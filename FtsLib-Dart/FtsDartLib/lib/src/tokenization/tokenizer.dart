import 'html_word_scanner.dart';

/// Extracts the set of unique normalized terms from an HTML string.
/// Strips nikud, lowercases ASCII, ignores HTML tags and non-letter characters.
/// Not thread-safe — do not share across isolates.
class Tokenizer extends HtmlWordScanner {
  final Set<String> _terms = {};

  /// Returns the set of unique normalized terms found in [text].
  /// The returned set is reused on the next call — copy it if you need to keep it.
  Set<String> extract(String text) {
    _terms.clear();
    if (text.isNotEmpty) scan(text);
    return _terms;
  }

  @override
  void onWord(int rawStart, int rawEnd, int visibleStart) {
    // rawStart / rawEnd / visibleStart are available but not needed here —
    // the Tokenizer only cares about the normalized form.
    _terms.add(_buffer.toString());
  }
}
