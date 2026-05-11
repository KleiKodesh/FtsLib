using FtsLib.Indexing;
using System;
using System.Collections.Generic;
using System.Data.SQLite;

namespace FtsLib.Search
{
    /// <summary>
    /// Expands wildcard patterns into the set of concrete terms that exist in the
    /// index by querying each segment's <c>term_index</c> table.
    ///
    /// Supported wildcards:
    ///   '*'  — matches zero or more characters (prefix / suffix / infix)
    ///   '?'  — makes the immediately preceding character optional
    ///          e.g. שלו?ם → {שלום, שלם}  (with or without ו)
    ///          A '?' with no preceding letter (at position 0, or after another '?'
    ///          or after '*') is silently dropped.
    ///
    /// Pattern rules for '*':
    ///   שלו*   → prefix  → LIKE 'שלו%'
    ///   *לום   → suffix  → LIKE '%לום'
    ///   *לו*   → infix   → LIKE '%לו%'
    ///
    /// Expansion limits (both enforced before/after the DB query):
    ///
    ///   MinAnchorLength (2): the non-wildcard anchor must be at least 2 chars.
    ///   Patterns like "*ל" or "מ*" are rejected immediately — they would expand
    ///   to tens of thousands of terms.  The caller receives an empty list and
    ///   should skip the group rather than killing the whole query.
    ///
    ///   MaxPrefixWildcardChars (3) / MaxSuffixWildcardChars (4):
    ///   After the DB query, expanded terms are filtered by how many characters the
    ///   wildcard portion actually matched:
    ///     *abc  (suffix wildcard) — leading '*' capped at 3 chars (max Hebrew prefix)
    ///     abc*  (prefix wildcard) — trailing '*' capped at 4 chars (max Hebrew suffix)
    ///     *abc* (infix wildcard)  — leading capped at 3, trailing at 4 (7 total)
    ///   Research basis: Hebrew stacked prefixes max at 3 (וּמִבְּ); pronominal suffixes
    ///   max at 4 (יהֶם, יכֶם).  Anything longer is a compound run-on, not an affix.
    ///
    ///   MaxOptionalChars (4): a pattern may contain at most this many '?' operators.
    ///   Patterns with more are rejected to cap the 2^N combinatorial expansion.
    /// </summary>
    internal static class HebrewWildcardExpander
    {
        /// <summary>
        /// Minimum number of non-wildcard characters a pattern must contain.
        /// Patterns shorter than this are rejected before hitting the DB.
        /// </summary>
        public const int MinAnchorLength = 2;

        /// <summary>
        /// Maximum characters the leading '*' of a suffix wildcard (*abc) may match.
        /// Hebrew/Aramaic prefixes stack to at most 3 chars (e.g. וּמִבְּ = vav+mem+bet).
        /// </summary>
        public const int MaxPrefixWildcardChars = 3;

        /// <summary>
        /// Maximum characters the trailing '*' of a prefix wildcard (abc*) may match.
        /// Hebrew pronominal suffixes reach at most 4 chars (e.g. יהֶם, יכֶם, יהֶן).
        /// Verb conjugation suffixes top out at 3 chars (תֶּם, תֶּן), so 4 is the safe cap.
        /// </summary>
        public const int MaxSuffixWildcardChars = 4;

        /// <summary>
        /// Maximum number of '?' operators allowed in a single pattern.
        /// Caps the 2^N combinatorial expansion at 2^4 = 16 variants.
        /// </summary>
        public const int MaxOptionalChars = 4;

        // ── Public entry point ────────────────────────────────────────

