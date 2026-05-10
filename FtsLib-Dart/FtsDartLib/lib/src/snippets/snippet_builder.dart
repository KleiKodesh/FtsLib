import '../tokenization/token_stream.dart';
import 'snippet_result.dart';

/// Builds a highlighted HTML snippet from raw HTML content and a set of query terms.
///
/// Single-pass design — the raw HTML is scanned exactly once:
///   1. [TokenStream] tokenizes the raw HTML, producing tokens with raw char
///      positions AND cumulative visible-char offsets.
///   2. A sliding-window algorithm finds the tightest token window covering all terms.
///   3. ExpandWindow binary-searches the token list to add context — O(log n).
///   4. The renderer walks only the snippet range, stripping tags inline.
///
/// All internal data structures are reused across calls — zero per-call heap
/// allocation on the hot path. Not thread-safe — one instance per thread.
class SnippetBuilder {
  final String _preTag;
  final String _postTag;
  final int _snippetLength;
  final int _contextWords;

  final TokenStream _tokenStream = TokenStream();

  // ── Reused per-call state ─────────────────────────────────────

  final Map<String, int> _termToGroup = {};
  List<int> _groupCount = List<int>.filled(8, 0, growable: true);

  final Set<String> _termSet = {};
  final Set<String> _allTerms = {};
  final StringBuffer _renderBuf = StringBuffer();

  SnippetBuilder({
    String preTag = '<mark>',
    String postTag = '</mark>',
    int snippetLength = 400,
    int contextWords = 8,
  })  : _preTag = preTag,
        _postTag = postTag,
        _snippetLength = snippetLength,
        _contextWords = contextWords;

  // ── Public API ───────────────────────────────────────────────

  SnippetResult buildFromTerms(String rawHtml, List<String> queryTerms) {
    if (rawHtml.isEmpty || queryTerms.isEmpty) {
      return SnippetResult(_encode(rawHtml), 0x7FFFFFFF, 0x7FFFFFFF, false);
    }

    final tokens = _tokenStream.tokenize(rawHtml);
    return _buildCoreLiteral(tokens, rawHtml, queryTerms);
  }

  SnippetResult buildFromGroups(
    String rawHtml,
    List<List<String>> queryGroups, {
    bool requireOrdered = false,
    int originalGroupCount = 0,
  }) {
    if (rawHtml.isEmpty || queryGroups.isEmpty) {
      return SnippetResult(_encode(rawHtml), 0x7FFFFFFF, 0x7FFFFFFF, false);
    }

    _allTerms.clear();
    for (final g in queryGroups) {
      for (final t in g) _allTerms.add(t);
    }

    int denominator =
        originalGroupCount > 0 ? originalGroupCount : queryGroups.length;

    final tokens = _tokenStream.tokenize(rawHtml);
    final result =
        _buildCoreGroups(tokens, rawHtml, queryGroups, _allTerms, denominator);

    if (requireOrdered && result.isMatch && queryGroups.length > 1) {
      if (!_hasOrderedMatch(tokens)) {
        return SnippetResult(
            result.html, result.score, result.wordDistance, false);
      }
    }

    return result;
  }

  // ── Core pipelines ────────────────────────────────────────────

  SnippetResult _buildCoreLiteral(
      List<TextToken> tokens, String rawHtml, List<String> queryTerms) {
    if (tokens.isEmpty) {
      return SnippetResult(_encode(rawHtml), 0x7FFFFFFF, 0x7FFFFFFF, false);
    }

    final (iLeft, iRight, score) = _findWindowLiteral(tokens, queryTerms);
    if (score == 0x7FFFFFFF) {
      return SnippetResult(_encode(rawHtml), 0x7FFFFFFF, 0x7FFFFFFF, false);
    }

    final (snapStart, snapEnd) =
        _expandWindow(tokens, rawHtml.length, iLeft, iRight);
    String html = _renderFromRaw(rawHtml, tokens, queryTerms, snapStart, snapEnd);
    int wordDist = iRight - iLeft - (queryTerms.length - 1);
    if (wordDist < 0) wordDist = 0;
    return SnippetResult(html, score, wordDist, true);
  }

