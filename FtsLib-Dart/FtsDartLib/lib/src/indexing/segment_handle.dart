import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sqlite3_pkg;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Location of one term's posting data within a segment.
class SegmentChunk {
  final SegmentHandle seg;

  /// Byte offset of the skip table in the .dat file (0 when no skip table).
  final int skipOffset;

  /// Number of skip entries (triplets). 0 means no skip table.
  final int skipCount;

  /// Byte offset of the posting data in the .dat file.
  final int offset;
  final int length;
  final int count;

  SegmentChunk(this.seg, this.skipOffset, this.skipCount,
      this.offset, this.length, this.count);
}

/// Holds open resources for one segment pair (.dat + .db).
///
/// Uses two database handles:
///   [_db]     — async sqflite Database for LIKE queries (wildcard/fuzzy expansion)
///   [_dbSync] — synchronous sqlite3 Database for the search hot path
///               (term lookup during posting list intersection)
class SegmentHandle {
  final String datPath;

  /// Async database — used for LIKE queries (wildcard/fuzzy expansion).
  final Database _db;

  /// Synchronous database — used for the term lookup hot path.
  final sqlite3_pkg.Database _dbSync;

  /// Cached prepared statement for synchronous term lookup — avoids
  /// re-preparing on every call during posting list intersection.
  late final sqlite3_pkg.PreparedStatement _lookupStmt;

  final RandomAccessFile dataStream;

  SegmentHandle._({
    required this.datPath,
    required Database db,
    required sqlite3_pkg.Database dbSync,
    required this.dataStream,
  })  : _db = db,
        _dbSync = dbSync {
    // Pre-prepare the term lookup statement — reused on every search call.
    _lookupStmt = _dbSync.prepare(
      'SELECT skip_offset, skip_count, offset, length, count '
      'FROM term_index WHERE term = ?',
      persistent: true,
    );
  }

  /// Opens a segment handle. Must be called with await.
  static Future<SegmentHandle> open(String datPath, String dbPath) async {
    final dataStream = await File(datPath).open(mode: FileMode.read);
    try {
      // Async handle for LIKE queries.
      final db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      // Synchronous handle for the search hot path.
      final dbSync = sqlite3_pkg.sqlite3.open(dbPath, mode: sqlite3_pkg.OpenMode.readOnly);
      return SegmentHandle._(
          datPath: datPath, db: db, dbSync: dbSync, dataStream: dataStream);
    } catch (_) {
      await dataStream.close();
      rethrow;
    }
  }

  // ── Synchronous term lookup (search hot path) ─────────────────

  /// Looks up a term synchronously — used during posting list intersection.
  SegmentChunk? lookupTermSync(String term) {
    final result = _lookupStmt.select([term]);
    if (result.isEmpty) return null;
    final r = result.first;
    return SegmentChunk(
      this,
      r['skip_offset'] as int,
      r['skip_count'] as int,
      r['offset'] as int,
      r['length'] as int,
      r['count'] as int,
    );
  }

  // ── Async term lookup (used by IndexReader.getTermCount) ──────

  Future<SegmentChunk?> lookupTerm(String term) async {
    final rows = await _db.rawQuery(
      'SELECT skip_offset, skip_count, offset, length, count '
      'FROM term_index WHERE term = ?',
      [term],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return SegmentChunk(
      this,
      r['skip_offset'] as int,
      r['skip_count'] as int,
      r['offset'] as int,
      r['length'] as int,
      r['count'] as int,
    );
  }

  // ── LIKE queries (wildcard/fuzzy expansion) ───────────────────

  /// Queries terms matching a LIKE pattern — async, used by wildcard/fuzzy expanders.
  Future<List<String>> queryTermsLike(String likePattern) async {
    final rows = await _db.rawQuery(
      "SELECT term FROM term_index WHERE term LIKE ? ESCAPE '\\'",
      [likePattern],
    );
    return rows.map((r) => r['term'] as String).toList();
  }

  /// Queries terms matching multiple LIKE patterns (OR) — async.
  Future<List<String>> queryTermsLikeAny(List<String> likePatterns) async {
    if (likePatterns.isEmpty) return [];
    final sb = StringBuffer('SELECT term FROM term_index WHERE ');
    for (int i = 0; i < likePatterns.length; i++) {
      if (i > 0) sb.write(" OR ");
      sb.write("term LIKE ? ESCAPE '\\'");
    }
    final rows = await _db.rawQuery(sb.toString(), likePatterns);
    return rows.map((r) => r['term'] as String).toList();
  }

  /// Returns true if the exact term exists in this segment.
  Future<bool> termExists(String term) async {
    final rows = await _db.rawQuery(
      'SELECT 1 FROM term_index WHERE term = ? LIMIT 1',
      [term],
    );
    return rows.isNotEmpty;
  }

  Future<void> dispose() async {
    _lookupStmt.dispose();
    await _db.close();
    _dbSync.dispose();
    await dataStream.close();
  }
}
