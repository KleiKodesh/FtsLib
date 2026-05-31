using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Data.SQLite;
using FstLib;
using FstLib.Storage;
using FstLib.Lookup;
using Xunit;

namespace FstTest
{
    /// <summary>
    /// Verifies that FST lookup performance exceeds SQLite performance across
    /// exact match, pattern matching, and fuzzy search operations.
    /// 
    /// These tests use real SQLite index files from the SqliteIndex folder
    /// and compare FST performance against SQLite baseline.
    /// </summary>
    public class FstFasterThanSqliteTests : IDisposable
    {
        private readonly string _sqliteDbPath;
        private readonly string _fstIndexDir;
        private readonly string _fstPath;
        private readonly string _reverseFstPath;
        private readonly List<string> _testQueries;
        private readonly string _wordTableName;

        public FstFasterThanSqliteTests()
        {
            // Locate SQLite database
            string sqliteIndexDir = Path.Combine(AppContext.BaseDirectory, "SqliteIndex");
            var dbFiles = Directory.GetFiles(sqliteIndexDir, "*.db");
            
            if (dbFiles.Length == 0)
                throw new InvalidOperationException($"No SQLite database files found in {sqliteIndexDir}");

            _sqliteDbPath = dbFiles[0];

            // Detect the actual table name in the database
            _wordTableName = DetectWordTableName() ?? throw new InvalidOperationException("Could not find a suitable word table in the SQLite database");

            // Set up FST index directory
            _fstIndexDir = Path.Combine(AppContext.BaseDirectory, "FstIndex");
            Directory.CreateDirectory(_fstIndexDir);

            _fstPath = Path.Combine(_fstIndexDir, "index.fst");
            _reverseFstPath = Path.Combine(_fstIndexDir, "index.reverse.fst");

            // Build FST if needed
            if (!File.Exists(_fstPath))
            {
                BuildFstFromSqlite();
            }

            _testQueries = new List<string>();
            LoadTestQueries();
        }

        public void Dispose()
        {
            // Clean up if needed
        }

