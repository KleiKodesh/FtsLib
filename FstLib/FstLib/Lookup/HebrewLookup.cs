using System;
using System.Collections.Generic;
using System.Linq;
using FstLib.Core;
using FstLib.Morphology;

namespace FstLib.Lookup
{
    /// <summary>
    /// Hebrew-specific affix-aware pattern lookups using known morphological affixes.
    /// 
    /// These methods are wrappers around the regular StartsWith/EndsWith/Contains methods,
    /// with additional filtering to ensure only known Hebrew morphological affixes are used.
    /// 
    /// - HebrewAffixEndsWith: Uses regular EndsWith, then filters by Hebrew prefix affixes
    ///   Example: target="כל" finds "כל", "בכל", "לכל", "שכל", "וכל", "הכל", "כשכל", etc.
    ///   (all words ending with "כל" that have only known Hebrew prefix affixes)
    /// 
    /// - HebrewAffixStartsWith: Uses regular StartsWith, then filters by Hebrew suffix affixes
    ///   Example: target="כל" finds "כל", "כלם", "כלך", "כלנו", "כלים", "כלות", etc.
    ///   (all words starting with "כל" that have only known Hebrew suffix affixes)
    /// 
    /// - HebrewAffixContains: Uses regular Contains, then filters by Hebrew prefix and/or suffix affixes
    ///   Example: target="כל" finds "כל", "בכל", "כלם", "שכלך", "הכלים", "בכלנו", "וכלות", "כשכלם", etc.
    ///   (all words containing "כל" that have only known Hebrew prefix and/or suffix affixes)
    /// 
    /// All methods include the word itself if it exists (no affixes).
    /// </summary>
    internal sealed partial class FstLookup
    {
        // ── Hebrew Affix EndsWith Lookup ──────────────────────────

        /// <summary>
        /// Enumerates all words that end with the target, filtered by known Hebrew prefix affixes.
        /// Wrapper around EnumerateEndsWith with Hebrew morphological affix validation.
        /// </summary>
        /// <param name="target">The target word to find (e.g., "כל").</param>
        /// <returns>All (key, value) pairs where the word ends with target and any prefix affix is a known Hebrew morphological prefix.</returns>
        /// <remarks>
        /// Algorithm:
        /// 1. Use EnumerateEndsWith(target) to find all words ending with target
        /// 2. For each result, strip prefix affixes and validate they are known Hebrew morphological prefixes
        /// 3. Include the target word itself (no prefix affixes)
        /// 
        /// Example: target="כל" finds "כל", "בכל", "לכל", "שכל", "וכל", "הכל", "כשכל", etc.
        /// But NOT "xyכל" (because "xy" is not a known Hebrew prefix affix)
        /// </remarks>
        internal IEnumerable<(string Key, long Value)> EnumerateHebrewAffixEndsWith(string target)
        {
            if (target == null) throw new ArgumentNullException(nameof(target));
            if (target.Length == 0) throw new ArgumentException("Target cannot be empty");

            // Use regular EndsWith and filter by Hebrew prefix affix morphology
            foreach (var (key, value) in EnumerateEndsWith(target))
            {
                var (stripped, prefixAffixes) = HebrewMorphology.StripPrefixes(key);
                
                // Include if stripped word equals target and all prefix affixes are known Hebrew morphological prefixes
                if (stripped == target && prefixAffixes.All(p => HebrewMorphology.IsKnownPrefix(p)))
                    yield return (key, value);
            }
        }

        // ── Hebrew Affix StartsWith Lookup ────────────────────────

