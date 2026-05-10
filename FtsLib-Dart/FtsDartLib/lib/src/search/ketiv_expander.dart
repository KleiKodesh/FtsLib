/// Generates כתיב חסר / כתיב מלא spelling variants of a normalised Hebrew term
/// by inserting ו and י at every consonant-boundary position in the stem.
///
/// See the C# source for the full algorithm description.
class KetivExpander {
  static const int _yod = 0x05D9; // י
  static const int _vav = 0x05D5; // ו

  /// Hard cap on the number of variants returned per term.
  static const int maxVariants = 40;

  // Suffixes to preserve verbatim — ordered longest-first so greedy match works.
  static const List<String> _preservedSuffixes = [
    '\u05D5\u05D9\u05D5\u05EA', // ויות
    '\u05D9\u05D5\u05EA',       // יות
    '\u05D5\u05EA',             // ות
    '\u05D9\u05DF',             // ין
    '\u05D9\u05DD',             // ים
    '\u05D9\u05EA',             // ית
    '\u05D5\u05DF',             // ון
    '\u05EA\u05D9',             // תי
    '\u05E0\u05D5',             // נו
    '\u05DB\u05DD',             // כם
    '\u05DB\u05DF',             // כן
    '\u05D4\u05DD',             // הם
    '\u05D4\u05DF',             // הן
    '\u05DA',                   // ך
    '\u05D4',                   // ה
  ];

  static bool _isHebrewConsonant(int c) =>
      c >= 0x05D0 && c <= 0x05EA && c != _vav && c != _yod;

  static bool _isConsonantal(String stem, int index) {
    int c = stem.codeUnitAt(index);
    if (c != _vav && c != _yod) return false;
    return index == 0 || index == stem.length - 1;
  }

  /// Returns all כתיב spelling variants of [term], excluding the original term.
  static List<String> expand(String term, {int maxVariantsOverride = maxVariants}) {
    if (term.isEmpty || term.length < 2) return [];

    // Step 1: detect and strip a grammatical suffix
    String stem = term;
    String suffix = '';
    for (final s in _preservedSuffixes) {
      if (term.endsWith(s) && term.length > s.length) {
        stem = term.substring(0, term.length - s.length);
        suffix = s;
        break;
      }
    }

    // Step 2: identify protected (consonantal) ו/י positions in stem
    final protectedIndices = <int>{};
    for (int i = 0; i < stem.length; i++) {
      if (_isConsonantal(stem, i)) protectedIndices.add(i);
    }

    // Step 3: build consonant skeleton (strip unprotected ו/י)
    final skeletonBuf = StringBuffer();
    final skeletonConsonantIndices = <int>[];

    for (int i = 0; i < stem.length; i++) {
      int c = stem.codeUnitAt(i);
      bool isVowelLetter =
          (c == _vav || c == _yod) && !protectedIndices.contains(i);
      if (!isVowelLetter) {
        int posInSkeleton = skeletonBuf.length;
        skeletonBuf.writeCharCode(c);
        if (_isHebrewConsonant(c) || protectedIndices.contains(i)) {
          skeletonConsonantIndices.add(posInSkeleton);
        }
      }
    }

    String skeleton = skeletonBuf.toString();
    final variants = <String>{};

    // Step 4: single-deletion pass (מלא → חסר)
    for (int i = 0; i < stem.length; i++) {
      int c = stem.codeUnitAt(i);
      if (c != _vav && c != _yod) continue;
      if (protectedIndices.contains(i)) continue;

      String deletion = stem.substring(0, i) + stem.substring(i + 1) + suffix;
      if (deletion.length >= 2 && deletion != term) variants.add(deletion);
    }

    if (skeletonConsonantIndices.length < 2) {
      _originalStemPass(stem, suffix, term, variants, maxVariantsOverride);
      return List<String>.from(variants);
    }

    // Always include the bare skeleton + suffix (maximally חסר form)
    {
      String bareVariant = skeleton + suffix;
      if (bareVariant != term) variants.add(bareVariant);
    }

    // Step 5: skeleton insertion pass (חסר → מלא)
    {
      int gaps = skeletonConsonantIndices.length - 1;
      int effectiveGaps = gaps < 4 ? gaps : 4;
      int total = _pow3(effectiveGaps);

      for (int mask = 0;
          mask < total && variants.length < maxVariantsOverride;
          mask++) {
        final insertions = <_Insertion>[];
        int m = mask;
        for (int g = 0; g < effectiveGaps; g++) {
          int choice = m % 3;
          m ~/= 3;
          if (choice == 1) {
            insertions.add(_Insertion(skeletonConsonantIndices[g], _vav));
          } else if (choice == 2) {
            insertions.add(_Insertion(skeletonConsonantIndices[g], _yod));
          }
        }

        if (insertions.isEmpty) continue;

        // Reject masks where two consecutive gaps both insert.
        bool hasAdjacentInsertions = false;
        for (int i = 0; i < insertions.length - 1; i++) {
          if (insertions[i + 1].afterIndex == insertions[i].afterIndex + 1) {
            hasAdjacentInsertions = true;
            break;
          }
        }
        if (hasAdjacentInsertions) continue;

        // Apply insertions left-to-right, adjusting offset as chars are added.
        String s = skeleton;
        int offset = 0;
        for (final ins in insertions) {
          int pos = ins.afterIndex + 1 + offset;
          s = s.substring(0, pos) +
              String.fromCharCode(ins.ch) +
              s.substring(pos);
          offset++;
        }

        String variant = s + suffix;
        if (variant != term) variants.add(variant);
      }
    }

    // Step 6: original stem insertion pass
    _originalStemPass(stem, suffix, term, variants, maxVariantsOverride);

    return List<String>.from(variants);
  }

  static void _originalStemPass(String stem, String suffix, String term,
      Set<String> variants, int maxVariantsOverride) {
    for (int i = 0;
        i < stem.length - 1 && variants.length < maxVariantsOverride;
        i++) {
      if (!_isHebrewConsonant(stem.codeUnitAt(i))) continue;

      for (final ch in [_vav, _yod]) {
        if (stem.codeUnitAt(i + 1) == ch) continue;

        String variant = stem.substring(0, i + 1) +
            String.fromCharCode(ch) +
            stem.substring(i + 1) +
            suffix;
        if (variant != term && variant.length >= 2) variants.add(variant);
      }
    }
  }

  static int _pow3(int n) {
    int result = 1;
    for (int i = 0; i < n; i++) result *= 3;
    return result;
  }
}

class _Insertion {
  final int afterIndex;
  final int ch;
  const _Insertion(this.afterIndex, this.ch);
}
