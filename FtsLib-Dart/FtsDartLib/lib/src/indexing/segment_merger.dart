import 'dart:convert';
import 'dart:io';

import '../search/var_int.dart';
import 'delete_set.dart';
import 'segment_reader.dart';
import 'segment_store.dart';
import 'segment_writer.dart';

/// Handles LSM-style segment merging.
/// Called by SegmentStore when a level reaches [SegmentStore.fanout] segments.
///
/// Ported from C# SegmentMerger — logic is identical.
class SegmentMerger {
  final SegmentStore _store;

  SegmentMerger(this._store);

  // ── Cascade ──────────────────────────────────────────────────

  Future<void> mergeIfNeeded(int level) async {
    if (_store.live.liveSegCount(level) < SegmentStore.fanout) return;
    _store.live.ensureLevel(level + 1);
    await mergeLevel(level);
    await mergeIfNeeded(level + 1);
  }

  // ── Core merge ───────────────────────────────────────────────

  Future<void> mergeLevel(int level, {int? targetSegId}) async {
    final segIds = _store.live.getLiveSegIds(level);
    if (segIds.length < 2) return;

    int newSegId = targetSegId ?? _store.live.nextSegId();
    int nextLevel = level + 1;
    String outDat = _store.live.segDatPath(nextLevel, newSegId);
    String outDb = _store.live.segDbPath(nextLevel, newSegId);

    String tmpDat = '$outDat.tmp';
    String tmpDb = '$outDb.tmp';

    print('[Merger] L$level→L$nextLevel seg $newSegId: ${segIds.length} segs');

    _store.wal.beginMerge(level, segIds, newSegId);

    _deleteIfExists(tmpDat);
    _deleteIfExists(tmpDb);

    final readers = _openReaders(level, segIds);
    final List<SegmentWriterTermMeta> entries =
        _writeMergedDat(level, nextLevel, readers, tmpDat);
    _closeReaders(readers);

    SegmentWriter.writeMetaDb(tmpDb, entries);

    File(tmpDat).renameSync(outDat);
    File(tmpDb).renameSync(outDb);

    // Register the target segment as live BEFORE deleting sources.
    _store.wal.endMerge(level, newSegId);
    _store.live.promoteSegment(level, segIds, nextLevel, newSegId);

    // Delete the source segments.
    for (final sid in segIds) {
      _deleteIfExists(_store.live.segDatPath(level, sid));
      _deleteIfExists(_store.live.segDbPath(level, sid));
      _deleteIfExists('${_store.live.segDbPath(level, sid)}-shm');
      _deleteIfExists('${_store.live.segDbPath(level, sid)}-wal');
    }

    print('[Merger] Done → L$nextLevel seg $newSegId (${entries.length} terms)');
  }

  // ── Merge write ──────────────────────────────────────────────

  List<SegmentWriterTermMeta> _writeMergedDat(
    int srcLevel,
    int dstLevel,
    List<SegmentReader> readers,
    String outPath,
  ) {
    final entries = <_TermMeta>[];
    final sink = File(outPath).openSync(mode: FileMode.writeOnly);

    // Reusable merge buffer — grown as needed.
    var mergeBuffer = List<int>.filled(256, 0, growable: true);

    try {
      while (true) {
        final minTerm = _findMinTerm(readers);
        if (minTerm == null) break;

        final result = _mergeChunks(
          readers,
          minTerm,
          _store.getDeleteSet(),
          mergeBuffer,
        );
        mergeBuffer = result.buf;

        // Skip terms whose entire posting list was purged.
        if (result.totalCount == 0) continue;

        final termBytes = utf8.encode(minTerm);
        final termByteLen = termBytes.length;
        final chunkLen = result.mergedLen;
        final skipCount = result.skipLen ~/ 3;

        sink.writeFromSync(_int32LE(termByteLen));
        sink.writeFromSync(termBytes);
        sink.writeFromSync(_int32LE(chunkLen));
        sink.writeFromSync(_int32LE(result.totalCount));
        sink.writeFromSync(_uint32LE(result.lastEncoded));
        sink.writeFromSync(_int32LE(skipCount));

        final skipOff = sink.positionSync();
        if (result.skipTable != null) {
          for (int i = 0; i < result.skipLen; i++) {
            sink.writeFromSync(_int32LE(result.skipTable![i]));
          }
        }

        final outOff = sink.positionSync();
        sink.writeFromSync(mergeBuffer.sublist(0, chunkLen));

        entries.add(_TermMeta(
          term: minTerm,
          skipOffset: skipOff,
          skipCount: skipCount,
          offset: outOff,
          length: chunkLen,
          count: result.totalCount,
        ));
      }
    } finally {
      sink.closeSync();
    }

    return entries;
  }

  // ── Chunk merge ──────────────────────────────────────────────

  static const int _skipInterval = 128;

