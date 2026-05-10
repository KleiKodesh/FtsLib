/// Computes the Levenshtein (edit) distance between two strings.
/// Uses a two-row DP approach — O(min(a,b)) space.
class Levenshtein {
  /// Returns the edit distance between [a] and [b], stopping early and
  /// returning [maxDistance] + 1 as soon as it is certain the true distance
  /// exceeds [maxDistance].
  static int distance(String a, String b, {int maxDistance = 0x7FFFFFFF}) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Keep the shorter string in 'a' to minimise row width
    if (a.length > b.length) {
      final tmp = a;
      a = b;
      b = tmp;
    }

    int lenA = a.length;
    int lenB = b.length;

    // If lengths differ by more than maxDistance, bail immediately
    if (lenB - lenA > maxDistance) return maxDistance + 1;

    final List<int> prev = List<int>.generate(lenA + 1, (i) => i);
    final List<int> curr = List<int>.filled(lenA + 1, 0);

    for (int j = 1; j <= lenB; j++) {
      curr[0] = j;
      int rowMin = curr[0];

      for (int i = 1; i <= lenA; i++) {
        int cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[i] = _min3(
          curr[i - 1] + 1,     // insert
          prev[i] + 1,         // delete
          prev[i - 1] + cost,  // substitute
        );
        if (curr[i] < rowMin) rowMin = curr[i];
      }

      // Early exit: entire row exceeds maxDistance
      if (rowMin > maxDistance) return maxDistance + 1;

      for (int i = 0; i <= lenA; i++) prev[i] = curr[i];
    }

    return prev[lenA];
  }

  static int _min3(int a, int b, int c) =>
      a < b ? (a < c ? a : c) : (b < c ? b : c);
}
