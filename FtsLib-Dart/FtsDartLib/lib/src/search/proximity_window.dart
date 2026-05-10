import '../tokenization/token_stream.dart';

/// Finds the minimum-span window in a token list that covers all query groups.
/// Uses the classic two-pointer sliding-window algorithm — O(n) in token count.
///
/// Each group is a set of alternative terms (OR semantics): the window must
/// contain at least one term from every group.
class ProximityWindow {
  /// Scans [tokens] and returns the tightest contiguous window (by raw character
  /// span) that contains at least one occurrence of every group in [queryGroups].
  ///
  /// Returns (winStart, winEnd, score) where score = winEnd - winStart.
  /// Returns (-1, -1, maxInt) when at least one group has no representative.
  static (int winStart, int winEnd, int score) find(
    List<TextToken> tokens,
    List<List<String>> queryGroups,
  ) {
    if (queryGroups.isEmpty) return (-1, -1, 0x7FFFFFFF);

    // Map every term to its group index.
    final termToGroup = <String, int>{};
    for (int g = 0; g < queryGroups.length; g++) {
      for (final t in queryGroups[g]) {
        termToGroup.putIfAbsent(t, () => g);
      }
    }

    final groupCount = List<int>.filled(queryGroups.length, 0);
    int covered = 0;
    int required = queryGroups.length;

    int bestStart = -1, bestEnd = -1, bestScore = 0x7FFFFFFF;
    int L = 0;

    for (int R = 0; R < tokens.length; R++) {
      String rt = tokens[R].normalized;
      if (termToGroup.containsKey(rt)) {
        int rg = termToGroup[rt]!;
        if (groupCount[rg]++ == 0) covered++;
      }

      while (covered == required) {
        int span = tokens[R].rawEnd - tokens[L].rawStart;
        if (span < bestScore) {
          bestScore = span;
          bestStart = tokens[L].rawStart;
          bestEnd = tokens[R].rawEnd;
        }

        String lt = tokens[L].normalized;
        if (termToGroup.containsKey(lt)) {
          int lg = termToGroup[lt]!;
          if (--groupCount[lg] == 0) covered--;
        }
        L++;
      }
    }

    return (bestStart, bestEnd, bestScore);
  }

  /// Convenience overload for single-term-per-group queries (literal searches).
  static (int winStart, int winEnd, int score) findLiteral(
    List<TextToken> tokens,
    List<String> queryTerms,
  ) {
    final groups = queryTerms.map((t) => [t]).toList();
    return find(tokens, groups);
  }
}
