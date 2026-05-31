using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Data.SQLite;
using FstLib;

namespace FstTest
{
    /// <summary>
    /// Benchmarks FST lookup performance against SQLite index performance.
    /// Compares exact match queries, pattern matching, and fuzzy search across
    /// both storage backends using real indexed data.
    /// </summary>
    public class FstVsSqliteBenchmark
    {
        private readonly string _sqliteIndexDir;
        private readonly string _fstIndexDir;
        private readonly List<string> _testQueries;

        public FstVsSqliteBenchmark(string sqliteIndexDir, string fstIndexDir)
        {
            _sqliteIndexDir = sqliteIndexDir ?? throw new ArgumentNullException(nameof(sqliteIndexDir));
            _fstIndexDir = fstIndexDir ?? throw new ArgumentNullException(nameof(fstIndexDir));
            _testQueries = new List<string>();
        }

        /// <summary>
        /// Loads test queries from a SQLite index to ensure we're testing against real data.
        /// </summary>
        public void LoadTestQueriesFromSqlite(string dbPath, int sampleSize = 100)
        {
            if (!File.Exists(dbPath))
                throw new FileNotFoundException($"SQLite database not found: {dbPath}");

            _testQueries.Clear();
            var connectionString = $"Data Source={dbPath}";

            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT DISTINCT term FROM term_index LIMIT ?";
                    command.Parameters.AddWithValue("@limit", sampleSize);

                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            _testQueries.Add(reader.GetString(0));
                        }
                    }
                }
            }

            Console.WriteLine($"Loaded {_testQueries.Count} test queries from SQLite");
        }

        /// <summary>
        /// Benchmarks exact match lookups: FST vs SQLite.
        /// </summary>
        public void BenchmarkExactMatch(string fstPath, string dbPath, int iterations = 1000)
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded. Call LoadTestQueriesFromSqlite first.");

            Console.WriteLine("\n=== EXACT MATCH BENCHMARK ===");
            Console.WriteLine($"Iterations: {iterations}, Test queries: {_testQueries.Count}");

            // Warm up
            _ = FstLookupApi.Lookup(fstPath, _testQueries[0], out _);
            QuerySqliteExact(dbPath, _testQueries[0]);

            // FST benchmark
            var fstStopwatch = Stopwatch.StartNew();
            int fstHits = 0;
            for (int i = 0; i < iterations; i++)
            {
                var query = _testQueries[i % _testQueries.Count];
                if (FstLookupApi.Lookup(fstPath, query, out _))
                    fstHits++;
            }
            fstStopwatch.Stop();

            // SQLite benchmark
            var sqliteStopwatch = Stopwatch.StartNew();
            int sqliteHits = 0;
            for (int i = 0; i < iterations; i++)
            {
                var query = _testQueries[i % _testQueries.Count];
                if (QuerySqliteExact(dbPath, query))
                    sqliteHits++;
            }
            sqliteStopwatch.Stop();

            PrintResults("Exact Match", fstStopwatch, sqliteStopwatch, fstHits, sqliteHits, iterations);
        }

        /// <summary>
        /// Benchmarks prefix pattern matching: FST vs SQLite.
        /// </summary>
        public void BenchmarkPrefixPattern(string fstPath, string reverseFstPath, string dbPath, int iterations = 100)
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded. Call LoadTestQueriesFromSqlite first.");

            Console.WriteLine("\n=== PREFIX PATTERN BENCHMARK (pattern*) ===");
            Console.WriteLine($"Iterations: {iterations}, Test queries: {_testQueries.Count}");

            var patterns = _testQueries
                .Select(q => q.Length > 2 ? q.Substring(0, q.Length / 2) : q)
                .Distinct()
                .Take(10)
                .ToList();

            // Warm up
            _ = FstLookupApi.LookupStartsWith(fstPath, patterns[0], reverseFstPath).Count();
            _ = QuerySqlitePrefix(dbPath, patterns[0]).Count();

            // FST benchmark
            var fstStopwatch = Stopwatch.StartNew();
            int fstResults = 0;
            for (int i = 0; i < iterations; i++)
            {
                var pattern = patterns[i % patterns.Count];
                fstResults += FstLookupApi.LookupStartsWith(fstPath, pattern, reverseFstPath).Count();
            }
            fstStopwatch.Stop();

            // SQLite benchmark
            var sqliteStopwatch = Stopwatch.StartNew();
            int sqliteResults = 0;
            for (int i = 0; i < iterations; i++)
            {
                var pattern = patterns[i % patterns.Count];
                sqliteResults += QuerySqlitePrefix(dbPath, pattern).Count();
            }
            sqliteStopwatch.Stop();

            Console.WriteLine($"FST:    {fstStopwatch.ElapsedMilliseconds}ms ({fstResults} total results)");
            Console.WriteLine($"SQLite: {sqliteStopwatch.ElapsedMilliseconds}ms ({sqliteResults} total results)");
            Console.WriteLine($"FST is {(double)sqliteStopwatch.ElapsedMilliseconds / fstStopwatch.ElapsedMilliseconds:F2}x faster");
        }

        /// <summary>
        /// Benchmarks suffix pattern matching: FST vs SQLite.
        /// </summary>
        public void BenchmarkSuffixPattern(string fstPath, string dbPath, int iterations = 100)
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded. Call LoadTestQueriesFromSqlite first.");

            Console.WriteLine("\n=== SUFFIX PATTERN BENCHMARK (*pattern) ===");
            Console.WriteLine($"Iterations: {iterations}, Test queries: {_testQueries.Count}");

            var patterns = _testQueries
                .Select(q => q.Length > 2 ? q.Substring(q.Length / 2) : q)
                .Distinct()
                .Take(10)
                .ToList();

            // Warm up
            _ = FstLookupApi.LookupEndsWith(fstPath, patterns[0]).Count();
            _ = QuerySqliteSuffix(dbPath, patterns[0]).Count();

            // FST benchmark
            var fstStopwatch = Stopwatch.StartNew();
            int fstResults = 0;
            for (int i = 0; i < iterations; i++)
            {
                var pattern = patterns[i % patterns.Count];
                fstResults += FstLookupApi.LookupEndsWith(fstPath, pattern).Count();
            }
            fstStopwatch.Stop();

            // SQLite benchmark
            var sqliteStopwatch = Stopwatch.StartNew();
            int sqliteResults = 0;
            for (int i = 0; i < iterations; i++)
            {
                var pattern = patterns[i % patterns.Count];
                sqliteResults += QuerySqliteSuffix(dbPath, pattern).Count();
            }
            sqliteStopwatch.Stop();

            Console.WriteLine($"FST:    {fstStopwatch.ElapsedMilliseconds}ms ({fstResults} total results)");
            Console.WriteLine($"SQLite: {sqliteStopwatch.ElapsedMilliseconds}ms ({sqliteResults} total results)");
            Console.WriteLine($"FST is {(double)sqliteStopwatch.ElapsedMilliseconds / fstStopwatch.ElapsedMilliseconds:F2}x faster");
        }

        /// <summary>
        /// Benchmarks fuzzy search: FST vs SQLite (Levenshtein distance).
        /// </summary>
        public void BenchmarkFuzzySearch(string fstPath, string dbPath, int maxEdits = 1, int iterations = 50)
        {
            if (_testQueries.Count == 0)
                throw new InvalidOperationException("No test queries loaded. Call LoadTestQueriesFromSqlite first.");

            Console.WriteLine($"\n=== FUZZY SEARCH BENCHMARK (max edits: {maxEdits}) ===");
            Console.WriteLine($"Iterations: {iterations}, Test queries: {_testQueries.Count}");

            // Warm up
            _ = FstLookupApi.LookupFuzzy(fstPath, _testQueries[0], maxEdits).Count();
            _ = QuerySqliteFuzzy(dbPath, _testQueries[0], maxEdits).Count();

            // FST benchmark
            var fstStopwatch = Stopwatch.StartNew();
            int fstResults = 0;
            for (int i = 0; i < iterations; i++)
            {
                var query = _testQueries[i % _testQueries.Count];
                fstResults += FstLookupApi.LookupFuzzy(fstPath, query, maxEdits).Count();
            }
            fstStopwatch.Stop();

            // SQLite benchmark
            var sqliteStopwatch = Stopwatch.StartNew();
            int sqliteResults = 0;
            for (int i = 0; i < iterations; i++)
            {
                var query = _testQueries[i % _testQueries.Count];
                sqliteResults += QuerySqliteFuzzy(dbPath, query, maxEdits).Count();
            }
            sqliteStopwatch.Stop();

            Console.WriteLine($"FST:    {fstStopwatch.ElapsedMilliseconds}ms ({fstResults} total results)");
            Console.WriteLine($"SQLite: {sqliteStopwatch.ElapsedMilliseconds}ms ({sqliteResults} total results)");
            if (sqliteStopwatch.ElapsedMilliseconds > 0)
                Console.WriteLine($"FST is {(double)sqliteStopwatch.ElapsedMilliseconds / fstStopwatch.ElapsedMilliseconds:F2}x faster");
        }

        // ─────────────────────────────────────────────────────────
        //  SQLite Query Helpers
        // ─────────────────────────────────────────────────────────

        private bool QuerySqliteExact(string dbPath, string word)
        {
            var connectionString = $"Data Source={dbPath}";
            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT COUNT(*) FROM words WHERE word = ?";
                    command.Parameters.AddWithValue("@word", word);
                    var result = command.ExecuteScalar();
                    return result != null && (long)result > 0;
                }
            }
        }

        private IEnumerable<string> QuerySqlitePrefix(string dbPath, string pattern)
        {
            var connectionString = $"Data Source={dbPath}";
            var results = new List<string>();

            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT word FROM words WHERE word LIKE ? LIMIT 1000";
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

        private IEnumerable<string> QuerySqliteSuffix(string dbPath, string pattern)
        {
            var connectionString = $"Data Source={dbPath}";
            var results = new List<string>();

            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT word FROM words WHERE word LIKE ? LIMIT 1000";
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

        private IEnumerable<string> QuerySqliteFuzzy(string dbPath, string word, int maxEdits)
        {
            // SQLite doesn't have built-in Levenshtein distance, so we fetch all words
            // and compute distance in-memory. This is a fair comparison since it shows
            // the cost of fuzzy search without specialized indexing.
            var connectionString = $"Data Source={dbPath}";
            var results = new List<string>();

            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT word FROM words LIMIT 10000";

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

        private int LevenshteinDistance(string s1, string s2)
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

        private void PrintResults(string testName, Stopwatch fstTimer, Stopwatch sqliteTimer, 
            int fstHits, int sqliteHits, int iterations)
        {
            Console.WriteLine($"{testName}:");
            Console.WriteLine($"  FST:    {fstTimer.ElapsedMilliseconds}ms ({fstHits} hits)");
            Console.WriteLine($"  SQLite: {sqliteTimer.ElapsedMilliseconds}ms ({sqliteHits} hits)");
            
            if (sqliteTimer.ElapsedMilliseconds > 0)
            {
                double speedup = (double)sqliteTimer.ElapsedMilliseconds / fstTimer.ElapsedMilliseconds;
                Console.WriteLine($"  FST is {speedup:F2}x faster");
            }

            if (fstHits != sqliteHits)
                Console.WriteLine($"  ⚠ WARNING: Result count mismatch! FST: {fstHits}, SQLite: {sqliteHits}");
        }
    }
}
