import 'dart:io';

import 'delete_set.dart';
import 'index_directory.dart';
import 'ram_index.dart';
import 'segment_store.dart';

/// Builds a full-text index by accepting (lineId, term) pairs and flushing
/// them to segment files. Line IDs must be added in strictly ascending order.
///
/// The index is stored as segment pairs (seg_L_ID.dat + seg_L_ID.db).
/// IndexReader can search at any point — mid-build or after dispose.
///
/// Flush pipeline: when a flush is triggered (threshold or forceFlush), the
/// current RamIndex is handed off to SegmentStore and a fresh one is started
/// immediately. The actual segment write runs as a background Future so the
/// indexing loop is never blocked on I/O. A depth-1 slot in SegmentStore
/// provides back-pressure: the next flush cannot start until the previous
/// flush write AND any triggered merge both finish.
class IndexWriter extends IndexDirectory {
  /// Flush the RamIndex when it reaches this many distinct terms.
  int flushThreshold = 500000;

  /// Threshold used for the very first flush only.
  /// 0 (default) = disabled, use [flushThreshold] from the start.
  int firstFlushThreshold = 100000;

  RamIndex _ramIndex;
  SegmentStore? _store;
  DeleteSet _deletes;
  final bool _useSkipList;
  bool _disposed = false;
  int _lastLineId = -2147483648; // int.minValue
  bool _flushPending = false;

  /// The highest line ID that has been fully written to a segment file on disk.
  int get lastFlushedLineId =>
      _store != null ? _store!.lastFlushedLineId : -2147483648;

  /// Returns a consistent snapshot of all live segment paths.
  List<(String dat, String db)> getLiveSegmentPaths() {
    if (_store == null) return [];
    return _store!.getLiveSegmentPaths();
  }

  /// Creates an IndexWriter that owns its own SegmentStore.
  /// Runs crash recovery if segments are found on disk.
  IndexWriter(String indexPath, {bool useSkipList = true})
      : _useSkipList = useSkipList,
        _ramIndex = RamIndex(useSkipList: useSkipList),
        _deletes = DeleteSet.load(''),
        super(indexPath) {
    _deletes = DeleteSet.load(deletesFile);

    final segDir = this.indexPath;
    final dir = Directory(segDir);
    bool hasSegments = dir.existsSync() &&
        (dir
                .listSync()
                .whereType<File>()
                .any((f) => f.path.endsWith('.dat') &&
                    f.path.split(Platform.pathSeparator).last.startsWith('seg_')) ||
            File('$segDir${Platform.pathSeparator}wal.log').existsSync());

    if (hasSegments) {
      print('[IndexWriter] Segments found — running crash recovery...');
      _store = SegmentStore(segDir);
      // CorruptIndexException propagates up — the caller (IndexingPipeline)
      // must catch it, delete the index directory, and restart from scratch.
      _store!.recover();
      print('[IndexWriter] Recovery complete.');
    }
  }

  /// Creates an IndexWriter that reuses an existing [SegmentStore].
  /// Recovery must have already been run on the store before passing it here.
  IndexWriter.withStore(String indexPath, SegmentStore store,
      {bool useSkipList = true})
      : _useSkipList = useSkipList,
        _ramIndex = RamIndex(useSkipList: useSkipList),
        _deletes = DeleteSet.load(''),
        _store = store,
        super(indexPath) {
    _deletes = DeleteSet.load(deletesFile);
  }

  /// Adds a (lineId, term) pair to the index.
  /// Line IDs must be strictly ascending across all add calls.
  Future<void> add(int lineId, String term) async {
    if (_disposed) throw StateError('IndexWriter is disposed');

    // If a flush was triggered on the previous line, execute it now —
    // before writing any terms for the new line, so no line is split
    // across two segments.
    if (_flushPending && lineId != _lastLineId) {
      await _flushRam();
      _flushPending = false;
    }

    _ramIndex.add(term, lineId);
    _lastLineId = lineId;

    // Arm the flush flag once the threshold is reached, but don't flush
    // yet — more terms for this same lineId may still arrive.
    int activeThreshold =
        (firstFlushThreshold > 0 && lastFlushedLineId == -2147483648)
            ? firstFlushThreshold
            : flushThreshold;
    if (_ramIndex.count >= activeThreshold) _flushPending = true;
  }

  /// Immediately hands the current RAM index off for background writing to a
  /// new level-0 segment, regardless of whether the flush threshold has been
  /// reached. Does nothing if the RAM index is empty.
  Future<void> forceFlush() async {
    if (_disposed) throw StateError('IndexWriter is disposed');
    _flushPending = false;
    await _flushRam();
  }

  /// Logically deletes a document from the index.
  void delete(int lineId) {
    if (_disposed) throw StateError('IndexWriter is disposed');
    _deletes.add(lineId);
    _deletes.save(deletesFile);
  }

  /// Permanently removes all deleted doc IDs from segment files by running a
  /// merge pass across all levels, then clears the delete set.
  Future<void> purge() async {
    if (_disposed) throw StateError('IndexWriter is disposed');

    await _flushRam();

    _store ??= SegmentStore(indexPath);

    // Drain any in-flight flush before starting the purge merge.
    await _store!.waitForMerge();

    print('[IndexWriter] Purging ${_deletes.count} deleted doc(s)...');
    _store!.setDeleteSet(_deletes);
    await _store!.mergeAllUnderMergeLock();
    _deletes.clear();
    _deletes.save(deletesFile); // removes the file
    _store!.setDeleteSet(null);
    print('[IndexWriter] Purge complete.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _flushRam();
      // Drain the entire background pipeline before exiting.
      await _store?.waitForMerge();
    } catch (_) {
      // swallow so dispose never throws
    }
    print('[IndexWriter] Done.');
  }

  // ── Private ──────────────────────────────────────────────────

  Future<void> _flushRam() async {
    if (_ramIndex.count == 0) return;

    _store ??= SegmentStore(indexPath);

    print('[IndexWriter] Scheduling flush of ${_ramIndex.count} terms...');

    // Hand the completed RamIndex to SegmentStore and start a fresh one
    // immediately. The actual write happens as a background Future inside flush().
    final batch = _ramIndex;
    _ramIndex = RamIndex(useSkipList: _useSkipList);

    await _store!.flush(batch, _lastLineId);

    print('[IndexWriter] Flush scheduled.');
  }
}
