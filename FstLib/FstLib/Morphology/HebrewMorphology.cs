using System;
using System.Collections.Generic;
using System.Linq;

namespace FstLib.Morphology
{
    /// <summary>
    /// Hebrew morphological data: prefixes, suffixes, and prefix combinations.
    /// 
    /// Hebrew morphology is built on:
    /// 1. Roots (typically 3 letters)
    /// 2. Prefixes (תחיליות) - can stack/combine
    /// 3. Suffixes (סיומות) - possessive and object markers
    /// 
    /// INDIVIDUAL PREFIXES (can combine with each other):
    ///   ו (vav) - "and" (conjunction)
    ///   ש (shin) - "that, which" (relative particle)
    ///   ב (bet) - "in, at" (preposition)
    ///   ל (lamed) - "to, for" (preposition)
    ///   כ (kaf) - "as, like" (preposition)
    ///   מ (mem) - "from" (preposition)
    ///   ה (he) - "the" (definite article)
    ///   ת (tav) - "you" (future), "she" (future), noun formation
    ///   י (yod) - "he will" (future marker)
    ///   א (alef) - "I will" (future marker)
    ///   נ (nun) - "we will" (future marker)
    /// 
    /// COMMON PREFIX COMBINATIONS (2-3 prefixes stacking):
    /// Two-prefix: וה, וב, ול, וכ, ומה, שב, של, שה, מה, בה, לה, כה
    /// Three-prefix: ושה, ושב, וכשה, וכש, ולכש, ומהש, שבכ
    /// 
    /// NOUN SUFFIXES (Possessive):
    ///   ־י (my)
    ///   ־ך (your m.s.)
    ///   ־ו (his)
    ///   ־ה (her)
    ///   ־נו (our)
    ///   ־כם (your m.pl.)
    ///   ־כן (your f.pl.)
    ///   ־ם (their m.)
    ///   ־ן (their f.)
    /// 
    /// VERB OBJECT SUFFIXES:
    ///   ־ני (me)
    ///   ־ך (you m.s.)
    ///   ־ו (him)
    ///   ־ה (her)
    ///   ־נו (us)
    ///   ־כם (you m.pl.)
    ///   ־כן (you f.pl.)
    ///   ־ם (them m.)
    ///   ־ן (them f.)
    /// 
    /// PLURAL NOUN SUFFIXES:
    ///   ־ים (masculine plural)
    ///   ־ות (feminine plural)
    /// </summary>
    internal static class HebrewMorphology
    {
        /// <summary>
        /// Most common Hebrew prefixes and prefix combinations (clitics).
        /// Ordered by length (longer first) for greedy matching of combinations.
        /// Based on frequency in modern Hebrew texts.
        /// </summary>
        public static readonly string[] CommonPrefixes = new[]
        {
            // Most common prefix combinations (3-4 characters)
            "וכשה",    // and when + word starting with ה
            "ושה",     // and that + word starting with ה
            "ושב",     // and that is in
            "וכש",     // and when
            
            // Common 2-character prefix combinations
            "וה",      // and the
            "וב",      // and in
            "ול",      // and to
            "וכ",      // and like
            "ומ",      // and from
            "וש",      // and that
            "בה",      // in the
            "לה",      // to the
            "מה",      // from the
            "שב",      // that is in
            "של",      // that is to
            "שה",      // that + word starting with ה
            "כש",      // like/when
            
            // Most frequent individual prefixes
            "ו",       // and (conjunction)
            "ה",       // the (definite article)
            "ב",       // in, at (preposition)
            "ל",       // to, for (preposition)
            "כ",       // as, like (preposition)
            "מ",       // from (preposition)
            "ש",       // that, which (relative particle)
            "י",       // he will (future marker)
            "ת",       // you (future), she (future)
            "א",       // I will (future marker)
            "נ",       // we will (future marker)
        };