        /// <summary>
        /// Expands a pattern that may contain '*', '?', or both.
        ///
        /// '?' patterns are first unrolled into up to 2^N concrete sub-patterns
        /// (each with/without the optional char), then each sub-pattern is either
        /// looked up as a literal or expanded via the '*' LIKE query.
        ///
        /// Returns an empty list when the anchor is too short, the '?' count
        /// exceeds <see cref="MaxOptionalChars"/>, or nothing survives the filter.
        /// </summary>
        public static List<string> Expand(string pattern, IReadOnlyList<SegmentHandle> segments)
        {
            bool hasOptional = pattern.IndexOf('?') >= 0;
            bool hasStar     = pattern.IndexOf('*') >= 0;

            if (!hasOptional)
                return ExpandStar(pattern, segments);   // fast path — original behaviour

            // Count '?' operators (after normalising away no-op ones).
            // We count positions where '?' has a real preceding letter.
            int optCount = CountEffectiveOptionals(pattern);
            if (optCount > MaxOptionalChars)
                return new List<string>();

            // Generate all sub-patterns by including/excluding each optional char.
            var subPatterns = new HashSet<string>(StringComparer.Ordinal);
            ExpandOptionals(pattern, 0, new System.Text.StringBuilder(pattern.Length), subPatterns);

            // Collect results across all sub-patterns, deduplicating.
            var seen    = new HashSet<string>(StringComparer.Ordinal);
            var results = new List<string>();

            foreach (var sub in subPatterns)
            {
                List<string> expanded;
                if (sub.IndexOf('*') >= 0)
                    expanded = ExpandStar(sub, segments);
                else
                    expanded = LookupLiteral(sub, segments);

                foreach (var term in expanded)
                    if (seen.Add(term))
                        results.Add(term);
            }

            return results;
        }

        // ── '*'-only expansion (original logic) ───────────────────────

        /// <summary>
        /// Queries every segment for terms matching <paramref name="pattern"/>
        /// (which must contain only '*' wildcards, no '?'), then filters out any
        /// result where the wildcard portion exceeds the allowed affix length.
        ///
        /// When the segment has a trigram_index, uses exact trigram lookup on the
        /// anchor portion of the pattern (O(log n)) then filters results in memory.
        /// Falls back to a LIKE scan for old segments without the trigram table.
        /// </summary>
        public static List<string> ExpandStar(string pattern, IReadOnlyList<SegmentHandle> segments)
        {
            int anchorLen = AnchorLength(pattern);
            if (anchorLen < MinAnchorLength)
                return new List<string>();

            // Extract the anchor — the non-wildcard portion of the pattern.
            // For prefix (abc*) the anchor is the prefix; for suffix (*abc) it's the
            // suffix; for infix (*abc*) it's the middle part.
            string anchor      = StripWildcard(pattern);
            string likePattern = ToLikePattern(pattern);

            bool hasLeadingStar  = pattern.StartsWith("*");
            bool hasTrailingStar = pattern.EndsWith("*");

            var raw = new HashSet<string>(StringComparer.Ordinal);

            foreach (var seg in segments)
            {
                if (seg.HasTrigramIndex && anchor.Length >= 3)
                {
                    // Fast path: look up trigrams of the anchor, then verify each
                    // candidate against the full LIKE pattern in memory.
                    // This replaces a full table scan with targeted B-tree lookups.
                    var trigrams = FuzzyExpander.BuildNgrams(anchor, 3);
                    // Use the least-common trigram to minimise candidates.
                    // For now use the first one — all are equally selective for a
                    // random anchor; a frequency table would be needed to do better.
                    seg.TrigramLookup.Parameters["@g"].Value = trigrams[0];
                    using (var reader = seg.TrigramLookup.ExecuteReader())
                        while (reader.Read())
                        {
                            string term = reader.GetString(0);
                            // Verify against the full pattern in memory — cheap string op.
                            if (MatchesLike(term, likePattern))
                                raw.Add(term);
                        }
                }
                else
                {
                    // Fallback: LIKE scan (old segment or short anchor).
                    using (var cmd = seg.Conn.CreateCommand())
                    {
                        cmd.CommandText =
                            "SELECT term FROM term_index WHERE term LIKE @p ESCAPE '\\'";
                        cmd.Parameters.Add("@p", System.Data.DbType.String).Value = likePattern;
                        using (var reader = cmd.ExecuteReader())
                            while (reader.Read())
                                raw.Add(reader.GetString(0));
                    }
                }
            }

            // Filter by wildcard budget (same logic as before).
            var results = new List<string>(raw.Count);
            foreach (var term in raw)
            {
                int extra = term.Length - anchorLen;
                if (hasLeadingStar && hasTrailingStar)
                {
                    if (extra <= MaxPrefixWildcardChars + MaxSuffixWildcardChars)
                        results.Add(term);
                }
                else if (hasLeadingStar)
                {
                    if (extra <= MaxPrefixWildcardChars)
                        results.Add(term);
                }
                else
                {
                    if (extra <= MaxSuffixWildcardChars)
                        results.Add(term);
                }
            }

            return results;
        }

