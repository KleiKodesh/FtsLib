using System;
using System.Collections.Generic;
using FstLib.Core;
using FstLib.Lookup;
using FstLib.Storage;

namespace FstLib
{
    /// <summary>
    /// API for querying FST indexes with various lookup patterns.
    ///
    /// Example
    /// ───────
    ///   // Query a single key
    ///   if (FstLookupApi.Lookup("index.fst", "stop", out long val))
    ///       Console.WriteLine(val); // value associated with "stop"
    ///
    ///   // Fuzzy search
    ///   var fuzzyResults = FstLookupApi.LookupFuzzy("index.fst", "stop", maxEdits: 1);
    /// </summary>
    public static class FstLookupApi
    {
        /// <summary>
        /// Loads the FST stored at <paramref name="filePath"/> and looks up <paramref name="key"/>.
        /// </summary>
        /// <param name="filePath">Path to the FST file written by <see cref="FstBuildApi.BuildAndSave"/>.</param>
        /// <param name="key">The key to search for.</param>
        /// <param name="value">
        ///   When this method returns <c>true</c>, contains the value associated with
        ///   <paramref name="key"/>; otherwise 0.
        /// </param>
        /// <returns><c>true</c> if <paramref name="key"/> was found; otherwise <c>false</c>.</returns>
        /// <remarks>
        ///   This method loads the FST from disk on every call, which is appropriate
        ///   for one-off queries.  For repeated lookups against the same index, load
        ///   the FST once with <see cref="FstPersistence.Load"/> and reuse a single
        ///   <see cref="FstLookup"/> instance.
        /// </remarks>
        public static bool Lookup(string filePath, string key, out long value)
        {
            if (filePath == null) throw new ArgumentNullException(nameof(filePath));
            if (key      == null) throw new ArgumentNullException(nameof(key));

            Fst       fst    = FstPersistence.Load(filePath);
            var       lookup = new FstLookup(fst);

            return lookup.TryGet(key, out value);
        }

        /// <summary>
        /// Loads the FST stored at <paramref name="filePath"/> and enumerates all keys
        /// whose Levenshtein distance to <paramref name="key"/> is at most <paramref name="maxEdits"/>.
        /// </summary>
        public static IEnumerable<(string Key, long Value)> LookupFuzzy(string filePath, string key, int maxEdits)
        {
            if (filePath == null) throw new ArgumentNullException(nameof(filePath));
            if (key      == null) throw new ArgumentNullException(nameof(key));

            Fst       fst    = FstPersistence.Load(filePath);
            var       lookup = new FstLookup(fst);

            return lookup.EnumerateFuzzy(key, maxEdits);
        }

        /// <summary>
        /// Loads the FST stored at <paramref name="filePath"/> and enumerates all keys
        /// that end with the given <paramref name="pattern"/> (wildcard: *pattern).
        /// </summary>
        /// <param name="filePath">Path to the FST file written by <see cref="FstBuildApi.BuildAndSave"/>.</param>
        /// <param name="pattern">The pattern to search for (words must end with this).</param>
        /// <returns>All (key, value) pairs where key ends with pattern, in lexicographic order.</returns>
        public static IEnumerable<(string Key, long Value)> LookupEndsWith(string filePath, string pattern)
        {
            if (filePath == null) throw new ArgumentNullException(nameof(filePath));
            if (pattern  == null) throw new ArgumentNullException(nameof(pattern));

            Fst       fst    = FstPersistence.Load(filePath);
            var       lookup = new FstLookup(fst);

            return lookup.EnumerateEndsWith(pattern);
        }

        /// <summary>
        /// Loads the FST stored at <paramref name="filePath"/> and enumerates all keys
        /// that end with the given <paramref name="pattern"/> (wildcard: *pattern).
        /// Uses reverse FST for efficiency.
        /// </summary>
        /// <param name="filePath">Path to the FST file written by <see cref="FstBuildApi.BuildAndSave"/>.</param>
        /// <param name="reverseFilePath">Path to the reverse FST file for efficient suffix matching.</param>
        /// <param name="pattern">The pattern to search for (words must end with this).</param>
        /// <returns>All (key, value) pairs where key ends with pattern, in lexicographic order.</returns>
        public static IEnumerable<(string Key, long Value)> LookupEndsWith(string filePath, string reverseFilePath, string pattern)
        {
            if (filePath        == null) throw new ArgumentNullException(nameof(filePath));
            if (reverseFilePath == null) throw new ArgumentNullException(nameof(reverseFilePath));
            if (pattern         == null) throw new ArgumentNullException(nameof(pattern));

            Fst fst        = FstPersistence.Load(filePath);
            Fst reverseFst = FstPersistence.Load(reverseFilePath);
            var reverseLookup = new FstLookup(reverseFst);
            var lookup = new FstLookup(fst, reverseLookup);

            return lookup.EnumerateEndsWith(pattern);
        }

        /// <summary>
        /// Loads the FST stored at <paramref name="filePath"/> and enumerates all keys
        /// that start with the given <paramref name="pattern"/> (wildcard: pattern*).
        /// </summary>
        /// <param name="filePath">Path to the FST file written by <see cref="FstBuildApi.BuildAndSave"/>.</param>
        /// <param name="pattern">The pattern to search for (words must start with this).</param>
        /// <param name="reverseFilePath">Path to the reverse FST file written by <see cref="FstBuildApi.BuildAndSaveSorted"/>.</param>
        /// <returns>All (key, value) pairs where key starts with pattern, in lexicographic order.</returns>
        public static IEnumerable<(string Key, long Value)> LookupStartsWith(string filePath, string pattern, string reverseFilePath)
        {
            if (filePath        == null) throw new ArgumentNullException(nameof(filePath));
            if (pattern         == null) throw new ArgumentNullException(nameof(pattern));
            if (reverseFilePath == null) throw new ArgumentNullException(nameof(reverseFilePath));

            Fst fst        = FstPersistence.Load(filePath);
            Fst reverseFst = FstPersistence.Load(reverseFilePath);
            var reverseLookup = new FstLookup(reverseFst);
            var lookup = new FstLookup(fst, reverseLookup);

            return lookup.EnumerateStartsWith(pattern);
        }

        /// <summary>
        /// Loads the FST stored at <paramref name="filePath"/> and enumerates all keys
        /// that contain the given <paramref name="pattern"/> (wildcard: *pattern*).
        /// </summary>
        /// <param name="filePath">Path to the FST file written by <see cref="FstBuildApi.BuildAndSave"/>.</param>
        /// <param name="pattern">The substring to search for.</param>
        /// <param name="reverseFilePath">Path to the reverse FST file written by <see cref="FstBuildApi.BuildAndSaveSorted"/>.</param>
        /// <returns>All (key, value) pairs where key contains pattern, in lexicographic order.</returns>
        public static IEnumerable<(string Key, long Value)> LookupContains(string filePath, string pattern, string reverseFilePath)
        {
            if (filePath        == null) throw new ArgumentNullException(nameof(filePath));
            if (pattern         == null) throw new ArgumentNullException(nameof(pattern));
            if (reverseFilePath == null) throw new ArgumentNullException(nameof(reverseFilePath));

            Fst fst        = FstPersistence.Load(filePath);
            Fst reverseFst = FstPersistence.Load(reverseFilePath);
            var reverseLookup = new FstLookup(reverseFst);
            var lookup = new FstLookup(fst, reverseLookup);

            return lookup.EnumerateContains(pattern);
        }
    }
}