  _MergeResult _mergeChunks(
    List<SegmentReader> readers,
    String term,
    DeleteSet? deletes,
    List<int> buf,
  ) {
    int prevEncoded = 0;
    int totalCount = 0;
    int lastEncoded = 0;
    bool firstChunk = true;
    int pos = 0; // write cursor into buf

    for (final r in readers) {
      if (r.done || r.currentTerm != term) continue;

      final chunk = r.currentChunk;
      final chunkLen = r.currentChunkLen;

      if (deletes == null || deletes.isEmpty) {
        // Fast path: no deletions — copy chunks verbatim.
        if (firstChunk) {
          buf = _ensureCapacity(buf, pos + chunkLen);
          buf.setRange(pos, pos + chunkLen, chunk);
          pos += chunkLen;
          firstChunk = false;
        } else {
          // Re-encode the first delta relative to the previous chunk's last value.
          final readPos = [0];
          final firstEncoded2 = VarInt.read(chunk, readPos, chunkLen);
          final newDelta = (firstEncoded2 - prevEncoded) & 0xFFFFFFFF;
          final hdr = List<int>.filled(5, 0);
          final hdrLen = VarInt.encode(newDelta, hdr);
          final rest = chunkLen - readPos[0];
          buf = _ensureCapacity(buf, pos + hdrLen + rest);
          buf.setRange(pos, pos + hdrLen, hdr);
          pos += hdrLen;
          if (rest > 0) {
            buf.setRange(pos, pos + rest, chunk, readPos[0]);
            pos += rest;
          }
        }

        prevEncoded = r.currentLastEncoded & 0xFFFFFFFF;
        totalCount += r.currentCount;
      } else {
        // Purge path: decode every doc ID and skip deleted ones.
        final readPos = [0];
        int encoded = 0;
        final tmp = List<int>.filled(5, 0);

        while (readPos[0] < chunkLen) {
          final delta = VarInt.read(chunk, readPos, chunkLen);
          encoded = (encoded + delta) & 0xFFFFFFFF;
          // Convert uint32 encoded value back to signed int32 doc ID.
          final docId = encoded >= 0x80000000
              ? encoded - 0x100000000
              : encoded;

          if (deletes.contains(docId)) continue;

          final outDelta = firstChunk
              ? encoded & 0xFFFFFFFF
              : (encoded - prevEncoded) & 0xFFFFFFFF;
          final nBytes = VarInt.encode(outDelta, tmp);
          buf = _ensureCapacity(buf, pos + nBytes);
          buf.setRange(pos, pos + nBytes, tmp);
          pos += nBytes;

          prevEncoded = encoded & 0xFFFFFFFF;
          totalCount++;
          firstChunk = false;
        }
      }

      r.moveNext();
    }

    final mergedLen = pos;
    lastEncoded = prevEncoded;

    // Rebuild skip table by decoding the final merged bytes.
    List<int>? skipTable;
    int skipLen = 0;

    if (totalCount >= _skipInterval * 2) {
      final readPos = [0];
      int encoded = 0;
      int prevEnc = 0;
      int docIndex = 0;

      while (readPos[0] < mergedLen) {
        final byteOffsetBefore = readPos[0];
        final delta = VarInt.read(buf, readPos, mergedLen);
        prevEnc = encoded;
        encoded = (encoded + delta) & 0xFFFFFFFF;
        final docId = encoded >= 0x80000000
            ? encoded - 0x100000000
            : encoded;
        docIndex++;

        if (docIndex > 1 && (docIndex - 1) % _skipInterval == 0) {
          skipTable ??= List<int>.filled(12, 0, growable: true);
          if (skipLen + 3 > skipTable.length) {
            final newSkip = List<int>.filled(skipTable.length * 2, 0, growable: true);
            for (int i = 0; i < skipLen; i++) newSkip[i] = skipTable[i];
            skipTable = newSkip;
          }
          skipTable[skipLen] = docId;
          skipTable[skipLen + 1] = byteOffsetBefore;
          // Store prevEnc as signed int32 — matches C# skip table format.
          skipTable[skipLen + 2] = prevEnc >= 0x80000000
              ? prevEnc - 0x100000000
              : prevEnc;
          skipLen += 3;
        }
      }
    }

    return _MergeResult(
      buf: buf,
      mergedLen: mergedLen,
      totalCount: totalCount,
      lastEncoded: lastEncoded,
      skipTable: skipTable,
      skipLen: skipLen,
    );
  }

  static List<int> _ensureCapacity(List<int> buf, int required) {
    if (required <= buf.length) return buf;
    int newSize = buf.length;
    while (newSize < required) newSize *= 2;
    final newBuf = List<int>.filled(newSize, 0, growable: true);
    newBuf.setRange(0, buf.length, buf);
    return newBuf;
  }

  // ── Helpers ──────────────────────────────────────────────────

  List<SegmentReader> _openReaders(int level, List<int> segIds) {
    final readers = segIds
        .map((sid) => SegmentReader(_store.live.segDatPath(level, sid)))
        .toList();
    for (final r in readers) r.moveNext();
    return readers;
  }

  static void _closeReaders(List<SegmentReader> readers) {
    for (final r in readers) r.dispose();
  }

  static String? _findMinTerm(List<SegmentReader> readers) {
    String? min;
    for (final r in readers) {
      if (r.done) continue;
      if (min == null || r.currentTerm.compareTo(min) < 0) {
        min = r.currentTerm;
      }
    }
    return min;
  }

  static void _deleteIfExists(String path) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  static List<int> _int32LE(int v) => [
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ];

  static List<int> _uint32LE(int v) {
    final u = v & 0xFFFFFFFF;
    return [
      u & 0xFF,
      (u >> 8) & 0xFF,
      (u >> 16) & 0xFF,
      (u >> 24) & 0xFF,
    ];
  }
}

class _MergeResult {
  final List<int> buf;
  final int mergedLen;
  final int totalCount;
  final int lastEncoded;
  final List<int>? skipTable;
  final int skipLen;

  _MergeResult({
    required this.buf,
    required this.mergedLen,
    required this.totalCount,
    required this.lastEncoded,
    required this.skipTable,
    required this.skipLen,
  });
}

/// Metadata for one term in the merged segment — passed to [SegmentWriter.writeMetaDb].
class _TermMeta implements SegmentWriterTermMeta {
  @override final String term;
  @override final int skipOffset;
  @override final int skipCount;
  @override final int offset;
  @override final int length;
  @override final int count;

  const _TermMeta({
    required this.term,
    required this.skipOffset,
    required this.skipCount,
    required this.offset,
    required this.length,
    required this.count,
  });
}