        /// <summary>
        /// In-memory match of <paramref name="term"/> against a SQLite-style LIKE
        /// <paramref name="likePattern"/> (where '%' = any sequence, '\' = escape).
        ///
        /// Dispatches to fast string primitives for the three common shapes that
        /// arise from pure '*' patterns, and falls back to the general recursive
        /// matcher only for complex patterns produced by '?' expansion.
        ///
        ///   prefix%          → StartsWith
        ///   %suffix          → EndsWith
        ///   %infix%          → Contains
        ///   prefix%suffix    → StartsWith + EndsWith (non-overlapping)
        ///   anything else    → recursive matcher
        /// </summary>
        private static bool MatchesLike(string term, string likePattern)
        {
            // Count and locate '%' wildcards (ignoring escaped ones).
            int first = -1, second = -1, pctCount = 0;
            for (int i = 0; i < likePattern.Length; i++)
            {
                if (likePattern[i] == '\\') { i++; continue; } // skip escaped char
                if (likePattern[i] != '%') continue;
                pctCount++;
                if (first  < 0) first  = i;
                else if (second < 0) second = i;
            }

            // ── Fast paths ────────────────────────────────────────────

            if (pctCount == 0)
            {
                // No wildcards — exact match (after unescaping).
                return string.Equals(term, UnescapeLike(likePattern), StringComparison.Ordinal);
            }

            if (pctCount == 1)
            {
                string before = UnescapeLike(likePattern.Substring(0, first));
                string after  = UnescapeLike(likePattern.Substring(first + 1));

                if (before.Length == 0)
                    // %suffix — term must end with suffix
                    return after.Length == 0 || term.EndsWith(after, StringComparison.Ordinal);

                if (after.Length == 0)
                    // prefix% — term must start with prefix
                    return term.StartsWith(before, StringComparison.Ordinal);

                // prefix%suffix — term must start with prefix AND end with suffix,
                // and the two parts must not overlap.
                return term.Length >= before.Length + after.Length
                    && term.StartsWith(before, StringComparison.Ordinal)
                    && term.EndsWith(after,   StringComparison.Ordinal);
            }

            if (pctCount == 2 && first == 0 && second == likePattern.Length - 1)
            {
                // %infix% — term must contain infix
                string infix = UnescapeLike(likePattern.Substring(1, likePattern.Length - 2));
                return infix.Length == 0 || term.IndexOf(infix, StringComparison.Ordinal) >= 0;
            }

            // ── General fallback (complex patterns from '?' expansion) ─
            return LikeMatch(term, 0, likePattern, 0);
        }

        /// <summary>Removes LIKE escape characters ('\\' prefix) from a pattern segment.</summary>
        private static string UnescapeLike(string s)
        {
            if (s.IndexOf('\\') < 0) return s; // fast path — nothing to unescape
            var sb = new System.Text.StringBuilder(s.Length);
            for (int i = 0; i < s.Length; i++)
            {
                if (s[i] == '\\' && i + 1 < s.Length) { i++; sb.Append(s[i]); }
                else sb.Append(s[i]);
            }
            return sb.ToString();
        }

        private static bool LikeMatch(string text, int ti, string pattern, int pi)
        {
            while (pi < pattern.Length)
            {
                char p = pattern[pi];
                if (p == '%')
                {
                    // Skip consecutive '%'
                    while (pi < pattern.Length && pattern[pi] == '%') pi++;
                    if (pi == pattern.Length) return true; // trailing % matches anything
                    // Try matching the rest of the pattern at every position in text
                    for (int i = ti; i <= text.Length; i++)
                        if (LikeMatch(text, i, pattern, pi)) return true;
                    return false;
                }
                else if (p == '\\' && pi + 1 < pattern.Length)
                {
                    // Escaped character — match literally
                    pi++;
                    if (ti >= text.Length || text[ti] != pattern[pi]) return false;
                    ti++; pi++;
                }
                else
                {
                    if (ti >= text.Length || text[ti] != p) return false;
                    ti++; pi++;
                }
            }
            return ti == text.Length;
        }

        // ── '?' expansion helpers ─────────────────────────────────────

