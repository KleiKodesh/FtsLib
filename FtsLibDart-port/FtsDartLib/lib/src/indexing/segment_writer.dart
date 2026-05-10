import 'dart:io';
import 'dart:convert';
import 'package:sqlite3/sqlite3.dart' as sqlite3_pkg;

import 'ram_index.dart';

/// Static I/O helpers for writing segment files.
///
/// Owns two operations:
///   writeSegment  — serialises a RamIndex to a .dat posting file and its
///                   companion .db SQLite term-index file.
///   writeMetaDb   — writes (or rewrites) only the .db term-index file from
///                   a pre-built metadata list; used by SegmentMerger when
///                   producing a merged segment.
///
/// Both methods are stateless and safe to call from any isolate.
/// Uses the sqlite3 package for synchronous I/O (no async overhead on the
/// flush worker isolate).
class SegmentWriter {
  /// Writes a RamIndex to a new segment pair (.dat + .db).
  /// [sortedTerms] must be the terms from [ramIndex] sorted with
  /// the default string comparator (ordinal / code-unit order).
  ///
  /// Writes to .tmp files first, then renames atomically so a crash mid-write
  /// never leaves a corrupt file at the final path.
  ///
  /// Per-term record layout in .dat:
  ///   4 bytes  int    termByteLen
  ///   N bytes         term (UTF-8)
  ///   4 bytes  int    chunkByteLen
  ///   4 bytes  int    docCount
  ///   4 bytes  uint   lastEncoded
  ///   4 bytes  int    skipCount
  ///   skipCount × 12 bytes  skip table (int32 docId, int32 byteOffset, int32 prevEncoded)
  ///   M bytes         varint posting data
  static void writeSegment(
    RamIndex ramIndex,
    List<String> sortedTerms,
    String datPath,
    String dbPath,
  ) {
    final tmpDat = '$datPath.tmp';
    final tmpDb = '$dbPath.tmp';

    // Clean up any leftover .tmp files from a previous crash.
    _deleteIfExists(tmpDat);
    _deleteIfExists(tmpDb);

    try {
      final meta = <_TermMeta>[];

      // ── Write .dat file ──────────────────────────────────────
      final sink = File(tmpDat).openSync(mode: FileMode.writeOnly);
      // Build a lookup map from the entries iterable for O(1) access.
      final entryMap = {for (final e in ramIndex.entries) e.key: e.value};
      try {
        for (final term in sortedTerms) {
          final entry = entryMap[term]!;

          final termBytes = utf8.encode(term);
          final termByteLen = termBytes.length;
          final postBuf = entry.stream.buffer;
          final postLen = entry.stream.byteLength;
          final skipCount = entry.skipLen ~/ 3;

          // termByteLen (4 bytes LE)
          sink.writeFromSync(_int32LE(termByteLen));
          // term bytes
          sink.writeFromSync(termBytes);
          // chunkByteLen
          sink.writeFromSync(_int32LE(postLen));
          // docCount
          sink.writeFromSync(_int32LE(entry.stream.count));
          // lastEncoded (uint32)
          sink.writeFromSync(_uint32LE(entry.stream.lastEncoded));
          // skipCount
          sink.writeFromSync(_int32LE(skipCount));

          // skip table — each entry is 3 × int32
          final skipOff = sink.positionSync();
          if (entry.skip != null) {
            for (int i = 0; i < entry.skipLen; i++) {
              sink.writeFromSync(_int32LE(entry.skip![i]));
            }
          }

          // posting data
          final postOff = sink.positionSync();
          sink.writeFromSync(postBuf.sublist(0, postLen));

          meta.add(_TermMeta(
            term: term,
            skipOffset: skipOff,
            skipCount: skipCount,
            offset: postOff,
            length: postLen,
            count: entry.stream.count,
          ));
        }
      } finally {
        sink.closeSync();
      }

      // ── Write .db file ───────────────────────────────────────
      writeMetaDb(tmpDb, meta);

      // Both files fully written — rename atomically to final paths.
      File(tmpDat).renameSync(datPath);
      File(tmpDb).renameSync(dbPath);
    } catch (_) {
      // Clean up partial .tmp files so recovery does not see them.
      _deleteIfExists(tmpDat);
      _deleteIfExists(tmpDb);
      rethrow;
    }
  }

  /// Writes a SQLite term-index (.db) file from a pre-built metadata list.
  /// Used by SegmentMerger after writing the merged .dat file.
  static void writeMetaDb(String path, List<SegmentWriterTermMeta> rows) {
    final db = sqlite3_pkg.sqlite3.open(path);
    try {
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=NORMAL');
      db.execute('PRAGMA temp_store=MEMORY');
      db.execute('PRAGMA mmap_size=1073741824');
      db.execute('PRAGMA page_size=65536');

      db.execute(
        'CREATE TABLE term_index('
        'term TEXT NOT NULL,'
        'skip_offset INTEGER NOT NULL,'
        'skip_count INTEGER NOT NULL,'
        'offset INTEGER NOT NULL,'
        'length INTEGER NOT NULL,'
        'count INTEGER NOT NULL'
        ');',
      );

      // Bulk insert inside a single transaction for speed.
      final stmt = db.prepare(
        'INSERT INTO term_index'
        '(term,skip_offset,skip_count,offset,length,count) '
        'VALUES(?,?,?,?,?,?)',
      );
      try {
        db.execute('BEGIN;');
        for (final row in rows) {
          stmt.execute([
            row.term,
            row.skipOffset,
            row.skipCount,
            row.offset,
            row.length,
            row.count,
          ]);
        }
        db.execute('COMMIT;');
      } finally {
        stmt.dispose();
      }

      db.execute('CREATE UNIQUE INDEX idx_term ON term_index(term);');
      db.execute('ANALYZE;');
    } finally {
      db.dispose();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────

  static void _deleteIfExists(String path) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  /// Encodes [v] as a 4-byte little-endian signed int.
  static List<int> _int32LE(int v) => [
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ];

  /// Encodes [v] as a 4-byte little-endian unsigned int.
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

/// Metadata for one term — used to build the .db index.
/// Implemented by both [SegmentWriter] internally and [SegmentMerger].
abstract class SegmentWriterTermMeta {
  String get term;
  int get skipOffset;
  int get skipCount;
  int get offset;
  int get length;
  int get count;
}

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
