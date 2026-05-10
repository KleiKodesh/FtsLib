import '../snippets/snippet_builder.dart';
import '../snippets/snippet_result.dart' as inner;
import 'snippet_result.dart';
import 'zayit_db.dart';

/// Generates a highlighted HTML snippet for a single search result line.
///
/// Pipeline (single pass over the token stream):
///   1. Use already-fetched content from [SearchResult.content] — no second DB round-trip.
///   2. Tokenize via [TokenStream] (preserves raw char positions).
///   3. Find the tightest proximity window covering all query groups.
///   4. Expand the window to a readable length and render highlighted HTML.
class SnippetPipeline {
  static const int defaultSnippetLength = 120;
  static const int defaultContextWords = 8;

  // One SnippetBuilder per call — in Dart we don't need ThreadStatic.
  // Callers can cache a SnippetBuilder instance for performance.

  static SnippetBuilder _getBuilder(int snippetLength, int contextWords) {
    return SnippetBuilder(
      snippetLength: snippetLength,
      contextWords: contextWords,
    );
  }

  // ── Primary path: content already in hand ────────────────────

  /// Builds a snippet from already-fetched content using pre-computed query
  /// groups. Each group is a set of alternative terms (OR within group, AND
  /// across groups).
  static SnippetResult generate(
    String content,
    List<List<String>> queryGroups, {
    bool requireOrdered = false,
    int originalGroupCount = 0,
    int snippetLength = defaultSnippetLength,
    int contextWords = defaultContextWords,
  }) {
    if (content.isEmpty || queryGroups.isEmpty) return SnippetResult.noMatch;

    final innerResult = _getBuilder(snippetLength, contextWords).buildFromGroups(
      content,
      queryGroups,
      requireOrdered: requireOrdered,
      originalGroupCount: originalGroupCount,
    );
    return SnippetResult(
        innerResult.html, innerResult.score, innerResult.wordDistance, innerResult.isMatch);
  }

  static SnippetResult generateFromTerms(
    String content,
    List<String> queryTerms, {
    int snippetLength = defaultSnippetLength,
    int contextWords = defaultContextWords,
  }) {
    if (content.isEmpty || queryTerms.isEmpty) return SnippetResult.noMatch;

    final innerResult =
        _getBuilder(snippetLength, contextWords).buildFromTerms(content, queryTerms);
    return SnippetResult(
        innerResult.html, innerResult.score, innerResult.wordDistance, innerResult.isMatch);
  }

  // ── Fallback path: fetch content from DB ──────────────────────

  /// Fetches content from the DB then builds the snippet.
  static Future<SnippetResult> generateFromDb(
    int lineId,
    List<String> queryTerms,
    String dbPath, {
    int snippetLength = defaultSnippetLength,
    int contextWords = defaultContextWords,
  }) async {
    if (queryTerms.isEmpty) return SnippetResult.noMatch;

    final db = ZayitDb(dbPath);
    await db.open();
    try {
      final content = await db.getLineContent(lineId);
      if (content == null) return SnippetResult.noMatch;
      return generateFromTerms(content, queryTerms,
          snippetLength: snippetLength, contextWords: contextWords);
    } finally {
      await db.dispose();
    }
  }
}