        /// <summary>
        /// Recursively generates all sub-patterns by including or excluding each
        /// optional character (the char immediately before a '?').
        ///
        /// A '?' is a no-op (silently dropped) when:
        ///   - it appears at position 0 (nothing before it), or
        ///   - the character immediately before it is another '?' or a '*'
        ///     (wildcards cannot themselves be made optional).
        /// </summary>
        private static void ExpandOptionals(
            string                      pattern,
            int                         pos,
            System.Text.StringBuilder   current,
            HashSet<string>             results)
        {
            if (pos == pattern.Length)
            {
                results.Add(current.ToString());
                return;
            }

            char c = pattern[pos];

            if (c != '?')
            {
                current.Append(c);
                ExpandOptionals(pattern, pos + 1, current, results);
                current.Length--;
                return;
            }

            // c == '?'
            // Determine whether the preceding character in `current` is a real letter
            // (not a wildcard) that can be made optional.
            bool hasOptionalTarget =
                current.Length > 0 &&
                current[current.Length - 1] != '*';
            // (A preceding '?' was already consumed as a letter or dropped, so the
            //  last char in `current` at this point is always a real letter or '*'.)

            if (!hasOptionalTarget)
            {
                // No-op '?' — just skip it and continue.
                ExpandOptionals(pattern, pos + 1, current, results);
                return;
            }

            // Branch 1: include the optional char (do nothing — it's already in `current`).
            ExpandOptionals(pattern, pos + 1, current, results);

            // Branch 2: exclude the optional char (remove the last char from `current`).
            char saved = current[current.Length - 1];
            current.Length--;
            ExpandOptionals(pattern, pos + 1, current, results);
            current.Append(saved); // restore for the caller
        }

        /// <summary>
        /// Counts the number of '?' operators that have a real (non-wildcard)
        /// preceding character — i.e. the ones that will actually produce two branches.
        /// </summary>
        private static int CountEffectiveOptionals(string pattern)
        {
            int count = 0;
            for (int i = 0; i < pattern.Length; i++)
            {
                if (pattern[i] != '?') continue;
                if (i == 0) continue;                    // no preceding char
                char prev = pattern[i - 1];
                if (prev == '*' || prev == '?') continue; // wildcard before '?' is a no-op
                count++;
            }
            return count;
        }

        // ── Literal lookup ────────────────────────────────────────────

        /// <summary>
        /// Looks up an exact term across all segments.
        /// Returns a single-element list if found, empty list otherwise.
        /// </summary>
        private static List<string> LookupLiteral(string term, IReadOnlyList<SegmentHandle> segments)
        {
            if (AnchorLength(term) < MinAnchorLength)
                return new List<string>();

            foreach (var seg in segments)
            {
                using (var cmd = seg.Conn.CreateCommand())
                {
                    cmd.CommandText = "SELECT 1 FROM term_index WHERE term = @t LIMIT 1";
                    cmd.Parameters.Add("@t", System.Data.DbType.String).Value = term;
                    var scalar = cmd.ExecuteScalar();
                    if (scalar != null)
                        return new List<string> { term };
                }
            }
            return new List<string>();
        }

        // ── Pattern translation ───────────────────────────────────────

        /// <summary>
        /// Converts a user wildcard pattern (using '*') to a SQLite LIKE pattern
        /// (using '%'). Literal '%' and '_' in the input are escaped with '\'.
        /// '?' characters must have been removed before calling this method.
        /// </summary>
        internal static string ToLikePattern(string pattern)
        {
            var sb = new System.Text.StringBuilder(pattern.Length + 4);
            foreach (char c in pattern)
            {
                switch (c)
                {
                    case '%':  sb.Append("\\%"); break;
                    case '_':  sb.Append("\\_"); break;
                    case '*':  sb.Append('%');   break;
                    default:   sb.Append(c);     break;
                }
            }
            return sb.ToString();
        }

        /// <summary>
        /// Returns the pattern with all '*' and '?' characters removed — used as the
        /// fallback literal when expansion yields no results.
        /// </summary>
        public static string StripWildcard(string pattern)
            => pattern.Replace("*", string.Empty).Replace("?", string.Empty);

        // ── Helpers ──────────────────────────────────────────────────

        /// <summary>
        /// Returns the number of non-wildcard ('*' or '?') characters in
        /// <paramref name="pattern"/>.
        /// </summary>
        internal static int AnchorLength(string pattern)
        {
            int n = 0;
            foreach (char c in pattern)
                if (c != '*' && c != '?') n++;
            return n;
        }
    }
}