        /// <summary>
        /// Enumerates all words that start with the target, filtered by known Hebrew suffix affixes.
        /// Wrapper around EnumerateStartsWith with Hebrew morphological affix validation.
        /// </summary>
        /// <param name="target">The target word to find (e.g., "כל").</param>
        /// <returns>All (key, value) pairs where the word starts with target and any suffix affix is a known Hebrew morphological suffix.</returns>
        /// <remarks>
        /// Algorithm:
        /// 1. Use EnumerateStartsWith(target) to find all words starting with target
        /// 2. For each result, strip suffix affixes and validate they are known Hebrew morphological suffixes
        /// 3. Include the target word itself (no suffix affixes)
        /// 
        /// Example: target="כל" finds "כל", "כלם", "כלך", "כלנו", "כלים", "כלות", etc.
        /// But NOT "כלxy" (because "xy" is not a known Hebrew suffix affix)
        /// </remarks>
        internal IEnumerable<(string Key, long Value)> EnumerateHebrewAffixStartsWith(string target)
        {
            if (target == null) throw new ArgumentNullException(nameof(target));
            if (target.Length == 0) throw new ArgumentException("Target cannot be empty");

            // Use regular StartsWith and filter by Hebrew suffix affix morphology
            foreach (var (key, value) in EnumerateStartsWith(target))
            {
                var (stripped, suffixAffixes) = HebrewMorphology.StripSuffixes(key);
                
                // Include if stripped word equals target and all suffix affixes are known Hebrew morphological suffixes
                if (stripped == target && suffixAffixes.All(s => HebrewMorphology.IsKnownSuffix(s)))
                    yield return (key, value);
            }
        }

        // ── Hebrew Affix Contains Lookup ──────────────────────────

        /// <summary>
        /// Enumerates all words that contain the target, filtered by known Hebrew prefix and/or suffix affixes.
        /// Wrapper around EnumerateContains with Hebrew morphological affix validation.
        /// </summary>
        /// <param name="target">The target word to find (e.g., "כל").</param>
        /// <returns>All (key, value) pairs where the word contains target and any affixes are known Hebrew morphological affixes.</returns>
        /// <remarks>
        /// Algorithm:
        /// 1. Use EnumerateContains(target) to find all words containing target
        /// 2. For each result, strip prefix and suffix affixes and validate they are known Hebrew morphological affixes
        /// 3. Include the target word itself (no affixes)
        /// 
        /// Example: target="כל" finds "כל", "בכל", "כלם", "שכלך", "הכלים", "בכלנו", "וכלות", "כשכלם", etc.
        /// But NOT "xyכלxy" (because "xy" is not a known Hebrew affix)
        /// </remarks>
        internal IEnumerable<(string Key, long Value)> EnumerateHebrewAffixContains(string target)
        {
            if (target == null) throw new ArgumentNullException(nameof(target));
            if (target.Length == 0) throw new ArgumentException("Target cannot be empty");

            // Use regular Contains and filter by Hebrew affix morphology
            foreach (var (key, value) in EnumerateContains(target))
            {
                var (stripped, prefixAffixes, suffixAffixes) = HebrewMorphology.StripAffixes(key);
                
                // Include if stripped word equals target and all affixes are known Hebrew morphological affixes
                if (stripped == target && 
                    prefixAffixes.All(p => HebrewMorphology.IsKnownPrefix(p)) &&
                    suffixAffixes.All(s => HebrewMorphology.IsKnownSuffix(s)))
                    yield return (key, value);
            }
        }

        // ── Deprecated aliases for backward compatibility ────────

        /// <summary>
        /// Deprecated: Use EnumerateHebrewAffixEndsWith instead.
        /// </summary>
        [Obsolete("Use EnumerateHebrewAffixEndsWith instead")]
        public IEnumerable<(string Key, long Value)> EnumerateHebrewEndsWith(string target)
            => EnumerateHebrewAffixEndsWith(target);

        /// <summary>
        /// Deprecated: Use EnumerateHebrewAffixStartsWith instead.
        /// </summary>
        [Obsolete("Use EnumerateHebrewAffixStartsWith instead")]
        public IEnumerable<(string Key, long Value)> EnumerateHebrewStartsWith(string target)
            => EnumerateHebrewAffixStartsWith(target);

        /// <summary>
        /// Deprecated: Use EnumerateHebrewAffixContains instead.
        /// </summary>
        [Obsolete("Use EnumerateHebrewAffixContains instead")]
        public IEnumerable<(string Key, long Value)> EnumerateHebrewContains(string target)
            => EnumerateHebrewAffixContains(target);
    }
}