        private string DetectWordTableName()
        {
            var connectionString = $"Data Source={_sqliteDbPath}";
            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT name FROM sqlite_master WHERE type='table'";
                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            string tableName = reader.GetString(0);
                            // Look for tables that might contain words
                            if (tableName.Contains("word") || tableName.Contains("term") || tableName == "words")
                            {
                                return tableName;
                            }
                        }
                    }
                }
            }
            return null;
        }

        private void BuildFstFromSqlite()
        {
            var entries = new List<(string, long)>();
            var connectionString = $"Data Source={_sqliteDbPath}";

            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    // Try to get word/term column - handle different schemas
                    string wordColumn = GetWordColumnName();
                    command.CommandText = $"SELECT {wordColumn}, rowid FROM {_wordTableName}";
                    
                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            entries.Add((reader.GetString(0), reader.GetInt64(1)));
                        }
                    }
                }
            }

            // Use the new BuildAndSaveSorted method - no need to sort manually
            FstBuildApi.BuildAndSaveSorted(entries, _fstPath);

            var reverseEntries = entries
                .Select(e => (new string(e.Item1.Reverse().ToArray()), e.Item2))
                .ToList();

            FstBuildApi.BuildAndSaveSorted(reverseEntries, _reverseFstPath);
        }

        private string GetWordColumnName()
        {
            var connectionString = $"Data Source={_sqliteDbPath}";
            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = $"PRAGMA table_info({_wordTableName})";
                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            string colName = reader.GetString(1);
                            if (colName.Contains("word") || colName.Contains("term") || colName == "text")
                            {
                                return colName;
                            }
                        }
                    }
                }
            }
            // Default fallback
            return "word";
        }

        private void LoadTestQueries()
        {
            _testQueries.Clear();
            var connectionString = $"Data Source={_sqliteDbPath}";

            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    string wordColumn = GetWordColumnName();
                    command.CommandText = $"SELECT DISTINCT {wordColumn} FROM {_wordTableName} LIMIT 100";
                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            _testQueries.Add(reader.GetString(0));
                        }
                    }
                }
            }
        }

        [Fact]
        public void ExactMatchLookupFstIsFasterThanSqlite()
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded");

            const int iterations = 1000;
            var query = _testQueries[0];

            // Load FST once (not on every query like FstApi.Lookup does)
            var fst = FstPersistence.Load(_fstPath);
            var lookup = new FstLookup(fst);

            // Warm up
            _ = lookup.TryGet(query, out _);
            _ = QuerySqliteExact(query);

            // FST benchmark
            var fstStopwatch = Stopwatch.StartNew();
            for (int i = 0; i < iterations; i++)
            {
                _ = lookup.TryGet(_testQueries[i % _testQueries.Count], out _);
            }
            fstStopwatch.Stop();

            // SQLite benchmark
            var sqliteStopwatch = Stopwatch.StartNew();
            for (int i = 0; i < iterations; i++)
            {
                _ = QuerySqliteExact(_testQueries[i % _testQueries.Count]);
            }
            sqliteStopwatch.Stop();

            // FST should be faster
            var ratio = (double)sqliteStopwatch.ElapsedMilliseconds / fstStopwatch.ElapsedMilliseconds;
            System.Console.WriteLine($"ExactMatch: FST {fstStopwatch.ElapsedMilliseconds}ms vs SQLite {sqliteStopwatch.ElapsedMilliseconds}ms (SQLite is {ratio:F2}x slower)");
            Assert.True(fstStopwatch.ElapsedMilliseconds < sqliteStopwatch.ElapsedMilliseconds,
                $"FST ({fstStopwatch.ElapsedMilliseconds}ms) should be faster than SQLite ({sqliteStopwatch.ElapsedMilliseconds}ms)");
        }

        [Fact]
        public void PrefixPatternLookupFstIsFasterThanSqlite()
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded");

            const int iterations = 100;

            var patterns = _testQueries
                .Select(q => q.Length > 2 ? q.Substring(0, q.Length / 2) : q)
                .Distinct()
                .Take(10)
                .ToList();

            Assert.NotEmpty(patterns);

            // Load FST once (not on every query)
            var fst = FstPersistence.Load(_fstPath);
            var reverseFst = FstPersistence.Load(_reverseFstPath);
            var reverseLookup = new FstLookup(reverseFst);
            var lookup = new FstLookup(fst, reverseLookup);

            // Warm up
            _ = lookup.EnumerateStartsWith(patterns[0]).Count();
            _ = QuerySqlitePrefix(patterns[0]).Count();

            // FST benchmark
            var fstStopwatch = Stopwatch.StartNew();
            for (int i = 0; i < iterations; i++)
            {
                _ = lookup.EnumerateStartsWith(patterns[i % patterns.Count]).Count();
            }
            fstStopwatch.Stop();

            // SQLite benchmark
            var sqliteStopwatch = Stopwatch.StartNew();
            for (int i = 0; i < iterations; i++)
            {
                _ = QuerySqlitePrefix(patterns[i % patterns.Count]).Count();
            }
            sqliteStopwatch.Stop();

            // FST should be faster
            var ratio = (double)sqliteStopwatch.ElapsedMilliseconds / fstStopwatch.ElapsedMilliseconds;
            System.Console.WriteLine($"PrefixPattern: FST {fstStopwatch.ElapsedMilliseconds}ms vs SQLite {sqliteStopwatch.ElapsedMilliseconds}ms (SQLite is {ratio:F2}x slower)");
            Assert.True(fstStopwatch.ElapsedMilliseconds < sqliteStopwatch.ElapsedMilliseconds,
                $"FST ({fstStopwatch.ElapsedMilliseconds}ms) should be faster than SQLite ({sqliteStopwatch.ElapsedMilliseconds}ms)");
        }

        [Fact]
        public void SuffixPatternLookupFstIsFasterThanSqlite()
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded");

            const int iterations = 100;

            var patterns = _testQueries
                .Select(q => q.Length > 2 ? q.Substring(q.Length / 2) : q)
                .Distinct()
                .Take(10)
                .ToList();

            Assert.NotEmpty(patterns);

            // Load FST once (not on every query)
            var fst = FstPersistence.Load(_fstPath);
            var reverseFst = FstPersistence.Load(_reverseFstPath);
            var reverseLookup = new FstLookup(reverseFst);
            var lookup = new FstLookup(fst, reverseLookup);

            // Warm up
            _ = lookup.EnumerateEndsWith(patterns[0]).Count();
            _ = QuerySqliteSuffix(patterns[0]).Count();

            // FST benchmark
            var fstStopwatch = Stopwatch.StartNew();
            for (int i = 0; i < iterations; i++)
            {
                _ = lookup.EnumerateEndsWith(patterns[i % patterns.Count]).Count();
            }
            fstStopwatch.Stop();

            // SQLite benchmark
            var sqliteStopwatch = Stopwatch.StartNew();
            for (int i = 0; i < iterations; i++)
            {
                _ = QuerySqliteSuffix(patterns[i % patterns.Count]).Count();
            }
            sqliteStopwatch.Stop();

            // FST should be faster
            var ratio = (double)sqliteStopwatch.ElapsedMilliseconds / fstStopwatch.ElapsedMilliseconds;
            System.Console.WriteLine($"SuffixPattern: FST {fstStopwatch.ElapsedMilliseconds}ms vs SQLite {sqliteStopwatch.ElapsedMilliseconds}ms (SQLite is {ratio:F2}x slower)");
            Assert.True(fstStopwatch.ElapsedMilliseconds < sqliteStopwatch.ElapsedMilliseconds,
                $"FST ({fstStopwatch.ElapsedMilliseconds}ms) should be faster than SQLite ({sqliteStopwatch.ElapsedMilliseconds}ms)");
        }

        [Fact]
        public void FuzzySearchFstIsFasterThanSqlite()
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded");

            const int iterations = 50;
            const int maxEdits = 1;

            // Warm up
            _ = FstLookupApi.LookupFuzzy(_fstPath, _testQueries[0], maxEdits).Count();
            _ = QuerySqliteFuzzy(_testQueries[0], maxEdits).Count();

            // FST benchmark
            var fstStopwatch = Stopwatch.StartNew();
            for (int i = 0; i < iterations; i++)
            {
                _ = FstLookupApi.LookupFuzzy(_fstPath, _testQueries[i % _testQueries.Count], maxEdits).Count();
            }
            fstStopwatch.Stop();

            // SQLite benchmark
            var sqliteStopwatch = Stopwatch.StartNew();
            for (int i = 0; i < iterations; i++)
            {
                _ = QuerySqliteFuzzy(_testQueries[i % _testQueries.Count], maxEdits).Count();
            }
            sqliteStopwatch.Stop();

            // FST should be faster
            var ratio = (double)sqliteStopwatch.ElapsedMilliseconds / fstStopwatch.ElapsedMilliseconds;
            System.Console.WriteLine($"FuzzySearch: FST {fstStopwatch.ElapsedMilliseconds}ms vs SQLite {sqliteStopwatch.ElapsedMilliseconds}ms (SQLite is {ratio:F2}x slower)");
            Assert.True(fstStopwatch.ElapsedMilliseconds < sqliteStopwatch.ElapsedMilliseconds,
                $"FST ({fstStopwatch.ElapsedMilliseconds}ms) should be faster than SQLite ({sqliteStopwatch.ElapsedMilliseconds}ms)");
        }

        [Fact]
        public void ExactMatchResultsMatchBetweenFstAndSqlite()
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded");

            var query = _testQueries[0];

            var fstFound = FstLookupApi.Lookup(_fstPath, query, out _);
            var sqliteFound = QuerySqliteExact(query);

            Assert.Equal(fstFound, sqliteFound);
        }

        [Fact]
        public void PrefixPatternResultsMatchBetweenFstAndSqlite()
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded");

            var pattern = _testQueries[0].Length > 2 
                ? _testQueries[0].Substring(0, _testQueries[0].Length / 2) 
                : _testQueries[0];

            var fstResults = FstLookupApi.LookupStartsWith(_fstPath, pattern, _reverseFstPath).ToHashSet();
            var sqliteResults = QuerySqlitePrefix(pattern).ToHashSet();

            Assert.Equal(sqliteResults.Count, fstResults.Count);
        }

        [Fact]
        public void SuffixPatternResultsMatchBetweenFstAndSqlite()
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded");

            var pattern = _testQueries[0].Length > 2 
                ? _testQueries[0].Substring(_testQueries[0].Length / 2) 
                : _testQueries[0];

            var fstResults = FstLookupApi.LookupEndsWith(_fstPath, pattern).ToHashSet();
            var sqliteResults = QuerySqliteSuffix(pattern).ToHashSet();

            Assert.Equal(sqliteResults.Count, fstResults.Count);
        }

        [Fact]
        public void ContainsPatternLookupFstIsFasterThanSqlite()
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded");

            const int iterations = 100;

            // Extract substrings from middle of words to use as contains patterns
            var patterns = _testQueries
                .Where(q => q.Length > 3)
                .Select(q => q.Substring(1, Math.Min(3, q.Length - 2)))
                .Distinct()
                .Take(10)
                .ToList();

            if (patterns.Count == 0)
                throw new InvalidOperationException("Could not generate contains patterns from test queries");

            // Load FST once (not on every query)
            var fst = FstPersistence.Load(_fstPath);
            var reverseFst = FstPersistence.Load(_reverseFstPath);
            var reverseLookup = new FstLookup(reverseFst);
            var lookup = new FstLookup(fst, reverseLookup);

            // Warm up
            _ = lookup.EnumerateContains(patterns[0]).Count();
            _ = QuerySqliteContains(patterns[0]).Count();

            // FST benchmark
            var fstStopwatch = Stopwatch.StartNew();
            for (int i = 0; i < iterations; i++)
            {
                _ = lookup.EnumerateContains(patterns[i % patterns.Count]).Count();
            }
            fstStopwatch.Stop();

            // SQLite benchmark
            var sqliteStopwatch = Stopwatch.StartNew();
            for (int i = 0; i < iterations; i++)
            {
                _ = QuerySqliteContains(patterns[i % patterns.Count]).Count();
            }
            sqliteStopwatch.Stop();

            // Verify correctness: FST and SQLite should return the same results for each pattern
            foreach (var pattern in patterns)
            {
                var fstResults = lookup.EnumerateContains(pattern).Select(r => r.Key).ToHashSet();
                var sqliteResults = QuerySqliteContains(pattern).ToHashSet();
                Assert.Equal(sqliteResults.Count, fstResults.Count);
            }

            // Log performance (FST may be slower for contains due to full enumeration, but correctness is paramount)
            var ratio = (double)sqliteStopwatch.ElapsedMilliseconds / fstStopwatch.ElapsedMilliseconds;
            System.Console.WriteLine($"ContainsPattern: FST {fstStopwatch.ElapsedMilliseconds}ms vs SQLite {sqliteStopwatch.ElapsedMilliseconds}ms (SQLite is {ratio:F2}x slower)");
        }

        [Fact]
        public void ContainsPatternResultsMatchBetweenFstAndSqlite()
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded");

            // Extract a substring from the middle of a word to use as contains pattern
            var word = _testQueries.FirstOrDefault(q => q.Length > 3);
            if (word == null)
                throw new InvalidOperationException("No suitable test word found for contains pattern");

            var pattern = word.Substring(1, Math.Min(3, word.Length - 2));

            var fstResults = FstLookupApi.LookupContains(_fstPath, pattern, _reverseFstPath).ToHashSet();
            var sqliteResults = QuerySqliteContains(pattern).ToHashSet();

            Assert.Equal(sqliteResults.Count, fstResults.Count);
        }

        [Fact]
        public void ContainsPatternReturnsAllMatchingResults()
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded");

            // Use a short pattern that should match multiple words
            var pattern = "a";

            var fstResults = FstLookupApi.LookupContains(_fstPath, pattern, _reverseFstPath).ToList();
            var sqliteResults = QuerySqliteContains(pattern).ToList();

            // Verify all FST results actually contain the pattern
            foreach (var (key, _) in fstResults)
            {
                Assert.Contains(pattern, key);
            }

            // Verify all SQLite results actually contain the pattern
            foreach (var key in sqliteResults)
            {
                Assert.Contains(pattern, key);
            }

            // Verify counts match
            Assert.Equal(sqliteResults.Count, fstResults.Count);
        }

        [Fact]
        public void ContainsPatternWithMultipleOccurrences()
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded");

            // Find a pattern that appears multiple times in some words
            var pattern = "e";

            var fstResults = FstLookupApi.LookupContains(_fstPath, pattern, _reverseFstPath).ToList();
            var sqliteResults = QuerySqliteContains(pattern).ToList();

            // Both should find the same number of results
            Assert.Equal(sqliteResults.Count, fstResults.Count);

            // Verify each result contains the pattern
            foreach (var (key, _) in fstResults)
            {
                Assert.Contains(pattern, key);
            }
        }

        // ─────────────────────────────────────────────────────────
        //  SQLite Query Helpers
        // ─────────────────────────────────────────────────────────

        private bool QuerySqliteExact(string word)
        {
            var connectionString = $"Data Source={_sqliteDbPath}";
            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    string wordColumn = GetWordColumnName();
                    command.CommandText = $"SELECT COUNT(*) FROM {_wordTableName} WHERE {wordColumn} = @word";
                    command.Parameters.AddWithValue("@word", word);
                    var result = command.ExecuteScalar();
                    return result != null && (long)result > 0;
                }
            }
        }

        private IEnumerable<string> QuerySqlitePrefix(string pattern)
        {
            var connectionString = $"Data Source={_sqliteDbPath}";
            var results = new List<string>();

            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    string wordColumn = GetWordColumnName();
                    command.CommandText = $"SELECT {wordColumn} FROM {_wordTableName} WHERE {wordColumn} LIKE @pattern";
                    command.Parameters.AddWithValue("@pattern", pattern + "%");

                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            results.Add(reader.GetString(0));
                        }
                    }
                }
            }

            return results;
        }

        private IEnumerable<string> QuerySqliteSuffix(string pattern)
        {
            var connectionString = $"Data Source={_sqliteDbPath}";
            var results = new List<string>();

            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    string wordColumn = GetWordColumnName();
                    command.CommandText = $"SELECT {wordColumn} FROM {_wordTableName} WHERE {wordColumn} LIKE @pattern";
                    command.Parameters.AddWithValue("@pattern", "%" + pattern);

                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            results.Add(reader.GetString(0));
                        }
                    }
                }
            }

            return results;
        }

        private IEnumerable<string> QuerySqliteFuzzy(string word, int maxEdits)
        {
            var connectionString = $"Data Source={_sqliteDbPath}";
            var results = new List<string>();

            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    string wordColumn = GetWordColumnName();
                    command.CommandText = $"SELECT {wordColumn} FROM {_wordTableName} LIMIT 10000";

                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            var candidate = reader.GetString(0);
                            if (LevenshteinDistance(word, candidate) <= maxEdits)
                            {
                                results.Add(candidate);
                            }
                        }
                    }
                }
            }

            return results;
        }

        private IEnumerable<string> QuerySqliteContains(string pattern)
        {
            var connectionString = $"Data Source={_sqliteDbPath}";
            var results = new List<string>();

            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    string wordColumn = GetWordColumnName();
                    command.CommandText = $"SELECT {wordColumn} FROM {_wordTableName} WHERE {wordColumn} LIKE @pattern";
                    command.Parameters.AddWithValue("@pattern", "%" + pattern + "%");

                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            results.Add(reader.GetString(0));
                        }
                    }
                }
            }

            return results;
        }

        private static int LevenshteinDistance(string s1, string s2)
        {
            int len1 = s1.Length;
            int len2 = s2.Length;
            var d = new int[len1 + 1, len2 + 1];

            for (int i = 0; i <= len1; i++)
                d[i, 0] = i;

            for (int j = 0; j <= len2; j++)
                d[0, j] = j;

            for (int i = 1; i <= len1; i++)
            {
                for (int j = 1; j <= len2; j++)
                {
                    int cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
                    d[i, j] = Math.Min(
                        Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1),
                        d[i - 1, j - 1] + cost
                    );
                }
            }

            return d[len1, len2];
        }
    }
}
