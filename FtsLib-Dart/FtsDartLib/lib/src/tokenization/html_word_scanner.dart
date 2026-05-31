import 'html_block_tags.dart';

/// Base class for single-pass HTML-aware text scanners.
/// Handles tag detection, entity decoding, nikud/cantillation stripping,
/// and word boundary detection. Subclasses receive each complete word via
/// [onWord] with both its raw source span and its normalized form.
abstract class HtmlWordScanner {
  // Normalized word buffer — reused across words, no per-word allocation.
  final StringBuffer _buffer = StringBuffer();

  /// Getter for subclasses to access the buffer
  StringBuffer get buffer => _buffer;

  // Tag name buffer — fixed size, no allocation per tag.
  final List<int> _tagName = List<int>.filled(16, 0);
  int _tagLen = 0;
  bool _inTag = false;
  int _wordStart = -1;
  int _visibleCount = 0;

  // ── Entry point ──────────────────────────────────────────────

  void scan(String text) {
    _buffer.clear();
    _tagLen = 0;
    _inTag = false;
    _wordStart = -1;
    _visibleCount = 0;

    int len = text.length;
    final iRef = [0]; // mutable index for entity handler

    for (int i = 0; i < len; i++) {
      int c = text.codeUnitAt(i);

      // ── HTML TAGS ────────────────────────────────────────────
      if (_inTag) {
        if (c == 0x3E) {
          // '>'
          if (HtmlBlockTags.isBlockTag(_tagName, _tagLen)) _flush(i);
          _inTag = false;
          _tagLen = 0;
        } else if (_tagLen < 16 && c != 0x20 && c != 0x09 && c != 0x2F) {
          _tagName[_tagLen++] = c;
        }
        continue;
      }

      if (c == 0x3C) {
        // '<'
        _flush(i);
        _inTag = true;
        _tagLen = 0;
        continue;
      }

      // ── HTML ENTITIES ────────────────────────────────────────
      if (c == 0x26) {
        // '&'
        iRef[0] = i;
        if (HtmlBlockTags.isWhitespaceEntity(text, len, iRef)) {
          _flush(iRef[0]);
          _visibleCount++;
          i = iRef[0];
        }
        continue;
      }

      // ── MAQAF ─ word-joining hyphen acts as separator ────────
      if (c == 0x05BE) {
        _flush(i);
        _visibleCount++;
        continue;
      }

      // ── NIKUD + CANTILLATION REMOVAL ─────────────────────────
      if (c >= 0x0591 &&
          c <= 0x05C7 &&
          c != 0x05C0 && // paseq
          c != 0x05C3 && // sof pasuq
          c != 0x05C6) {
        // nun hafukha
        continue;
      }

      // Non-spacing marks above U+007F
      if (c > 127 && _isNonSpacingMark(c)) continue;

      // ── WORD BUILDING ────────────────────────────────────────
      if (isLetter(c)) {
        if (c >= 0x41 && c <= 0x5A) c |= 32; // lowercase ASCII

        if (_buffer.isEmpty) _wordStart = i;

        _buffer.writeCharCode(c);
        _visibleCount++;
      } else {
        _flush(i);
        _visibleCount++;
      }
    }

    _flush(len);
  }

  // ── Flush ────────────────────────────────────────────────────

  void _flush(int rawEnd) {
    final bufLen = _buffer.length;
    if (bufLen > 1 && bufLen < 30) {
      int visibleStart = _visibleCount - bufLen;
      onWord(_wordStart, rawEnd, visibleStart);
    }
    _buffer.clear();
    _wordStart = -1;
  }

  // ── Subclass hook ────────────────────────────────────────────

  /// Called for each complete word found in the source text.
  /// [rawStart] — index of the first letter in the original string.
  /// [rawEnd]   — index just past the separator that ended the word.
  /// [visibleStart] — cumulative visible chars up to but not including this word.
  /// [_buffer] holds the normalized form at call time.
  void onWord(int rawStart, int rawEnd, int visibleStart);

  // ── Shared letter test ───────────────────────────────────────

  /// Returns true for Hebrew letters (alef–tav) and ASCII a–z / A–Z.
  static bool isLetter(int c) =>
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x05D0 && c <= 0x05EA);

  // Dart doesn't have CharUnicodeInfo; approximate non-spacing marks by range.
  static bool _isNonSpacingMark(int c) =>
      // Common non-spacing mark ranges
      (c >= 0x0300 && c <= 0x036F) || // Combining Diacritical Marks
      (c >= 0x1DC0 && c <= 0x1DFF) || // Combining Diacritical Marks Supplement
      (c >= 0x20D0 && c <= 0x20FF) || // Combining Diacritical Marks for Symbols
      (c >= 0xFE20 && c <= 0xFE2F); // Combining Half Marks
}
