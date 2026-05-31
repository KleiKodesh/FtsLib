using System;
using System.Collections.Generic;
using FstLib.Building;
using FstLib.Core;
using FstLib.Storage;

namespace FstLib
{
    /// <summary>
    /// API for building and persisting FST indexes.
    ///
    /// Example
    /// ───────
    ///   var entries = new (string key, long value)[]
    ///   {
    ///       ("mop",  0), ("moth", 1), ("pop", 2),
    ///       ("star", 3), ("stop", 4), ("top", 5),
    ///   };
    ///   FstBuildApi.BuildAndSave(entries, "index.fst");
    /// </summary>
    public static class FstBuildApi
    {
        /// <summary>
        /// Builds an FST from <paramref name="entries"/> and saves it to <paramref name="filePath"/>.
        ///
        /// <para><b>Important:</b> entries must be supplied in strictly ascending
        /// lexicographic (dictionary) order. An <see cref="ArgumentException"/> is
        /// thrown if this constraint is violated.</para>
        /// </summary>
        /// <param name="entries">
        ///   Sequence of (key, value) pairs in sorted order.
        ///   Each key must be unique and UTF-8 encodable.
        /// </param>
        /// <param name="filePath">
        ///   Destination path for the compiled FST file (e.g. "index.fst").
        ///   Parent directories are created automatically if they do not exist.
        /// </param>
        /// <param name="inputType">Label type (BYTE1/BYTE2/BYTE4). Default BYTE1.</param>
        /// <param name="suffixRamLimitMb">Suffix dedup cache RAM limit in MB. Default 32.</param>
        /// <returns>The number of entries indexed.</returns>
        public static int BuildAndSave(IEnumerable<(string Key, long Value)> entries, string filePath,
            InputType inputType = InputType.BYTE1, int suffixRamLimitMb = 32)
        {
            if (entries  == null) throw new ArgumentNullException(nameof(entries));
            if (filePath == null) throw new ArgumentNullException(nameof(filePath));

            var builder = new FstBuilder(inputType, suffixRamLimitMb);
            int count   = 0;

            foreach (var (key, value) in entries)
            {
                builder.Add(key, value);
                count++;
            }

            Fst fst = builder.Finish();
            FstPersistence.Save(fst, filePath);

            return count;
        }

        /// <summary>
        /// Builds an FST from <paramref name="entries"/>, automatically sorting them,
        /// and saves it to <paramref name="filePath"/>.
        ///
        /// <para>This overload handles unsorted input by sorting entries before building.
        /// Use this when your data source doesn't guarantee lexicographic order.</para>
        /// </summary>
        /// <param name="entries">
        ///   Sequence of (key, value) pairs in any order.
        ///   Each key must be unique and UTF-8 encodable.
        /// </param>
        /// <param name="filePath">
        ///   Destination path for the compiled FST file (e.g. "index.fst").
        ///   Parent directories are created automatically if they do not exist.
        /// </param>
        /// <param name="inputType">Label type (BYTE1/BYTE2/BYTE4). Default BYTE1.</param>
        /// <param name="suffixRamLimitMb">Suffix dedup cache RAM limit in MB. Default 32.</param>
        /// <returns>The number of entries indexed.</returns>
        public static int BuildAndSaveSorted(IEnumerable<(string Key, long Value)> entries, string filePath,
            InputType inputType = InputType.BYTE1, int suffixRamLimitMb = 32)
        {
            if (entries  == null) throw new ArgumentNullException(nameof(entries));
            if (filePath == null) throw new ArgumentNullException(nameof(filePath));

            // Sort entries by key before building
            var sortedEntries = new List<(string Key, long Value)>(entries);
            sortedEntries.Sort((a, b) => string.Compare(a.Key, b.Key, StringComparison.Ordinal));

            return BuildAndSave(sortedEntries, filePath, inputType, suffixRamLimitMb);
        }
    }
}
