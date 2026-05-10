import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Wraps the seforim SQLite database.
class ZayitDb {
  Database? _connection;
  final String dbPath;
  bool _disposed = false;

  bool get isOpen => _connection != null;

  ZayitDb(String? dbPath) : dbPath = _resolveDbPath(dbPath);

  /// Opens the database connection. Must be called before any query methods.
  Future<void> open() async {
    if (!File(dbPath).existsSync()) {
      print('[ZayitDb] Database not found: $dbPath');
      return;
    }

    print('[ZayitDb] Opening: $dbPath');
    _connection = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: false),
    );

    await _connection!.execute(
      'PRAGMA journal_mode=WAL;'
      'PRAGMA cache_size=-65536;'
      'PRAGMA temp_store=MEMORY;'
      'PRAGMA mmap_size=268435456;',
    );
  }

  // ── Indexing helpers ──────────────────────────────────────────

  Future<int> countLines() async {
    _ensureOpen();
    final rows = await _connection!.rawQuery('SELECT COUNT(*) FROM line');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<int> countLinesUpTo(int upToId) async {
    _ensureOpen();
    final rows = await _connection!
        .rawQuery('SELECT COUNT(*) FROM line WHERE id <= ?', [upToId]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<String?> getLineContent(int id) async {
    _ensureOpen();
    final rows = await _connection!
        .rawQuery('SELECT content FROM line WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return rows.first['content'] as String?;
  }

  Stream<(int id, String content)> readLines(int limit,
      {bool Function()? isCancelled}) async* {
    _ensureOpen();
    final sql = limit > 0
        ? 'SELECT id, content FROM line ORDER BY id LIMIT ?'
        : 'SELECT id, content FROM line ORDER BY id';
    final args = limit > 0 ? [limit] : null;
    final rows = await _connection!.rawQuery(sql, args);
    for (final r in rows) {
      if (isCancelled != null && isCancelled()) return;
      yield (r['id'] as int, (r['content'] as String?) ?? '');
    }
  }

  Stream<(int id, String content)> readLinesFrom(int afterId,
      {int limit = 0, bool Function()? isCancelled}) async* {
    _ensureOpen();
    final sql = limit > 0
        ? 'SELECT id, content FROM line WHERE id > ? ORDER BY id LIMIT ?'
        : 'SELECT id, content FROM line WHERE id > ? ORDER BY id';
    final args = limit > 0 ? [afterId, limit] : [afterId];
    final rows = await _connection!.rawQuery(sql, args);
    for (final r in rows) {
      if (isCancelled != null && isCancelled()) return;
      yield (r['id'] as int, (r['content'] as String?) ?? '');
    }
  }

  // ── Search result fetching ────────────────────────────────────

  /// Fetches all results for a pre-materialized ID list.
  /// Chunks to stay within SQLite's variable limit (999).
  Future<List<(int id, String content, String bookTitle)>> fetchSearchResults(
      List<int> ids) async {
    _ensureOpen();
    if (ids.isEmpty) return [];

    const chunkSize = 999;
    final result = <(int, String, String)>[];

    for (int start = 0; start < ids.length; start += chunkSize) {
      int end = (start + chunkSize).clamp(0, ids.length);
      final chunk = ids.sublist(start, end);
      final placeholders = chunk.map((_) => '?').join(',');
      final rows = await _connection!.rawQuery(
        'SELECT l.id, l.content, b.title'
        ' FROM line l LEFT JOIN book b ON b.id = l.bookId'
        ' WHERE l.id IN ($placeholders) ORDER BY l.id',
        chunk,
      );
      for (final r in rows) {
        result.add((
          r['id'] as int,
          (r['content'] as String?) ?? '',
          (r['title'] as String?) ?? '',
        ));
      }
    }
    return result;
  }

  /// Streaming overload — accepts a lazy ID iterable and fetches rows in
  /// batches of 200, yielding results as each batch completes.
  Stream<(int id, String content, String bookTitle)>
      fetchSearchResultsStreaming(Iterable<int> ids) async* {
    _ensureOpen();

    const chunkSize = 200;
    final chunk = <int>[];

    for (final id in ids) {
      chunk.add(id);
      if (chunk.length == chunkSize) {
        for (final row in await _fetchChunk(chunk)) yield row;
        chunk.clear();
      }
    }

    if (chunk.isNotEmpty) {
      for (final row in await _fetchChunk(chunk)) yield row;
    }
  }

  Future<List<(int, String, String)>> _fetchChunk(List<int> ids) async {
    final placeholders = ids.map((_) => '?').join(',');
    final rows = await _connection!.rawQuery(
      'SELECT l.id, l.content, b.title'
      ' FROM line l LEFT JOIN book b ON b.id = l.bookId'
      ' WHERE l.id IN ($placeholders)',
      ids,
    );
    return rows
        .map((r) => (
              r['id'] as int,
              (r['content'] as String?) ?? '',
              (r['title'] as String?) ?? '',
            ))
        .toList();
  }

  /// Fetches only id + bookTitle — no content column.
  Future<List<(int id, String bookTitle)>> fetchSearchResultsNoContent(
      List<int> ids) async {
    _ensureOpen();
    if (ids.isEmpty) return [];

    const chunkSize = 999;
    final result = <(int, String)>[];

    for (int start = 0; start < ids.length; start += chunkSize) {
      int end = (start + chunkSize).clamp(0, ids.length);
      final chunk = ids.sublist(start, end);
      final placeholders = chunk.map((_) => '?').join(',');
      final rows = await _connection!.rawQuery(
        'SELECT l.id, b.title'
        ' FROM line l JOIN book b ON b.id = l.bookId'
        ' WHERE l.id IN ($placeholders) ORDER BY l.bookId, l.lineIndex',
        chunk,
      );
      for (final r in rows) {
        result.add((r['id'] as int, (r['title'] as String?) ?? ''));
      }
    }
    return result;
  }

  // ── Diagnostic / test helpers ─────────────────────────────────

  Future<List<(int id, String content)>> findByPhrase(String phrase,
      {int limit = 20}) async {
    _ensureOpen();
    String escaped = phrase
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final rows = await _connection!.rawQuery(
      "SELECT id, content FROM line WHERE content LIKE ? ESCAPE '\\' LIMIT ?",
      ['%$escaped%', limit],
    );
    return rows
        .map((r) => (r['id'] as int, (r['content'] as String?) ?? ''))
        .toList();
  }

  Future<(String bookTitle, String heRef, String content)?> getLineInfo(
      int id) async {
    _ensureOpen();
    final rows = await _connection!.rawQuery(
      'SELECT b.title, l.heRef, l.content'
      ' FROM line l JOIN book b ON b.id = l.bookId'
      ' WHERE l.id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      (r['title'] as String?) ?? '',
      (r['heRef'] as String?) ?? '',
      (r['content'] as String?) ?? '',
    );
  }

  // ── Lifecycle ─────────────────────────────────────────────────

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _connection?.close();
    _connection = null;
  }

  // ── Helpers ───────────────────────────────────────────────────

  static String _resolveDbPath(String? dbPath) {
    if (dbPath != null && dbPath.isNotEmpty) return dbPath;
    // Default path mirrors the C# version's ApplicationData location.
    final home = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return '$home${Platform.pathSeparator}io.github.kdroidfilter.seforimapp'
        '${Platform.pathSeparator}databases${Platform.pathSeparator}seforim.db';
  }

  void _ensureOpen() {
    if (_connection == null) {
      throw StateError(
          'ZayitDb: database file was not found at open time.');
    }
  }
}
