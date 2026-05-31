import 'html_word_scanner.dart';

/// A single word token produced by [TokenStream].
class TextToken {
  /// Index of the first letter of the word in the original raw string
  /// (before nikud was stripped). Points into the source HTML.
  final int rawStart;

  /// Index just past the separator that ended the word in the original raw string.
  final int rawEnd;

  /// Normalized form of the word: nikud stripped, ASCII lowercased.
  final String normalized;

  /// Cumulative count of visible characters in the source string up to but not
  /// including the first letter of this token.
  final int visibleStart;

  const TextToken(
      this.rawStart, this.rawEnd, this.normalized, this.visibleStart);

  @override
  String toString() => '[$rawStart–$rawEnd] "$normalized"';
}

/// Produces a list of [TextToken] from an HTML string, preserving the raw
/// character positions of each word alongside its normalized form.
/// Used by the highlighter to locate match spans in the original source
/// without a second pass.
/// Not thread-safe — do not share across isolates.
class TokenStream extends HtmlWordScanner {
  final List<TextToken> _tokens = [];

  /// Tokenizes [text] and returns all tokens in order.
  /// The returned list is reused on the next call — copy it if you need to keep it.
  List<TextToken> tokenize(String text) {
    _tokens.clear();
    if (text.isNotEmpty) scan(text);
    return _tokens;
  }

  @override
  void onWord(int rawStart, int rawEnd, int visibleStart) {
    _tokens.add(TextToken(rawStart, rawEnd, buffer.toString(), visibleStart));
  }
}
