import 'dart:io';
import 'package:path/path.dart' as p;

// NOTE: SeforimIndex is imported from the fts_lib package.
// Until the Dart library is fully wired up (SegmentWriter/Reader translated),
// this service stubs the calls so the UI compiles and runs.
// Replace the stub section with real SeforimIndex calls once the library is complete.

/// Manages the FTS index lifecycle.
/// Mirrors the C# IndexService.
class IndexService {
  // ── State ─────────────────────────────────────────────────────

  bool _isReady = false;
  String _openDbPath = '';
  String _openIndexPath = '';

  bool get isReady => _isReady;
  String get openDbPath => _openDbPath;

  // ── Path helpers ─────────────────────────────────────────────

  /// Returns the index directory path for a given database file.
  String getIndexPath(String dbPath) {
    final name = p.basenameWithoutExtension(dbPath);
    // Place the index next to the executable / in the app's support directory.
    final dir = p.dirname(dbPath);
    return p.join(dir, '$name-fts-index');
  }

  /// Returns true when at least one segment file exists for [dbPath].
  bool indexExists(String dbPath) {
    final indexPath = getIndexPath(dbPath);
    final dir = Directory(indexPath);
    if (!dir.existsSync()) return false;
    return dir
        .listSync()
        .whereType<File>()
        .any((f) => f.path.endsWith('.dat') &&
            p.basename(f.path).startsWith('seg_'));
  }

  // ── Open / Close ─────────────────────────────────────────────

  /// Opens an existing index for searching.
  void open(String dbPath) {
    _openDbPath = dbPath;
    _openIndexPath = getIndexPath(dbPath);
    _isReady = true;
    // TODO: _index = SeforimIndex(_openIndexPath, dbPath);
  }

  void close() {
    _isReady = false;
    _openDbPath = '';
    _openIndexPath = '';
    // TODO: _index?.dispose();
  }

  // ── Build ────────────────────────────────────────────────────

  /// Builds the index for [dbPath], reporting progress via [onProgress].
  /// [onProgress] receives (linesIndexed, totalLines).
  /// Throws on error; caller should catch and display.
  Future<void> build(
    String dbPath, {
    required void Function(int indexed, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    final indexPath = getIndexPath(dbPath);

    // TODO: Replace stub with real SeforimIndex.buildIndex() call.
    // For now, simulate a build so the UI is exercisable.
    await _stubBuild(dbPath, indexPath, onProgress: onProgress, isCancelled: isCancelled);

    _openDbPath = dbPath;
    _openIndexPath = indexPath;
    _isReady = true;
  }

  // ── Search ────────────────────────────────────────────────────

  /// Searches the open index for [query].
  /// Yields [SearchResultItem] objects as they are found.
  /// [maxWordDistance] and [requireOrdered] mirror the C# search options.
  Stream<SearchResultItem> search(
    String query, {
    int maxWordDistance = 10,
    bool requireOrdered = false,
    bool Function()? isCancelled,
  }) async* {
    if (!_isReady) return;

    // TODO: Replace stub with real SeforimIndex.search() + generateSnippet() calls.
    yield* _stubSearch(query, maxWordDistance: maxWordDistance, isCancelled: isCancelled);
  }

  // ── Stubs (remove once library is fully wired) ────────────────

  Future<void> _stubBuild(
    String dbPath,
    String indexPath, {
    required void Function(int, int) onProgress,
    required bool Function() isCancelled,
  }) async {
    const total = 1000;
    for (int i = 0; i < total; i += 50) {
      if (isCancelled()) return;
      await Future.delayed(const Duration(milliseconds: 80));
      onProgress(i, total);
    }
    onProgress(total, total);
  }

  Stream<SearchResultItem> _stubSearch(
    String query, {
    int maxWordDistance = 10,
    bool Function()? isCancelled,
  }) async* {
    final terms = query.trim().split(RegExp(r'\s+'));
    for (int i = 1; i <= 30; i++) {
      if (isCancelled != null && isCancelled()) return;
      await Future.delayed(const Duration(milliseconds: 20));
      yield SearchResultItem(
        lineId: i,
        bookTitle: 'ספר לדוגמה $i',
        snippet: 'זהו קטע לדוגמה המכיל את המילה '
            '<mark>${terms.first}</mark> בתוך הטקסט.',
      );
    }
  }
}

// ── Data model ────────────────────────────────────────────────────

/// A single search result row — mirrors C# SearchResultItem.
class SearchResultItem {
  final int lineId;
  final String bookTitle;

  /// HTML snippet with <mark>…</mark> highlight tags.
  final String snippet;

  /// Plain-text version of the snippet (marks stripped) — for copy/select.
  late final String plainSnippet;

  SearchResultItem({
    required this.lineId,
    required this.bookTitle,
    required this.snippet,
  }) {
    plainSnippet = snippet
        .replaceAll('<mark>', '')
        .replaceAll('</mark>', '')
        .replaceAll('&amp;', '&')
        .replaceAll('&gt;', '>');
  }
}
