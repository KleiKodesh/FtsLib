import '../indexing/segment_handle.dart';

/// Expands wildcard patterns into the set of concrete terms that exist in the
/// index by querying each segment's term_index table.
///
/// Supported wildcards:
///   '*'  — matches zero or more characters (prefix / suffix / infix)
///   '?'  — makes the immediately preceding character optional
///          e.g. שלו?ם → {שלום, שלם}  (with or without ו)
///
/// Expansion limits:
///   [minAnchorLength] (2): the non-wildcard anchor must be at least 2 chars.
///   [maxPrefixWildcardChars] (3): leading '*' may match at most 3 chars.
///   [maxSuffixWildcardChars] (4): trailing '*' may match at most 4 chars.
///   [maxOptionalChars] (4): at most 4 '?' operators per pattern.
class HebrewWildcardExpander {
  /// Minimum number of non-wildcard characters a pattern must contain.
  static const int minAnchorLength = 2;

  /// Maximum characters the leading '*' of a suffix wildcard (*abc) may match.
  static const int maxPrefixWildcardChars = 3;

  /// Maximum characters the trailing '*' of a prefix wildcard (abc*) may match.
  static const int maxSuffixWildcardChars = 4;

  /// Maximum number of '?' operators allowed in a single pattern.
  static const int maxOptionalChars = 4;

  // ── Public entry point ────────────────────────────────────────

  /// Expands a pattern that may contain '*', '?', or both.
  static Future<List<String>> expand(
    String pattern,
    List<SegmentHandle> segments,
  ) async {
    final hasOptional = pattern.contains('?');
    final hasStar = pattern.contains('*');

    if (!hasOptional) return _expandStar(pattern, segments);

    // Count effective '?' operators.
    int optCount = _countEffectiveOptionals(pattern);
    if (optCount > maxOptionalChars) return [];

    // Generate all sub-patterns by including/excluding each optional char.
    final subPatterns = <String>{};
    _expandOptionals(pattern, 0, '', subPatterns);

    // Collect results across all sub-patterns, deduplicating.
    final seen = <String>{};
    final results = <String>[];

    for (final sub in subPatterns) {
      List<String> expanded;
      if (sub.contains('*')) {
        expanded = await _expandStar(sub, segments);
      } else {
        expanded = await _lookupLiteral(sub, segments);
      }
      for (final term in expanded) {
        if (seen.add(term)) results.add(term);
      }
    }

    return results;
  }

  // ── '*'-only expansion ────────────────────────────────────────

  static Future<List<String>> _expandStar(
    String pattern,
    List<SegmentHandle> segments,
  ) async {
    int anchorLen = _anchorLength(pattern);
    if (anchorLen < minAnchorLength) return [];

    final likePattern = _toLikePattern(pattern);
    final raw = <String>{};

    for (final seg in segments) {
      final terms = await seg.queryTermsLike(likePattern);
      raw.addAll(terms);
    }

    bool hasLeadingStar = pattern.startsWith('*');
    bool hasTrailingStar = pattern.endsWith('*');

    final results = <String>[];
    for (final term in raw) {
      int extra = term.length - anchorLen;
      if (hasLeadingStar && hasTrailingStar) {
        if (extra <= maxPrefixWildcardChars + maxSuffixWildcardChars) {
          results.add(term);
        }
      } else if (hasLeadingStar) {
        if (extra <= maxPrefixWildcardChars) results.add(term);
      } else {
        if (extra <= maxSuffixWildcardChars) results.add(term);
      }
    }

    return results;
  }

  // ── '?' expansion helpers ─────────────────────────────────────

  /// Recursively generates all sub-patterns by including or excluding each
  /// optional character (the char immediately before a '?').
  /// Uses a String accumulator (immutable) to avoid StringBuffer mutation issues.
  static void _expandOptionals(
    String pattern,
    int pos,
    String current,
    Set<String> results,
  ) {
    if (pos == pattern.length) {
      results.add(current);
      return;
    }

    final c = pattern[pos];

    if (c != '?') {
      _expandOptionals(pattern, pos + 1, current + c, results);
      return;
    }

    // c == '?'
    // Determine whether the last char in current is a real letter (not '*').
    bool hasOptionalTarget =
        current.isNotEmpty && current[current.length - 1] != '*';

    if (!hasOptionalTarget) {
      // No-op '?' — skip it.
      _expandOptionals(pattern, pos + 1, current, results);
      return;
    }

    // Branch 1: include the optional char (already in current).
    _expandOptionals(pattern, pos + 1, current, results);

    // Branch 2: exclude the optional char (remove last char from current).
    _expandOptionals(
        pattern, pos + 1, current.substring(0, current.length - 1), results);
  }

  static int _countEffectiveOptionals(String pattern) {
    int count = 0;
    for (int i = 0; i < pattern.length; i++) {
      if (pattern[i] != '?') continue;
      if (i == 0) continue;
      final prev = pattern[i - 1];
      if (prev == '*' || prev == '?') continue;
      count++;
    }
    return count;
  }

  // ── Literal lookup ────────────────────────────────────────────

  static Future<List<String>> _lookupLiteral(
    String term,
    List<SegmentHandle> segments,
  ) async {
    if (_anchorLength(term) < minAnchorLength) return [];
    for (final seg in segments) {
      if (await seg.termExists(term)) return [term];
    }
    return [];
  }

  // ── Pattern translation ───────────────────────────────────────

  /// Converts a user wildcard pattern (using '*') to a SQLite LIKE pattern.
  static String _toLikePattern(String pattern) {
    final sb = StringBuffer();
    for (final c in pattern.split('')) {
      switch (c) {
        case '%':
          sb.write('\\%');
          break;
        case '_':
          sb.write('\\_');
          break;
        case '*':
          sb.write('%');
          break;
        default:
          sb.write(c);
      }
    }
    return sb.toString();
  }

  /// Returns the pattern with all '*' and '?' characters removed.
  static String stripWildcard(String pattern) =>
      pattern.replaceAll('*', '').replaceAll('?', '');

  // ── Helpers ──────────────────────────────────────────────────

  static int _anchorLength(String pattern) {
    int n = 0;
    for (final c in pattern.split('')) {
      if (c != '*' && c != '?') n++;
    }
    return n;
  }
}
