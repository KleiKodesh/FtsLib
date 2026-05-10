/// The output of [SeforimIndex.generateSnippet].
/// Immutable — all properties are set at construction time.
class SnippetResult {
  /// Ready-to-render HTML snippet with matched query terms wrapped in
  /// highlight tags. Empty string when [isMatch] is false.
  final String html;

  /// Raw character span (rawEnd - rawStart) of the tightest window covering
  /// all query terms. Smaller = terms are closer together in the source text.
  /// int max value = at least one term absent (no match).
  final int score;

  /// Number of tokens (words) between the leftmost and rightmost matched
  /// tokens in the tightest window. 0 = adjacent. int max = no match.
  final int wordDistance;

  /// True when all query terms were found in the line content.
  /// False means the line was a false positive from the index.
  final bool isMatch;

  const SnippetResult(this.html, this.score, this.wordDistance, this.isMatch);

  static const SnippetResult noMatch =
      SnippetResult('', 0x7FFFFFFF, 0x7FFFFFFF, false);
}