        /// <summary>
        /// Most frequent Hebrew suffixes (possessive, object, and plural).
        /// Ordered by length (longer first) for greedy matching.
        /// Based on frequency in modern Hebrew texts.
        /// </summary>
        public static readonly string[] CommonSuffixes = new[]
        {
            // Longer suffixes (3+ characters)
            "ית",      // feminine singular (noun formation)
            "אי",      // masculine singular (adjective/noun formation)
            "ון",      // masculine singular (noun formation)
            "תי",      // my (verb object)
            "נו",      // our / us (verb object)
            
            // 2-character suffixes
            "ים",      // masculine plural
            "ות",      // feminine plural
            "כם",      // your (m.pl.)
            "כן",      // your (f.pl.)
            "ם",       // their (m.) / them (m.)
            "ן",       // their (f.) / them (f.)
            
            // Most frequent single-character suffixes
            "י",       // my / me (verb object)
            "ו",       // his / him (verb object)
            "ה",       // her / feminine singular
            "ת",       // you (f.s.) / feminine marker
            "נ",       // us (verb object)
        };

        /// <summary>
        /// All Hebrew prefixes and suffixes combined (for infix search).
        /// </summary>
        internal static readonly string[] AllAffixes = CommonPrefixes.Concat(CommonSuffixes).Distinct().ToArray();

        /// <summary>
        /// Check if a string is a known Hebrew prefix.
        /// </summary>
        internal static bool IsKnownPrefix(string prefix) => CommonPrefixes.Contains(prefix);

        /// <summary>
        /// Check if a string is a known Hebrew suffix.
        /// </summary>
        internal static bool IsKnownSuffix(string suffix) => CommonSuffixes.Contains(suffix);

        /// <summary>
        /// Check if a string is a known Hebrew affix (prefix or suffix).
        /// </summary>
        internal static bool IsKnownAffix(string affix) => AllAffixes.Contains(affix);

        /// <summary>
        /// Strip known prefixes from the start of a word.
        /// Returns (stripped_word, prefixes_removed).
        /// </summary>
        internal static (string Word, List<string> Prefixes) StripPrefixes(string word)
        {
            var prefixes = new List<string>();
            string remaining = word;

            // Greedily strip prefixes (longest first)
            bool changed = true;
            while (changed)
            {
                changed = false;
                foreach (var prefix in CommonPrefixes.OrderByDescending(p => p.Length))
                {
                    if (remaining.StartsWith(prefix))
                    {
                        prefixes.Add(prefix);
                        remaining = remaining.Substring(prefix.Length);
                        changed = true;
                        break;
                    }
                }
            }

            return (remaining, prefixes);
        }

        /// <summary>
        /// Strip known suffixes from the end of a word.
        /// Returns (stripped_word, suffixes_removed).
        /// </summary>
        internal static (string Word, List<string> Suffixes) StripSuffixes(string word)
        {
            var suffixes = new List<string>();
            string remaining = word;

            // Greedily strip suffixes (longest first)
            foreach (var suffix in CommonSuffixes.OrderByDescending(s => s.Length))
            {
                while (remaining.EndsWith(suffix))
                {
                    suffixes.Insert(0, suffix);
                    remaining = remaining.Substring(0, remaining.Length - suffix.Length);
                }
            }

            return (remaining, suffixes);
        }

        /// <summary>
        /// Strip both prefixes and suffixes from a word.
        /// Returns (root, prefixes, suffixes).
        /// </summary>
        internal static (string Root, List<string> Prefixes, List<string> Suffixes) StripAffixes(string word)
        {
            var (afterPrefix, prefixes) = StripPrefixes(word);
            var (root, suffixes) = StripSuffixes(afterPrefix);
            return (root, prefixes, suffixes);
        }

        /// <summary>
        /// Reconstruct a word from root and affixes.
        /// </summary>
        internal static string ReconstructWord(string root, IEnumerable<string> prefixes, IEnumerable<string> suffixes)
        {
            return string.Concat(prefixes) + root + string.Concat(suffixes);
        }
    }
}
