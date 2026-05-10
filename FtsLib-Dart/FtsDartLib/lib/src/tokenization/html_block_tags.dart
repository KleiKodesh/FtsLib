/// Block-tag detection and HTML entity whitespace handling,
/// shared by [HtmlWordScanner] subclasses.
/// All methods are allocation-free on the hot path.
class HtmlBlockTags {
  /// Returns true if the tag name in [name][0..len) is a block-level HTML
  /// element (acts as a word separator).
  static bool isBlockTag(List<int> name, int len) {
    if (len == 0) return false;

    // Skip leading '/' (closing tag) or '!' (comment/doctype)
    int start = (name[0] == 0x2F || name[0] == 0x21) ? 1 : 0;
    int tlen = len - start;
    if (tlen == 0) return false;

    int c0 = name[start];
    if (c0 >= 0x41 && c0 <= 0x5A) c0 |= 32; // lowercase

    switch (tlen) {
      case 1:
        return c0 == 0x70; // 'p'

      case 2:
        {
          int c1 = name[start + 1];
          if (c1 >= 0x41 && c1 <= 0x5A) c1 |= 32;
          if (c0 == 0x62 && c1 == 0x72) return true; // br
          if (c0 == 0x68 && c1 == 0x72) return true; // hr
          if (c0 == 0x6C && c1 == 0x69) return true; // li
          if (c0 == 0x75 && c1 == 0x6C) return true; // ul
          if (c0 == 0x6F && c1 == 0x6C) return true; // ol
          if (c0 == 0x74 && c1 == 0x72) return true; // tr
          if (c0 == 0x74 && c1 == 0x64) return true; // td
          if (c0 == 0x74 && c1 == 0x68) return true; // th
          if (c0 == 0x64 && c1 == 0x64) return true; // dd
          if (c0 == 0x64 && c1 == 0x74) return true; // dt
          if (c0 == 0x68) {
            int d = (c1 >= 0x41 && c1 <= 0x5A) ? c1 | 32 : c1;
            return d >= 0x31 && d <= 0x36; // h1–h6
          }
          return false;
        }

      case 3:
        {
          int c1 = name[start + 1]; if (c1 >= 0x41 && c1 <= 0x5A) c1 |= 32;
          int c2 = name[start + 2]; if (c2 >= 0x41 && c2 <= 0x5A) c2 |= 32;
          if (c0 == 0x64 && c1 == 0x69 && c2 == 0x76) return true; // div
          if (c0 == 0x70 && c1 == 0x72 && c2 == 0x65) return true; // pre
          if (c0 == 0x6E && c1 == 0x61 && c2 == 0x76) return true; // nav
          return false;
        }

      case 4:
        {
          int c1 = name[start + 1]; if (c1 >= 0x41 && c1 <= 0x5A) c1 |= 32;
          int c2 = name[start + 2]; if (c2 >= 0x41 && c2 <= 0x5A) c2 |= 32;
          int c3 = name[start + 3]; if (c3 >= 0x41 && c3 <= 0x5A) c3 |= 32;
          if (c0 == 0x6D && c1 == 0x61 && c2 == 0x69 && c3 == 0x6E) return true; // main
          return false;
        }

      case 5:
        {
          int c1 = name[start + 1]; if (c1 >= 0x41 && c1 <= 0x5A) c1 |= 32;
          int c2 = name[start + 2]; if (c2 >= 0x41 && c2 <= 0x5A) c2 |= 32;
          int c3 = name[start + 3]; if (c3 >= 0x41 && c3 <= 0x5A) c3 |= 32;
          int c4 = name[start + 4]; if (c4 >= 0x41 && c4 <= 0x5A) c4 |= 32;
          // table
          if (c0==0x74 && c1==0x61 && c2==0x62 && c3==0x6C && c4==0x65) return true;
          // aside
          if (c0==0x61 && c1==0x73 && c2==0x69 && c3==0x64 && c4==0x65) return true;
          return false;
        }

      default:
        return _matchesLongBlockTag(name, start, tlen);
    }
  }

  static bool _matchesLongBlockTag(List<int> name, int start, int tlen) {
    final sb = StringBuffer();
    for (int i = start; i < start + tlen; i++) {
      int c = name[i];
      if (c >= 0x41 && c <= 0x5A) c |= 32;
      sb.writeCharCode(c);
    }
    switch (sb.toString()) {
      case 'header':
      case 'footer':
      case 'figure':
      case 'section':
      case 'article':
      case 'caption':
      case 'figcaption':
      case 'blockquote':
        return true;
      default:
        return false;
    }
  }

  /// Handles an HTML entity starting at [i]+1 in [text].
  /// Advances [iRef[0]] past the closing ';'.
  /// Returns true if the entity is a whitespace separator (caller should flush word).
  static bool isWhitespaceEntity(String text, int len, List<int> iRef) {
    int start = iRef[0] + 1;
    int end = start;

    while (end < len && end - start < 10 && text.codeUnitAt(end) != 0x3B) {
      end++;
    }

    if (end >= len || text.codeUnitAt(end) != 0x3B) {
      return false; // malformed
    }

    iRef[0] = end; // advance past ';'

    int elen = end - start;
    if (elen == 0) return false;

    int e0 = text.codeUnitAt(start);

    // &nbsp;
    if (e0 == 0x6E && elen == 4 &&
        text.codeUnitAt(start+1)==0x62 &&
        text.codeUnitAt(start+2)==0x73 &&
        text.codeUnitAt(start+3)==0x70) return true;

    // &ensp;
    if (e0 == 0x65 && elen == 4 &&
        text.codeUnitAt(start+1)==0x6E &&
        text.codeUnitAt(start+2)==0x73 &&
        text.codeUnitAt(start+3)==0x70) return true;

    // &emsp;
    if (e0 == 0x65 && elen == 4 &&
        text.codeUnitAt(start+1)==0x6D &&
        text.codeUnitAt(start+2)==0x73 &&
        text.codeUnitAt(start+3)==0x70) return true;

    // Numeric whitespace entities: &#160; &#8194; &#8195; &#8201;
    if (e0 == 0x23 && elen > 1) {
      int val = 0;
      bool ok = true;
      for (int k = start + 1; k < end; k++) {
        int d = text.codeUnitAt(k);
        if (d < 0x30 || d > 0x39) { ok = false; break; }
        val = val * 10 + (d - 0x30);
      }
      if (ok && (val == 160 || val == 8194 || val == 8195 || val == 8201)) {
        return true;
      }
    }

    return false;
  }
}
