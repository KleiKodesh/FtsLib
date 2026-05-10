import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'corrupt_index_exception.dart';
import 'delete_set.dart';
import 'index_merging_exception.dart';
import 'ram_index.dart';
import 'search_lease.dart';
import 'segment_live_state.dart';
import 'segment_merger.dart';
import 'segment_reader.dart';
import 'segment_wal.dart';
import 'segment_writer.dart';

// ── Isolate message types ─────────────────────────────────────────

/// Sent from the main isolate to the flush worker.
class _FlushRequest {
  final SendPort replyTo;
  final RamIndex ramIndex;
  final List<String> terms; // pre-sorted
  final String datPath;
  final String dbPath;

  _FlushRequest(this.replyTo, this.ramIndex, this.terms, this.datPath, this.dbPath);
}

/// Sent back from the flush worker via Isolate.exit() — zero-copy transfer.
/// Contains either null (success) or a String error message.
class _FlushReply {
  final String? error;
  const _FlushReply(this.error);
}

/// Entry point for the pre-spawned flush worker isolate.
/// Receives [_FlushRequest] messages, writes the segment, and replies via
/// [Isolate.exit()] so the result is transferred without copying.
void _flushWorkerMain(SendPort mainSendPort) {
  // Initialise sqflite_common_ffi in this isolate so sqlite3 native library
  // is available for SegmentWriter.writeMetaDb.
  sqfliteFfiInit();

  final receivePort = ReceivePort();
  // Send our receive port to the main isolate so it can send us work.
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is _FlushRequest) {
      try {
        SegmentWriterRef.writeSegmentSync(
            message.ramIndex, message.terms, message.datPath, message.dbPath);
        Isolate.exit(message.replyTo, const _FlushReply(null));
      } catch (e) {
        Isolate.exit(message.replyTo, _FlushReply(e.toString()));
      }
    }
  });
}

/// Orchestrates the segment lifecycle: flush pipeline and crash recovery.
///
/// Delegates to:
///   [SegmentLiveState] — registry of live segments
///   [SegmentWal]       — write-ahead log for crash safety
///   SegmentWriter      — stateless .dat + .db I/O
///   SegmentMerger      — LSM merge logic
///
/// Flush pipeline (non-blocking on the indexing isolate):
///   A dedicated flush worker isolate is pre-spawned once at construction time.
///   flush() sends a [_FlushRequest] to the worker and awaits a [_FlushReply]
///   returned via [Isolate.exit()] — zero-copy transfer of the reply object.
///   Because the worker exits after each reply, a new worker is spawned for the
///   next flush. This matches the article's finding: spawn outside the timed
///   section, use Isolate.exit() to skip the byte-copy on return.
///   A depth-1 back-pressure slot ensures at most one flush is in flight at a
///   time. After the write, mergeIfNeeded runs on the main isolate (it mutates
///   live state which cannot be shared across isolates).
///   waitForMerge() drains the entire pipeline.
///
/// Search / merge exclusion:
///   A simple boolean flag [_merging] guards the live segment list.
///   getLiveSegmentPaths() throws [IndexMergingException] when [_merging] is true.
class SegmentStore {
  static const int fanout = 4;

  final SegmentLiveState live;
  final SegmentWal wal;

  late final SegmentMerger _merger;
  DeleteSet? _deleteSet;
  final String _dir;

  // Merge exclusion flag — true while a merge is running.
  bool _merging = false;

  // Active reader count — merge waits until this reaches 0.
  int _activeReaders = 0;
  Completer<void>? _readersGoneCompleter;

  // Flush pipeline
  Future<void> _pipelineTask = Future.value();
  bool _flushSlotFree = true;
  Completer<void>? _flushSlotCompleter;

  // Pre-spawned flush worker.
  // _workerSendPort is the port to send _FlushRequest messages to.
  // We keep a Future so the first flush awaits the spawn if it hasn't finished.
  Future<SendPort>? _workerReady;

