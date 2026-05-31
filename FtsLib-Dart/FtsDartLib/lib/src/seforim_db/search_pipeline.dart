import '../indexing/search_lease.dart';
import '../search/index_reader.dart';
import '../search/ketiv_expander.dart';
import '../search/query_parser.dart';
import 'search_result.dart';
import 'zayit_db.dart';

/// Executes a parsed query against the index and fetches matching rows
/// from the seforim database.
///
/// Query syntax (handled by [QueryParser]):
///   word        — literal AND term
///   word*       — wildcard (prefix / infix / suffix)
///   wor?d       — optional char
///   word~       — fuzzy, edit distance 1 (default)
///   word~2      — fuzzy, edit distance 2
///   word~3      — fuzzy, edit distance 3 (maximum)
///   a | b       — OR: lines matching a OR b satisfy this AND slot
class SearchPipeline {
  /// Parses [query], expands wildcards/fuzzy terms, runs the intersection
  /// search, fetches rows from the DB, and returns results as a stream.
  static Stream<SearchResult> search(
    String query,
    String indexPath,
    String dbPath,
    List<(String dat, String db)> livePaths,
    SearchLease? lease, {
    int cap = 0,
    bool expandKetiv = false,
    bool Function()? isCancelled,
  }) async* {
    final parsed = QueryParser.parse(query);
    if (parsed.isEmpty) {
      lease?.dispose();
      return;
    }

    final reader = await IndexReader.open(indexPath, livePaths, lease);
    try {
      final groups = <List<String>>[];
      final expandedGroups = <List<String>>[];

      for (final group in parsed.groups) {
        if (isCancelled != null && isCancelled()) return;

        bool hardMiss = false;
        final groupTerms = await _expandGroup(
            group, reader, expandKetiv, isCancelled, (v) => hardMiss = v);
        if (hardMiss) return;
        if (groupTerms.isEmpty) continue;
        groups.add(groupTerms);
        expandedGroups.add(groupTerms);
      }

      if (groups.isEmpty) return;

      int yielded = 0;
      final db = ZayitDb(dbPath);
      await db.open();
      try {
        final ids = reader.search(groups, isCancelled: isCancelled);
        await for (final (lineId, content, bookTitle)
            in db.fetchSearchResultsStreaming(ids)) {
          if (isCancelled != null && isCancelled()) return;
          yield SearchResult(lineId, bookTitle, content,
              matchedGroups: expandedGroups,
              originalGroupCount: parsed.groups.length);
          yielded++;
          if (cap > 0 && yielded >= cap) return;
        }
      } finally {
        await db.dispose();
      }
    } finally {
      await reader.dispose();
    }
  }

  /// Returns the normalised query terms for a raw query string.
  static List<String> extractTerms(String query) {
    final parsed = QueryParser.parse(query);
    final terms = <String>[];
    for (final g in parsed.groups) {
      for (final alt in g.alternatives) terms.add(alt.pattern);
    }
    return terms;
  }

  /// Returns only the matching line IDs — no database fetch at all.
  static Stream<int> searchIds(
    String query,
    String indexPath,
    List<(String dat, String db)> livePaths,
    SearchLease? lease, {
    bool expandKetiv = false,
    bool Function()? isCancelled,
  }) async* {
    final parsed = QueryParser.parse(query);
    if (parsed.isEmpty) {
      lease?.dispose();
      return;
    }

    final reader = await IndexReader.open(indexPath, livePaths, lease);
    try {
      final groups = <List<String>>[];

      for (final group in parsed.groups) {
        if (isCancelled != null && isCancelled()) return;

        bool hardMiss = false;
        final groupTerms = await _expandGroup(
            group, reader, expandKetiv, isCancelled, (v) => hardMiss = v);
        if (hardMiss) return;
        if (groupTerms.isEmpty) continue;
        groups.add(groupTerms);
      }

      if (groups.isEmpty) return;

      for (final id in reader.search(groups, isCancelled: isCancelled)) {
        yield id;
      }
    } finally {
      await reader.dispose();
    }
  }

  // ── Group expansion ───────────────────────────────────────────

  static Future<List<String>> _expandGroup(
    QueryGroup group,
    IndexReader reader,
    bool expandKetiv,
    bool Function()? isCancelled,
    void Function(bool) setHardMiss,
  ) async {
    // Fast path: single literal alternative (the common case).
    if (group.isSingle && !group.isWildcard && !group.isFuzzy) {
      final result = <String>[group.pattern];
      if (expandKetiv) {
        result.addAll(KetivExpander.expand(group.pattern));
      }
      return result;
    }

    final seen = <String>{};
    final list = <String>[];

    for (final alt in group.alternatives) {
      if (isCancelled != null && isCancelled()) break;

      List<String> expanded;

      if (alt.isFuzzy) {
        expanded = await reader.expandFuzzy(alt.pattern, alt.fuzzyDistance);
        if (expanded.isEmpty) {
          setHardMiss(true);
          return list;
        }
      } else if (alt.isWildcard) {
        expanded = await reader.expandWildcard(alt.pattern);
        if (expanded.isEmpty) continue;
      } else {
        expanded = [alt.pattern];
        if (expandKetiv) {
          expanded.addAll(KetivExpander.expand(alt.pattern));
        }
      }

      for (final term in expanded) {
        if (seen.add(term)) list.add(term);
      }
    }

    return list;
  }
}
