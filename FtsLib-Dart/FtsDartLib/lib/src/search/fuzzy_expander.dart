import '../indexing/segment_handle.dart';
import 'levenshtein.dart';

/// Expands a fuzzy query term into the set of index terms within a given
/// Levenshtein edit distance.
///
/// Algorithm (two-phase):
///   1. N-gram filter — generate n-grams of the query term and query each
///      segment's term_index with LIKE '%ngram%'. Uses OR across all n-grams
///      to maximise recall.
///
///      N-gram size by term length:
///        ≤ 2 chars  → substring LIKE scan (no n-grams possible)
///        3 chars    → bigrams  (2-char substrings)
///        ≥ 4 chars  → trigrams (3-char substrings)
///
///   2. Levenshtein confirm — filter candidates to those whose edit distance
///      from the query term is ≤ maxDistance (clamped to 3).
///
/// Returns a deduplicated list of matching terms across all live segments.
/// Returns an empty list when nothing matches.
class FuzzyExpander {
  /// Maximum allowed edit distance (hard cap).
  static const int maxAllowedDistance = 3;

  /// Expands [term] to all index terms within [maxDistance] edits.
  static Future<List<String>> expand(
    String term,
    int maxDistance,
    List<SegmentHandle> segments,
  ) async {
    if (maxDistance > maxAllowedDistance) maxDistance = maxAllowedDistance;
    if (maxDistance < 1) maxDistance = 1;

    Set<String> candidates;

    if (term.length >= 4) {
      // Standard trigram filter
      final ngrams = buildNgrams(term, 3);
      candidates = await _queryByNgrams(ngrams, segments);
    } else if (term.length == 3) {
      // Bigram filter: a 3-char word has only one trigram (itself), which
      // misses 1-edit neighbours. Bigrams give much better recall.
      final ngrams = buildNgrams(term, 2);
      candidates = await _queryByNgrams(ngrams, segments);
    } else {
      // ≤ 2 chars: no n-grams possible, fall back to infix LIKE scan.
      candidates = await _queryBySubstring(term, segments);
    }

    // Phase 2: Levenshtein confirmation
    final results = <String>[];
    for (final candidate in candidates) {
      if (Levenshtein.distance(candidate, term,
              maxDistance: maxDistance) <=
          maxDistance) {
        results.add(candidate);
      }
    }
    return results;
  }

  // ── N-gram generation ─────────────────────────────────────────

  /// Returns the distinct n-grams (substrings of length [n]) of [s]
  /// in first-seen order.
  /// Returns an empty list when s.length < n.
  static List<String> buildNgrams(String s, int n) {
    final seen = <String>{};
    final list = <String>[];
    for (int i = 0; i <= s.length - n; i++) {
      final ng = s.substring(i, i + n);
      if (seen.add(ng)) list.add(ng);
    }
    return list;
  }

  // ── Segment queries ───────────────────────────────────────────

  /// Queries each segment for terms containing at least one of the given n-grams.
  /// Uses OR across n-grams to maximise recall.
  static Future<Set<String>> _queryByNgrams(
    List<String> ngrams,
    List<SegmentHandle> segments,
  ) async {
    final results = <String>{};
    final likeArgs = ngrams.map((ng) => '%${_escapeLike(ng)}%').toList();

    for (final seg in segments) {
      final terms = await seg.queryTermsLikeAny(likeArgs);
      results.addAll(terms);
    }

    return results;
  }

  /// Fallback for terms of 2 chars or fewer: queries with a simple infix LIKE.
  static Future<Set<String>> _queryBySubstring(
    String term,
    List<SegmentHandle> segments,
  ) async {
    final results = <String>{};
    final pattern = '%${_escapeLike(term)}%';

    for (final seg in segments) {
      final terms = await seg.queryTermsLike(pattern);
      results.addAll(terms);
    }

    return results;
  }

  // ── Helpers ───────────────────────────────────────────────────

  /// Escapes SQLite LIKE special characters: \, %, _
  static String _escapeLike(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }
}
