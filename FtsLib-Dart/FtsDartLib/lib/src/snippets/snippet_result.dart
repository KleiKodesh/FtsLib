/// The output of [SnippetBuilder.build].
class SnippetResult {
  final String html;

  /// Character span (rawEnd - rawStart) of the tightest window.
  /// int max value = at least one term absent.
  final int score;

  /// Number of tokens (words) between the leftmost and rightmost matched
  /// tokens in the tightest window. 0 = adjacent. int max = no match.
  final int wordDistance;

  final bool isMatch;

  const SnippetResult(this.html, this.score, this.wordDistance, this.isMatch);
}
