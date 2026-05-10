import 'dart:io';

import '../indexing/corrupt_index_exception.dart';
import '../indexing/index_write_lock.dart';
import '../indexing/search_lease.dart';
import '../indexing/segment_store.dart';
import 'indexing_pipeline.dart';
import 'search_pipeline.dart';
import 'search_result.dart';
import 'snippet_pipeline.dart';
import 'snippet_result.dart';
import 'zayit_db.dart';

/// Public API for full-text search over the seforim database.
///
/// Owns a long-lived [SegmentStore] so that live segment state is always
/// consistent between build sessions and concurrent searches.
///
/// Query syntax:
///   word        — literal AND term
///   word*       — wildcard (prefix / infix / suffix)
///   wor?d       — optional char: the char before '?' is optional
///   word~       — fuzzy match, edit distance 1
///   word~2      — fuzzy match, edit distance 2
///   word~3      — fuzzy match, edit distance 3 (maximum)
///   a | b       — OR: lines matching a OR b satisfy this AND slot
class SeforimIndex {
  final String _indexPath;
  final String _dbPath;
  SegmentStore? _store;

  static const int defaultSnippetLength = SnippetPipeline.defaultSnippetLength;
  static const int defaultContextWords = SnippetPipeline.defaultContextWords;

  SeforimIndex(String indexPath, String dbPath)
      : _indexPath = indexPath.isNotEmpty ? indexPath : (throw ArgumentError('indexPath must not be empty')),
        _dbPath = dbPath.isNotEmpty ? dbPath : (throw ArgumentError('dbPath must not be empty')) {
    // Initialise the store eagerly so crash recovery runs once at startup.
    _ensureStore();
  }

  // ── Store lifecycle ───────────────────────────────────────────

  void _ensureStore() {
    final dir = Directory(_indexPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    _store = SegmentStore(_indexPath);

    final hasSegments = dir.existsSync() &&
        (dir
                .listSync()
                .whereType<File>()
                .any((f) =>
                    f.path.endsWith('.dat') &&
                    f.path.split(Platform.pathSeparator).last.startsWith('seg_')) ||
            File('$_indexPath${Platform.pathSeparator}wal.log').existsSync());

    if (!hasSegments) return;

    print('[SeforimIndex] Segments found — running crash recovery...');
    try {
      _store!.recover();
      print('[SeforimIndex] Recovery complete.');
    } on CorruptIndexException {
      // Recovery wiped the directory — start with a clean store.
      _store = SegmentStore(_indexPath);
    }
  }

  void _resetStore() {
    _store = SegmentStore(_indexPath);
  }

  /// Returns a consistent snapshot of all live segment paths under the store lock,
  /// together with a [SearchLease] that keeps the reader count elevated.
  SearchLease? acquireSearchLease(
      {required void Function(List<(String, String)>) onPaths}) {
    if (_store != null) {
      return _store!.acquireSearchLease(onPaths: onPaths);
    }
    onPaths([]);
    return null;
  }

  // ── Build ─────────────────────────────────────────────────────

  int getResumeLineId() => IndexingPipeline.readResumeLineId(_indexPath);

  void getResumeState({
    required void Function(int) lineId,
    required void Function(int) totalLines,
    required void Function(int) resumeOffset,
  }) =>
      IndexingPipeline.readProgressFile(_indexPath,
          lineId: lineId, totalLines: totalLines, resumeOffset: resumeOffset);

  void deleteBuildProgressFile() =>
      IndexingPipeline.deleteProgressFile(_indexPath);

  Future<int> countLines() async {
    final db = ZayitDb(_dbPath);
    await db.open();
    try {
      return await db.countLines();
    } finally {
      await db.dispose();
    }
  }

  Future<int> countLinesUpTo(int upToId) async {
    final db = ZayitDb(_dbPath);
    await db.open();
    try {
      return await db.countLinesUpTo(upToId);
    } finally {
      await db.dispose();
    }
  }

  Future<bool> buildIndex({
    int limit = 0,
    void Function(int)? onProgress,
    void Function()? onFlush,
    int totalLines = 0,
    int resumeOffset = 0,
    bool Function()? isCancelled,
  }) async {
    final lock = IndexWriteLock(_indexPath);
    try {
      final result = await IndexingPipeline.build(
        _indexPath,
        _dbPath,
        store: _store,
        limit: limit,
        totalLines: totalLines,
        resumeOffset: resumeOffset,
        onProgress: onProgress,
        onFlush: onFlush,
        isCancelled: isCancelled,
      );
      if (_store?.isWiped == true) _resetStore();
      return result;
    } finally {
      lock.dispose();
    }
  }

  // ── Search ────────────────────────────────────────────────────

  Stream<SearchResult> search(
    String query, {
    int cap = 0,
    bool expandKetiv = false,
    bool Function()? isCancelled,
  }) {
    List<(String, String)> livePaths = [];
    final lease = acquireSearchLease(onPaths: (p) => livePaths = p);
    return SearchPipeline.search(
      query,
      _indexPath,
      _dbPath,
      livePaths,
      lease,
      cap: cap,
      expandKetiv: expandKetiv,
      isCancelled: isCancelled,
    );
  }

  Stream<int> searchIds(
    String query, {
    bool expandKetiv = false,
    bool Function()? isCancelled,
  }) {
    List<(String, String)> livePaths = [];
    final lease = acquireSearchLease(onPaths: (p) => livePaths = p);
    return SearchPipeline.searchIds(
      query,
      _indexPath,
      livePaths,
      lease,
      expandKetiv: expandKetiv,
      isCancelled: isCancelled,
    );
  }

  // ── Snippets ──────────────────────────────────────────────────

  Future<SnippetResult> generateSnippetById(int lineId, String query) async {
    final terms = SearchPipeline.extractTerms(query);
    return SnippetPipeline.generateFromDb(lineId, terms, _dbPath);
  }

  SnippetResult generateSnippet(
    SearchResult result, {
    bool requireOrdered = false,
    int snippetLength = defaultSnippetLength,
    int contextWords = defaultContextWords,
  }) {
    if (result.matchedGroups.isEmpty) return SnippetResult.noMatch;
    return SnippetPipeline.generate(
      result.content,
      result.matchedGroups,
      requireOrdered: requireOrdered,
      originalGroupCount: result.originalGroupCount,
      snippetLength: snippetLength,
      contextWords: contextWords,
    );
  }
}
