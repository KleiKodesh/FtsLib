/// One row returned by [SeforimIndex.search].
/// Immutable — all properties are set at construction time.
class SearchResult {
  /// The line ID in the seforim database.
  final int lineId;

  /// Title of the book this line belongs to.
  final String bookTitle;

  /// Raw HTML content of the line as stored in the database.
  final String content;

  /// The query groups used to find this result — one group per query token,
  /// each containing the concrete index terms that were OR-expanded from that
  /// token (e.g. all fuzzy neighbors of יצחק~ form one group).
  final List<List<String>> matchedGroups;

  /// The number of query groups in the original parsed query, before any
  /// zero-expansion wildcards were skipped.
  final int originalGroupCount;

  SearchResult(
    this.lineId,
    this.bookTitle,
    this.content, {
    List<List<String>>? matchedGroups,
    int originalGroupCount = 0,
  })  : matchedGroups = matchedGroups ?? [],
        originalGroupCount = originalGroupCount > 0
            ? originalGroupCount
            : (matchedGroups?.length ?? 0);

  @override
  String toString() => '[$lineId] $bookTitle';
}