  /// The highest line ID that has been fully written to a segment file on disk.
  int lastFlushedLineId = -2147483648; // int.minValue

  /// Set to true when wipeIndexDirectory() is called during recovery.
  bool isWiped = false;

  SegmentStore(this._dir)
      : live = SegmentLiveState(_dir),
        wal = SegmentWal(_dir) {
    final dir = Directory(_dir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _merger = SegmentMerger(this);
    // Pre-spawn the flush worker so the first flush doesn't pay spawn cost.
    _workerReady = _spawnWorker();
  }

  /// Spawns a fresh flush worker isolate and returns its [SendPort].
  /// The worker sends its own receive port back as the first message.
  Future<SendPort> _spawnWorker() async {
    final mainPort = ReceivePort();
    await Isolate.spawn(_flushWorkerMain, mainPort.sendPort);
    // First message from the worker is its SendPort.
    final workerSendPort = await mainPort.first as SendPort;
    mainPort.close();
    return workerSendPort;
  }

  // ── Delete set ────────────────────────────────────────────────

  void setDeleteSet(DeleteSet? ds) => _deleteSet = ds;
  DeleteSet? getDeleteSet() => _deleteSet;

  // ── Live segment paths ────────────────────────────────────────

  /// Returns a consistent snapshot of all live segment paths.
  /// Throws [IndexMergingException] if a merge is currently in progress.
  List<(String dat, String db)> getLiveSegmentPaths() {
    if (_merging) throw IndexMergingException();
    return live.getLiveSegmentPaths();
  }

  /// Returns a consistent snapshot of all live segment paths together with a
  /// [SearchLease] that keeps the reader count elevated for the caller's lifetime.
  ///
  /// The caller MUST call [SearchLease.dispose] when the search is complete.
  SearchLease acquireSearchLease(
      {required void Function(List<(String, String)>) onPaths}) {
    if (_merging) throw IndexMergingException();

    _activeReaders++;
    final paths = live.getLiveSegmentPaths();
    onPaths(paths);

    return SearchLease(() {
      _activeReaders--;
      if (_activeReaders == 0) {
        _readersGoneCompleter?.complete();
        _readersGoneCompleter = null;
      }
    });
  }

  // ── Recovery ─────────────────────────────────────────────────

  Future<void> recover() async {
    // Step 1: find the highest segment ID ever allocated.
    int maxSegId = -1;
    final dir = Directory(_dir);
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        final base = f.path.split(Platform.pathSeparator).last;
        if (!base.startsWith('seg_')) continue;
        // strip .tmp if present
        String name = base.endsWith('.tmp')
            ? base.substring(0, base.length - 4)
            : base;
        name = name.replaceAll('.dat', '').replaceAll('.db', '');
        final parts = name.split('_');
        if (parts.length == 3) {
          final segId = int.tryParse(parts[2]);
          if (segId != null && segId > maxSegId) maxSegId = segId;
        }
      }
    }

    // Also scan the WAL for any target segment IDs.
    final walRecovery = wal.analyze();
    if (walRecovery.pendingMerge != null &&
        walRecovery.pendingMerge!.target > maxSegId) {
      maxSegId = walRecovery.pendingMerge!.target;
    }