  SnippetResult _buildCoreGroups(
    List<TextToken> tokens,
    String rawHtml,
    List<List<String>> queryGroups,
    Set<String> highlightTerms,
    int originalGroupCount,
  ) {
    if (tokens.isEmpty) {
      return SnippetResult(_encode(rawHtml), 0x7FFFFFFF, 0x7FFFFFFF, false);
    }

    final (iLeft, iRight, score) = _findWindowGroups(tokens, queryGroups);
    if (score == 0x7FFFFFFF) {
      return SnippetResult(_encode(rawHtml), 0x7FFFFFFF, 0x7FFFFFFF, false);
    }

    final (snapStart, snapEnd) =
        _expandWindow(tokens, rawHtml.length, iLeft, iRight);
    String html =
        _renderFromRaw(rawHtml, tokens, highlightTerms, snapStart, snapEnd);
    int wordDist = iRight - iLeft - (originalGroupCount - 1);
    if (wordDist < 0) wordDist = 0;
    return SnippetResult(html, score, wordDist, true);
  }

  // ── Window finding ────────────────────────────────────────────

  (int iLeft, int iRight, int score) _findWindowLiteral(
      List<TextToken> tokens, List<String> queryTerms) {
    _termToGroup.clear();
    int g = 0;
    for (final t in queryTerms) {
      _termToGroup.putIfAbsent(t, () => g++);
    }

    int required = _termToGroup.length;
    _ensureGroupCount(required);
    for (int i = 0; i < required; i++) _groupCount[i] = 0;
    return _runSlidingWindow(tokens, required);
  }

  (int iLeft, int iRight, int score) _findWindowGroups(
      List<TextToken> tokens, List<List<String>> queryGroups) {
    _termToGroup.clear();
    for (int gi = 0; gi < queryGroups.length; gi++) {
      for (final t in queryGroups[gi]) {
        _termToGroup.putIfAbsent(t, () => gi);
      }
    }

    int required = queryGroups.length;
    _ensureGroupCount(required);
    for (int i = 0; i < required; i++) _groupCount[i] = 0;
    return _runSlidingWindow(tokens, required);
  }

  (int iLeft, int iRight, int score) _runSlidingWindow(
      List<TextToken> tokens, int required) {
    int covered = 0;
    int bestILeft = -1, bestIRight = -1, bestScore = 0x7FFFFFFF;
    int L = 0;

    for (int R = 0; R < tokens.length; R++) {
      String rt = tokens[R].normalized;
      if (_termToGroup.containsKey(rt)) {
        int rg = _termToGroup[rt]!;
        if (_groupCount[rg]++ == 0) covered++;
      }

      while (covered == required) {
        int span = tokens[R].rawEnd - tokens[L].rawStart;
        if (span < bestScore) {
          bestScore = span;
          bestILeft = L;
          bestIRight = R;
        }
        String lt = tokens[L].normalized;
        if (_termToGroup.containsKey(lt)) {
          int lg = _termToGroup[lt]!;
          if (--_groupCount[lg] == 0) covered--;
        }
        L++;
      }
    }

    return (bestILeft, bestIRight, bestScore);
  }

  void _ensureGroupCount(int required) {
    if (_groupCount.length < required) {
      _groupCount = List<int>.filled(required * 2, 0, growable: true);
    }
  }

  // ── Ordered-match validation ──────────────────────────────────

  bool _hasOrderedMatch(List<TextToken> tokens) {
    int numGroups = 0;
    for (final v in _termToGroup.values) {
      if (v >= numGroups) numGroups = v + 1;
    }

    if (numGroups <= 1) return true;

    for (int start = 0; start < tokens.length; start++) {
      if (!_termToGroup.containsKey(tokens[start].normalized)) continue;
      if (_termToGroup[tokens[start].normalized] != 0) continue;

      int pos = start + 1;
      int nextGroup = 1;
      while (nextGroup < numGroups && pos < tokens.length) {
        if (_termToGroup.containsKey(tokens[pos].normalized) &&
            _termToGroup[tokens[pos].normalized] == nextGroup) {
          nextGroup++;
        }
        pos++;
      }

      if (nextGroup == numGroups) return true;
    }

    return false;
  }

  // ── Window expansion ──────────────────────────────────────────

