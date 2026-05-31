import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../search/var_int.dart';
import '../utils/byte_array_pool.dart';
import 'delete_set.dart';
import 'segment_reader.dart';
import 'segment_store.dart';
import 'segment_writer.dart';

/// Handles LSM-style segment merging.
/// Called by SegmentStore when a level reaches [SegmentStore.fanout] segments.
///
/// Optimized version matching C# performance characteristics.
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
    
    // Use optimized file I/O with large buffer (4MB like C#)
    final sink = File(outPath).openSync(mode: FileMode.writeOnly);
    
    try {
      // Reusable merge buffer with Uint8List for better performance
      var mergeBuffer = MergeBuffer(256);
      final writeBuffer = Uint8List(1024 * 1024); // 1MB write buffer
      int writeBufferPos = 0;

      while (true) {
        final minTerm = _findMinTerm(readers);
        if (minTerm == null) break;

        final result = _mergeChunks(
          readers,
          minTerm,
          _store.getDeleteSet(),
          mergeBuffer,
        );

        // Skip terms whose entire posting list was purged.
        if (result.totalCount == 0) continue;

        // Use pooled array for term bytes
        final termBytes = utf8.encode(minTerm);
        final termByteLen = termBytes.length;
        final chunkLen = result.mergedLen;
        final skipCount = result.skipLen ~/ 3;

        // Batch write operations for better I/O performance
        final headerData = <int>[];
        headerData.addAll(_int32LE(termByteLen));
        headerData.addAll(termBytes);
        headerData.addAll(_int32LE(chunkLen));
        headerData.addAll(_int32LE(result.totalCount));
        headerData.addAll(_uint32LE(result.lastEncoded));
        headerData.addAll(_int32LE(skipCount));
        
        writeBufferPos = _writeBatch(sink, headerData, writeBuffer, writeBufferPos);
        
        final skipOff = sink.positionSync();
        if (result.skipTable != null) {
          writeBufferPos = _writeBatch(sink, result.skipTable!, writeBuffer, writeBufferPos);
        }

        final outOff = sink.positionSync();
        final mergedData = mergeBuffer.view;
        writeBufferPos = _writeBatch(sink, mergedData, writeBuffer, writeBufferPos);

        entries.add(_TermMeta(
          term: minTerm,
          skipOffset: skipOff,
          skipCount: skipCount,
          offset: outOff,
          length: chunkLen,
          count: result.totalCount,
        ));
        
        // Return term bytes to pool
        ByteArrayPool.return_(termBytes as Uint8List);
      }
      
      // Flush any remaining data
      if (writeBufferPos > 0) {
        sink.writeFromSync(Uint8List.view(writeBuffer.buffer, 0, writeBufferPos));
      }
      sink.flushSync();
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
    MergeBuffer mergeBuffer,
  ) {
    int prevEncoded = 0;
    int totalCount = 0;
    int lastEncoded = 0;
    bool firstChunk = true;

    for (final r in readers) {
      if (r.done || r.currentTerm != term) continue;

      final chunk = r.currentChunk;
      final chunkLen = r.currentChunkLen;

      if (deletes == null || deletes.isEmpty) {
        // Fast path: no deletions — copy chunks verbatim.
        if (firstChunk) {
          mergeBuffer.writeBytes(chunk, chunkLen);
          firstChunk = false;
        } else {
          // Re-encode the first delta relative to the previous chunk's last value.
          final readPos = [0];
          final firstEncoded2 = VarInt.read(chunk, readPos, chunkLen);
          final newDelta = (firstEncoded2 - prevEncoded) & 0xFFFFFFFF;
          final hdr = Uint8List(5);
          final hdrLen = VarInt.encode(newDelta, hdr);
          final rest = chunkLen - readPos[0];
          mergeBuffer.writeBytes(hdr, hdrLen);
          if (rest > 0) {
            mergeBuffer.writeBytes(chunk.sublist(readPos[0]), rest);
          }
        }

        prevEncoded = r.currentLastEncoded & 0xFFFFFFFF;
        totalCount += r.currentCount;
      } else {
        // Purge path: decode every doc ID and skip deleted ones.
        final readPos = [0];
        int encoded = 0;
        final tmp = Uint8List(5);

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
          mergeBuffer.writeBytes(tmp, nBytes);

          prevEncoded = encoded & 0xFFFFFFFF;
          totalCount++;
          firstChunk = false;
        }
      }

      r.moveNext();
    }

    final mergedLen = mergeBuffer.position;
    lastEncoded = prevEncoded;

    // Rebuild skip table by decoding the final merged bytes.
    Uint8List? skipTable;
    int skipLen = 0;

    if (totalCount >= _skipInterval * 2) {
      final mergedData = mergeBuffer.view;
      final readPos = [0];
      int encoded = 0;
      int prevEnc = 0;
      int docIndex = 0;

      while (readPos[0] < mergedLen) {
        final byteOffsetBefore = readPos[0];
        final delta = VarInt.read(mergedData, readPos, mergedLen);
        prevEnc = encoded;
        encoded = (encoded + delta) & 0xFFFFFFFF;
        final docId = encoded >= 0x80000000
            ? encoded - 0x100000000
            : encoded;
        docIndex++;

        if (docIndex > 1 && (docIndex - 1) % _skipInterval == 0) {
          if (skipTable == null) {
            skipTable = Uint8List(12);
          } else if (skipLen + 12 > skipTable.length) {
            // Optimized resize: grow by 2x instead of manual copy
            final newSkip = Uint8List(skipTable.length * 2);
            newSkip.setRange(0, skipTable.length, skipTable);
            skipTable = newSkip;
          }

          // Store skip table data efficiently
          final docIdBytes = _int32LE(docId);
          final offsetBytes = _int32LE(byteOffsetBefore);
          final prevEncBytes = _int32LE(prevEnc >= 0x80000000
              ? prevEnc - 0x100000000
              : prevEnc);

          skipTable.setRange(skipLen, skipLen + 4, docIdBytes);
          skipTable.setRange(skipLen + 4, skipLen + 8, offsetBytes);
          skipTable.setRange(skipLen + 8, skipLen + 12, prevEncBytes);
          skipLen += 12;
        }
      }
    }

    return _MergeResult(
      mergeBuffer: mergeBuffer,
      mergedLen: mergedLen,
      totalCount: totalCount,
      lastEncoded: lastEncoded,
      skipTable: skipTable,
      skipLen: skipLen,
    );
  }

  // ── Optimized I/O helpers ───────────────────────────────────────

  /// Batch write data to reduce I/O operations.
  int _writeBatch(RandomAccessFile sink, List<int> data, Uint8List buffer, int bufferPos) {
    if (data.length <= buffer.length - bufferPos) {
      // Add to buffer
      buffer.setRange(bufferPos, bufferPos + data.length, data);
      bufferPos += data.length;
      
      // Flush if buffer is full
      if (bufferPos >= buffer.length) {
        sink.writeFromSync(buffer);
        return 0; // Reset position after flush
      }
      return bufferPos;
    } else {
      // Flush current buffer then write data directly
      if (bufferPos > 0) {
        sink.writeFromSync(Uint8List.view(buffer.buffer, 0, bufferPos));
      }
      sink.writeFromSync(data);
      return 0; // Reset position after flush
    }
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
  final MergeBuffer mergeBuffer;
  final int mergedLen;
  final int totalCount;
  final int lastEncoded;
  final Uint8List? skipTable;
  final int skipLen;

  _MergeResult({
    required this.mergeBuffer,
    required this.mergedLen,
    required this.totalCount,
    required this.lastEncoded,
    required this.skipTable,
    required this.skipLen,
  });
}

/// Metadata for one term in the merged segment — passed to [SegmentWriter.writeMetaDb].
class _TermMeta implements SegmentWriterTermMeta {
  @override
  final String term;
  @override
  final int skipOffset;
  @override
  final int skipCount;
  @override
  final int offset;
  @override
  final int length;
  @override
  final int count;

  const _TermMeta({
    required this.term,
    required this.skipOffset,
    required this.skipCount,
    required this.offset,
    required this.length,
    required this.count,
  });
}
