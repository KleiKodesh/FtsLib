/// Parses a raw query string into a [ParsedQuery].
///
/// Rules:
///   - Tokens are split on whitespace.
///   - A bare '|' token acts as an OR separator.
///   - A token containing '*' or '?' is a wildcard term.
///   - A token ending with '~' or '~N' (N = 1–3) is a fuzzy term.
///   - All others are literals.
///   - Nikud (U+05B0–U+05C7) and cantillation (U+0591–U+05AF) are stripped.
///   - English letters are lowercased.
///   - Non-letter, non-'*', non-'?' characters are dropped.
///   - Empty tokens (after stripping) are ignored.
class QueryParser {
  static ParsedQuery parse(String query) {
    final groups = <QueryGroup>[];

    if (query.trim().isEmpty) return ParsedQuery(groups);

    // Pad every '|' with spaces so "א|ב" and "א | ב" are treated identically.
    query = query.replaceAll('|', ' | ');

    final pendingGroup = <SubPattern>[];
    bool lastWasPipe = false;

    for (final raw in query.split(RegExp(r'[ \t\r\n]+'))) {
      if (raw.isEmpty) continue;

      bool isPipe = _isPipeToken(raw);

      if (isPipe) {
        lastWasPipe = true;
        continue;
      }

      final sp = _parseToken(raw);
      if (sp == null) continue;

      if (!lastWasPipe && pendingGroup.isNotEmpty) {
        groups.add(QueryGroup(List.of(pendingGroup)));
        pendingGroup.clear();
      }

      pendingGroup.add(sp);
      lastWasPipe = false;
    }

    if (pendingGroup.isNotEmpty) groups.add(QueryGroup(List.of(pendingGroup)));

    return ParsedQuery(groups);
  }

  // ── Token parsing ─────────────────────────────────────────────

  static bool _isPipeToken(String raw) {
    for (int i = 0; i < raw.length; i++) {
      if (raw.codeUnitAt(i) != 0x7C) return false; // '|'
    }
    return true;
  }

  static SubPattern? _parseToken(String raw) {
    String tokenText = raw;
    bool isFuzzy = false;
    int fuzzyDist = 1;

    int tildePos = raw.lastIndexOf('~');
    if (tildePos >= 0) {
      String suffix = raw.substring(tildePos + 1);
      String prefix = raw.substring(0, tildePos);

      if (suffix.isEmpty ||
          (suffix.length == 1 &&
              suffix.codeUnitAt(0) >= 0x31 &&
              suffix.codeUnitAt(0) <= 0x39)) {
        isFuzzy = true;
        fuzzyDist = suffix.isEmpty ? 1 : int.parse(suffix);
        if (fuzzyDist > 3) fuzzyDist = 3; // maxAllowedDistance
        tokenText = prefix;
      }
    }

    String normalised = _normalise(tokenText);
    if (normalised.isEmpty) return null;

    bool isWildcard = normalised.contains('*') || normalised.contains('?');

    // Fuzzy + wildcard on the same token: wildcard wins.
    if (isFuzzy && isWildcard) isFuzzy = false;

    return SubPattern(normalised, isWildcard, isFuzzy, fuzzyDist);
  }

  // ── Normalisation ─────────────────────────────────────────────

  static String _normalise(String token) {
    final sb = StringBuffer();
    for (int i = 0; i < token.length; i++) {
      int c = token.codeUnitAt(i);

      // Strip nikud (U+05B0–U+05C7) and cantillation (U+0591–U+05AF)
      if (c >= 0x0591 && c <= 0x05C7) continue;

      if (c == 0x2A) { sb.writeCharCode(0x2A); continue; } // '*'
      if (c == 0x3F) { sb.writeCharCode(0x3F); continue; } // '?'

      // Hebrew letters U+05D0–U+05EA
      if (c >= 0x05D0 && c <= 0x05EA) { sb.writeCharCode(c); continue; }

      // ASCII letters — lowercase
      if (c >= 0x41 && c <= 0x5A) { sb.writeCharCode(c | 32); continue; }
      if (c >= 0x61 && c <= 0x7A) { sb.writeCharCode(c); continue; }

      // Everything else is dropped
    }
    return sb.toString();
  }
}

// ── Value types ───────────────────────────────────────────────────

/// The result of parsing a query: an ordered list of groups.
/// Each group is an OR set of one or more sub-patterns; across groups the
/// semantics are AND.
class ParsedQuery {
  final List<QueryGroup> groups;
  ParsedQuery(this.groups);
  bool get isEmpty => groups.isEmpty;
}

/// One AND slot in the query, containing one or more OR alternatives.
class QueryGroup {
  final List<SubPattern> alternatives;
  QueryGroup(this.alternatives);

  bool get isSingle => alternatives.length == 1;
  String get pattern => alternatives[0].pattern;
  bool get isWildcard => alternatives[0].isWildcard;
  bool get isFuzzy => alternatives[0].isFuzzy;
  int get fuzzyDistance => alternatives[0].fuzzyDistance;
}

/// One OR alternative within a [QueryGroup].
class SubPattern {
  final String pattern;
  final bool isWildcard;
  final bool isFuzzy;
  final int fuzzyDistance;

  const SubPattern(
    this.pattern,
    this.isWildcard, [
    this.isFuzzy = false,
    this.fuzzyDistance = 1,
  ]);
}