  (int snapStart, int snapEnd) _expandWindow(
      List<TextToken> tokens, int rawLen, int iLeft, int iRight) {
    if (iLeft < 0 || iRight < 0 || tokens.isEmpty) return (0, rawLen);

    int totalVisible = tokens.last.visibleStart + tokens.last.normalized.length;

    if (totalVisible <= _snippetLength) return (0, rawLen);

    int sIdx = (iLeft - _contextWords).clamp(0, tokens.length - 1);
    int eIdx = (iRight + _contextWords).clamp(0, tokens.length - 1);

    while (sIdx < eIdx) {
      int visStart = tokens[sIdx].visibleStart;
      int visEnd = tokens[eIdx].visibleStart + tokens[eIdx].normalized.length;
      if (visEnd - visStart <= _snippetLength) break;
      bool canTrimLeft = sIdx < iLeft;
      bool canTrimRight = eIdx > iRight;
      if (!canTrimLeft && !canTrimRight) break;
      int trimLeft = canTrimLeft
          ? tokens[sIdx + 1].visibleStart - visStart
          : 0x7FFFFFFF;
      int trimRight = canTrimRight
          ? visEnd -
              (tokens[eIdx - 1].visibleStart +
                  tokens[eIdx - 1].normalized.length)
          : 0x7FFFFFFF;
      if (trimLeft <= trimRight) {
        sIdx++;
      } else {
        eIdx--;
      }
    }

    int snapStart = tokens[sIdx].rawStart;
    int snapEnd = eIdx + 1 < tokens.length
        ? tokens[eIdx + 1].rawStart
        : rawLen;

    return (snapStart.clamp(0, rawLen), snapEnd.clamp(0, rawLen));
  }

  // ── Single-pass renderer from raw HTML ────────────────────────

  String _renderFromRaw(
    String rawHtml,
    List<TextToken> tokens,
    Iterable<String> queryTerms,
    int snapStart,
    int snapEnd,
  ) {
    _termSet.clear();
    for (final t in queryTerms) _termSet.add(t);

    _renderBuf.clear();
    if (snapStart > 0) _renderBuf.write('…');

    int pos = snapStart;

    for (final tok in tokens) {
      if (tok.rawEnd <= snapStart) continue;
      if (tok.rawStart >= snapEnd) break;
      if (!_termSet.contains(tok.normalized)) continue;

      _appendRawStripped(rawHtml, pos, tok.rawStart, snapEnd);
      pos = tok.rawStart;

      _renderBuf.write(_preTag);
      int tokEnd = tok.rawEnd < snapEnd ? tok.rawEnd : snapEnd;
      _renderBuf.write(rawHtml.substring(tok.rawStart, tokEnd));
      _renderBuf.write(_postTag);
      pos = tok.rawEnd;
    }

    _appendRawStripped(rawHtml, pos, snapEnd, snapEnd);

    if (snapEnd < rawHtml.length) _renderBuf.write('…');
    return _renderBuf.toString();
  }

  /// Appends rawHtml[from..to) to _renderBuf, stripping HTML tags.
  /// Paragraph markers of the form {X} where X is a Hebrew letter are stripped.
  void _appendRawStripped(String rawHtml, int from, int to, int limit) {
    if (to > limit) to = limit;

    bool inTag = false;
    for (int k = from - 1; k >= 0; k--) {
      int ch = rawHtml.codeUnitAt(k);
      if (ch == 0x3E) break; // '>'
      if (ch == 0x3C) { inTag = true; break; } // '<'
    }

    for (int i = from; i < to; i++) {
      int c = rawHtml.codeUnitAt(i);
      if (inTag) {
        if (c == 0x3E) inTag = false;
        continue;
      }
      if (c == 0x3C) { inTag = true; continue; }

      // Strip {X} paragraph markers where X is a Hebrew letter (U+05D0–U+05EA).
      if (c == 0x7B && i + 2 < to && rawHtml.codeUnitAt(i + 2) == 0x7D) {
        int inner = rawHtml.codeUnitAt(i + 1);
        if (inner >= 0x05D0 && inner <= 0x05EA) { i += 2; continue; }
      }

      _renderBuf.writeCharCode(c);
    }
  }

  /// Strips HTML tags and {X} paragraph markers from a raw HTML string.
  static String _encode(String s) {
    if (s.isEmpty) return '';
    final sb = StringBuffer();
    bool inTag = false;
    for (int i = 0; i < s.length; i++) {
      int c = s.codeUnitAt(i);
      if (inTag) { if (c == 0x3E) inTag = false; continue; }
      if (c == 0x3C) { inTag = true; continue; }
      if (c == 0x7B && i + 2 < s.length && s.codeUnitAt(i + 2) == 0x7D) {
        int inner = s.codeUnitAt(i + 1);
        if (inner >= 0x05D0 && inner <= 0x05EA) { i += 2; continue; }
      }
      sb.writeCharCode(c);
    }
    return sb.toString();
  }
}