    // Step 2: delete all .tmp files.
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.tmp')) {
          try { f.deleteSync(); } catch (_) {}
        }
      }
      // Step 2b: delete .del tombstones from older builds.
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.del')) {
          try { f.deleteSync(); } catch (_) {}
        }
      }
      // Step 2c: clean up orphaned SQLite WAL files.
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.endsWith('.db-shm') || f.path.endsWith('.db-wal')) {
          final dbFile = f.path
              .replaceAll('-shm', '')
              .replaceAll('-wal', '');
          if (!File(dbFile).existsSync()) {
            try { f.deleteSync(); } catch (_) {}
          }
        }
      }
    }

    // Step 3: rebuild live state from disk.
    live.rebuildFromDisk(maxSegId: maxSegId);

    // Step 4: validate all segment files.
    try {
      await _validateAllSegments();
    } on FormatException catch (ex) {
      print('[Recovery] Corrupt segment detected during validation — wiping index for rebuild: ${ex.message}');
      _wipeIndexDirectory();
      throw CorruptIndexException(
          'Corrupt segment detected during validation — index wiped for rebuild.',
          ex);
    }

    // Step 5: check for interrupted merge and redo it if needed.
    if (walRecovery.pendingMerge == null) return;

    final op = walRecovery.pendingMerge!;
    print('[Recovery] Interrupted merge: L${op.level} → target ${op.target}');

    String targetDat = live.segDatPath(op.level + 1, op.target);
    String targetDb = live.segDbPath(op.level + 1, op.target);

    bool targetExists =
        File(targetDat).existsSync() && File(targetDb).existsSync();
    bool sourcesExist = false;
    for (final sid in op.sources) {
      if (File(live.segDatPath(op.level, sid)).existsSync()) {
        sourcesExist = true;
        break;
      }
    }

    if (targetExists && !sourcesExist) {
      // Case B: sources already deleted, target is complete — register it.
      print('[Recovery] Merge was complete (sources gone, target exists) — registering target and clearing WAL');
      live.addToLive(op.level + 1, op.target);
      wal.open();
      wal.endMerge(op.level, op.target);
      wal.close();
      return;
    }

    // Sources still exist (or target is missing/partial) — delete any partial
    // target and re-run the merge from the source segments.
    _deleteIfExists(targetDat);
    _deleteIfExists(targetDb);
    _deleteIfExists('$targetDb-shm');
    _deleteIfExists('$targetDb-wal');
    live.removeFromLive(op.level + 1, op.target);

    for (final sid in op.sources) {
      if (File(live.segDatPath(op.level, sid)).existsSync()) {
        live.addToLive(op.level, sid);
      }
    }
    if (!sourcesExist) {
      print('[Recovery] Neither merge target nor source segments exist — wiping index for rebuild');
      _wipeIndexDirectory();
      throw CorruptIndexException(
          'Merge source segments missing and target incomplete — index wiped for rebuild.',
          null);
    }

    wal.open();
    try {
      await _merger.mergeLevel(op.level, targetSegId: op.target);
    } on FormatException catch (ex) {
      print('[Recovery] Corrupt segment detected during merge — wiping index for rebuild: ${ex.message}');
      wal.close();
      _wipeIndexDirectory();
      throw CorruptIndexException(
          'Corrupt segment detected during merge — index wiped for rebuild.',
          ex);
    } finally {
      wal.close();
    }
  }

  Future<void> _validateAllSegments() async {
    final paths = live.getLiveSegmentPaths();
    for (final (dat, db) in paths) {
      if (!File(dat).existsSync()) {
        throw FormatException('Segment .dat file missing: $dat');
      }
      if (!File(db).existsSync()) {
        throw FormatException('Segment .db file missing: $db');
      }
      // Validate the .dat file by reading the first record header.
      try {
        final reader = SegmentReader(dat);
        try {
          reader.moveNext(); // throws FormatException on corrupt data
        } finally {
          reader.dispose();
        }
      } catch (ex) {
        throw FormatException('Corrupt segment file: $dat', ex);
      }
    }
  }

  void _wipeIndexDirectory() {
    isWiped = true;
    final dir = Directory(_dir);
    if (!dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      try { f.deleteSync(); } catch (_) {}
    }
  }

  // ── Flush ─────────────────────────────────────────────────────

  /// Schedules [ramIndex] to be written to a new level-0 segment and returns
  /// immediately. Ownership of [ramIndex] transfers to the flush worker isolate.
  ///
  /// The actual segment write runs in a pre-spawned worker isolate. The reply
  /// is returned via [Isolate.exit()] — zero-copy transfer back to this isolate.
  /// A new worker is pre-spawned immediately after each reply so the next flush
  /// never pays the spawn cost.
  ///
  /// If the previous flush write is still in flight, this call awaits it first
  /// (depth-1 back-pressure), then returns.
  Future<void> flush(RamIndex ramIndex, int lineId) async {
    // Back-pressure: wait until the previous flush+merge cycle is free.
    if (!_flushSlotFree) {
      _flushSlotCompleter ??= Completer<void>();
      await _flushSlotCompleter!.future;
    }
    _flushSlotFree = false;

    int segId = live.nextSegId();
    String datPath = live.segDatPath(0, segId);
    String dbPath = live.segDbPath(0, segId);

    // Sort terms on the calling side — cheap, keeps the worker I/O-only.
    final terms = ramIndex.entries.map((e) => e.key).toList()..sort();

    _pipelineTask = _pipelineTask.then((_) async {
      try {
        // Await the pre-spawned worker (ready immediately after the first flush).
        final workerSendPort = await _workerReady!;

        // Open a one-shot reply port for this flush.
        final replyPort = ReceivePort();

        // Send the work to the worker. The worker will call Isolate.exit()
        // with a _FlushReply, transferring it zero-copy to this isolate.
        workerSendPort.send(_FlushRequest(
          replyPort.sendPort,
          ramIndex,
          terms,
          datPath,
          dbPath,
        ));

        // Pre-spawn the NEXT worker now, while the current one is writing.
        // By the time we need it, it will already be ready.
        _workerReady = _spawnWorker();

        // Await the zero-copy reply from Isolate.exit().
        final reply = await replyPort.first as _FlushReply;
        replyPort.close();

        if (reply.error != null) {
          throw StateError('Flush worker failed: ${reply.error}');
        }

        live.addToLive(0, segId);
        lastFlushedLineId = lineId;

        // Merge runs on the main isolate — it mutates live state.
        wal.open();
        try {
          _merging = true;
          try {
            await _merger.mergeIfNeeded(0);
          } finally {
            _merging = false;
          }
        } finally {
          wal.close();
        }
      } finally {
        _flushSlotFree = true;
        final c = _flushSlotCompleter;
        _flushSlotCompleter = null;
        c?.complete();
      }
    });
  }

  // ── Pipeline drain ────────────────────────────────────────────

  /// Waits for all pending flush writes and any triggered LSM merges to finish.
  Future<void> waitForMerge() async {
    try {
      await _pipelineTask;
    } catch (e) {
      print('[SegmentStore] Pipeline exception (non-fatal): $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────

  /// Runs a merge pass across every level that has more than one segment.
  /// Used by Purge to physically remove deleted doc IDs from all segments.
  Future<void> mergeAllUnderMergeLock() async {
    wal.open();
    try {
      _merging = true;
      try {
        bool progress;
        do {
          progress = false;
          for (final level in live.getLevelsWithMultiple()) {
            live.ensureLevel(level + 1);
            await _merger.mergeLevel(level);
            progress = true;
            break; // restart after each merge — level counts change
          }
        } while (progress);
      } finally {
        _merging = false;
      }
    } finally {
      wal.clear();
    }
  }

  static void _deleteIfExists(String path) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }
}

// ── Flush worker helper ───────────────────────────────────────────
// SegmentWriterRef delegates to the real SegmentWriter.
// Called from the flush worker isolate — must be a top-level function
// or static method so it can be sent across isolate boundaries.

class SegmentWriterRef {
  /// Synchronous write — called from the flush worker isolate.
  static void writeSegmentSync(
      RamIndex ramIndex, List<String> terms, String datPath, String dbPath) {
    SegmentWriter.writeSegment(ramIndex, terms, datPath, dbPath);
  }
}
