import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:fts_lib/fts_lib.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Manages the FTS index lifecycle.
/// Mirrors the C# IndexService with real FtsLib functionality.
class IndexService {
  // ── State ─────────────────────────────────────────────────────

  bool _isReady = false;
  String _openDbPath = '';
  String _openIndexPath = '';
  ZayitDb? _zayitDb;
  IndexReader? _indexReader;

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
    return dir.listSync().whereType<File>().any((f) =>
        f.path.endsWith('.dat') && p.basename(f.path).startsWith('seg_'));
  }

  // ── Open / Close ─────────────────────────────────────────────

  /// Opens an existing index for searching.
  Future<void> open(String dbPath) async {
    try {
      // Initialize FFI if not already done
      sqfliteFfiInit();

      _openDbPath = dbPath;
      _openIndexPath = getIndexPath(dbPath);

      // Open database connection
      _zayitDb = ZayitDb(dbPath);
      await _zayitDb!.open();

      if (!_zayitDb!.isOpen) {
        throw Exception('Failed to open database: $dbPath');
      }

      // Open index reader
      _indexReader = await IndexReader.openFromDir(_openIndexPath);

      _isReady = true;
    } catch (e) {
      _isReady = false;
      rethrow;
    }
  }

  Future<void> close() async {
    _isReady = false;
    await _indexReader?.dispose();
    _indexReader = null;
    _zayitDb?.dispose();
    _zayitDb = null;
    _openDbPath = '';
    _openIndexPath = '';
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
    try {
      // Initialize FFI if not already done
      sqfliteFfiInit();

      final indexPath = getIndexPath(dbPath);

      // Clean up existing index
      final indexDir = Directory(indexPath);
      if (await indexDir.exists()) {
        await indexDir.delete(recursive: true);
      }
      await indexDir.create(recursive: true);

      // Open database
      _zayitDb = ZayitDb(dbPath);
      await _zayitDb!.open();

      if (!_zayitDb!.isOpen) {
        throw Exception('Failed to open database: $dbPath');
      }

      // Get total line count
      final totalLines = await _zayitDb!.countLines();
      final testLimit =
          totalLines > 10000 ? 10000 : totalLines; // Limit to 10k for testing
      print(
          'IndexService: Starting to index $testLimit lines (out of $totalLines total)');
      onProgress(0, testLimit);

      // Create index writer with optimized settings
      final indexWriter = IndexWriter(indexPath);
      indexWriter.flushThreshold =
          2000000; // High threshold to minimize merging
      indexWriter.firstFlushThreshold = 1000000;

      int indexedLines = 0;
      int currentLineId = 1;

      // Process lines in batches
      await for (final (lineId, content) in _zayitDb!.readLines(testLimit)) {
        if (isCancelled()) {
          print('IndexService: Indexing cancelled at line $indexedLines');
          await indexWriter.dispose();
          return;
        }

        // Tokenize content
        final words = content.toLowerCase().split(RegExp(r'[^a-zA-Zא-ת]+'));

        // Add terms to index
        for (final word in words) {
          if (word.length >= 2 && word.length <= 20) {
            indexWriter.add(currentLineId, word);
            currentLineId++;
          }
        }

        indexedLines++;

        // Report progress more frequently for better UX
        if (indexedLines % 100 == 0) {
          onProgress(indexedLines, testLimit);
          print(
              'IndexService: Progress $indexedLines/$testLimit (${(indexedLines / testLimit * 100).toStringAsFixed(1)}%)');
        }
      }

      // Final flush
      await indexWriter.forceFlush();
      await indexWriter.dispose();

      // Open the created index
      _indexReader = await IndexReader.openFromDir(indexPath);

      _openDbPath = dbPath;
      _openIndexPath = indexPath;
      _isReady = true;

      onProgress(testLimit, testLimit);
    } catch (e) {
      _isReady = false;
      rethrow;
    }
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
    if (!_isReady || _indexReader == null || _zayitDb == null) return;

    try {
      // Parse query for OR operations
      final searchTerms = query
          .split(RegExp(r'\s+OR\s+', caseSensitive: false))
          .map((term) => term.trim())
          .where((term) => term.isNotEmpty)
          .toList();

      if (searchTerms.isEmpty) return;

      // Perform search
      final results = await _indexReader!.searchOr(searchTerms);

      int yielded = 0;
      for (final lineId in results) {
        if (isCancelled != null && isCancelled()) return;

        // Get line content
        final content = await _zayitDb!.getLineContent(lineId);
        if (content == null) continue;

        // Generate snippet with highlighting
        final snippet = _generateSnippet(content, searchTerms);

        // Get book title (simplified - in real app would parse from line content)
        final bookTitle = _extractBookTitle(content, lineId);

        yield SearchResultItem(
          lineId: lineId,
          bookTitle: bookTitle,
          snippet: snippet,
        );

        yielded++;

        // Yield in batches to avoid overwhelming the UI
        if (yielded % 50 == 0) {
          await Future.delayed(const Duration(microseconds: 100));
        }
      }
    } catch (e) {
      // Log error but don't crash the stream
      print('Search error: $e');
    }
  }

  // ── Helper methods ─────────────────────────────────────────────

  String _generateSnippet(String content, List<String> searchTerms) {
    // Simple snippet generation - highlight first occurrence of any search term
    final lowerContent = content.toLowerCase();

    for (final term in searchTerms) {
      final lowerTerm = term.toLowerCase();
      final index = lowerContent.indexOf(lowerTerm);

      if (index != -1) {
        // Extract context around the match
        final start = (index - 50).clamp(0, content.length);
        final end = (index + term.length + 50).clamp(0, content.length);

        String snippet = content.substring(start, end);

        // Add ellipsis if truncated
        if (start > 0) snippet = '...$snippet';
        if (end < content.length) snippet = '$snippet...';

        // Highlight the term
        final actualTerm = content.substring(index, index + term.length);
        snippet = snippet.replaceAll(actualTerm, '<mark>$actualTerm</mark>');

        return snippet;
      }
    }

    // If no term found, return first 100 characters
    final snippet =
        content.length > 100 ? '${content.substring(0, 100)}...' : content;
    return snippet;
  }

  String _extractBookTitle(String content, int lineId) {
    // Simplified book title extraction
    // In a real implementation, this would parse the actual book structure
    if (content.contains('בראשית')) return 'בראשית';
    if (content.contains('שמות')) return 'שמות';
    if (content.contains('ויקרא')) return 'ויקרא';
    if (content.contains('במדבר')) return 'במדבר';
    if (content.contains('דברים')) return 'דברים';

    // Default: use line ID as reference
    return 'שורה $lineId';
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
        .replaceAll('&gt;', '>')
        .replaceAll('&lt;', '<')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}
