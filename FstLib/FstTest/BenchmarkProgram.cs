using System;
using System.IO;
using System.Linq;
using System.Data.SQLite;
using FstLib;
using FstLib.Storage;

namespace FstTest
{
    /// <summary>
    /// Benchmark runner for FST vs SQLite performance comparison.
    /// Can be invoked programmatically or from tests.
    /// </summary>
    public static class BenchmarkRunner
    {
        public static void RunBenchmarks()
        {
            Console.WriteLine("╔════════════════════════════════════════════════════════════╗");
            Console.WriteLine("║         FST vs SQLite Performance Benchmark Suite          ║");
            Console.WriteLine("╚════════════════════════════════════════════════════════════╝\n");

            try
            {
                // Locate SQLite index directory
                string sqliteIndexDir = Path.Combine(AppContext.BaseDirectory, "SqliteIndex");
                if (!Directory.Exists(sqliteIndexDir))
                {
                    Console.WriteLine($"❌ SQLite index directory not found: {sqliteIndexDir}");
                    return;
                }

                // Find first SQLite database
                var dbFiles = Directory.GetFiles(sqliteIndexDir, "*.db");
                if (dbFiles.Length == 0)
                {
                    Console.WriteLine($"❌ No SQLite database files found in {sqliteIndexDir}");
                    return;
                }

                string dbPath = dbFiles[0];
                Console.WriteLine($"📊 Using SQLite database: {Path.GetFileName(dbPath)}\n");

                // Create FST index directory
                string fstIndexDir = Path.Combine(AppContext.BaseDirectory, "FstIndex");
                Directory.CreateDirectory(fstIndexDir);

                // Initialize benchmark
                var benchmark = new FstVsSqliteBenchmark(sqliteIndexDir, fstIndexDir);

                // Load test queries from SQLite
                benchmark.LoadTestQueriesFromSqlite(dbPath, sampleSize: 200);

                // Build FST from SQLite data (if not already built)
                string fstPath = Path.Combine(fstIndexDir, "index.fst");
                string reverseFstPath = Path.Combine(fstIndexDir, "index.reverse.fst");

                if (!File.Exists(fstPath))
                {
                    Console.WriteLine("\n🔨 Building FST index from SQLite data...");
                    BuildFstFromSqlite(dbPath, fstPath, reverseFstPath);
                }
                else
                {
                    Console.WriteLine($"✓ FST index already exists: {fstPath}");
                }

                // Run benchmarks
                Console.WriteLine("\n" + new string('═', 60));
                benchmark.BenchmarkExactMatch(fstPath, dbPath, iterations: 1000);
                benchmark.BenchmarkSuffixPattern(fstPath, dbPath, iterations: 100);
                benchmark.BenchmarkPrefixPattern(fstPath, reverseFstPath, dbPath, iterations: 100);
                benchmark.BenchmarkFuzzySearch(fstPath, dbPath, maxEdits: 1, iterations: 50);
                Console.WriteLine(new string('═', 60));

                Console.WriteLine("\n✅ Benchmark complete!");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"\n❌ Error: {ex.Message}");
                Console.WriteLine($"Stack trace: {ex.StackTrace}");
            }
        }

        public static void BuildFstFromSqlite(string dbPath, string fstPath, string reverseFstPath)
        {
            var connectionString = $"Data Source={dbPath}";
            var entries = new System.Collections.Generic.List<(string, long)>();

            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT word, rowid FROM words ORDER BY word";
                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            entries.Add((reader.GetString(0), reader.GetInt64(1)));
                        }
                    }
                }
            }

            Console.WriteLine($"  Building FST with {entries.Count} entries...");
            FstLib.FstBuildApi.BuildAndSaveSorted(entries, fstPath);
            Console.WriteLine($"  ✓ FST saved to {fstPath}");

            // Build reverse FST for prefix/contains searches
            var reverseEntries = entries
                .Select(e => (new string(e.Item1.Reverse().ToArray()), e.Item2))
                .ToList();

            Console.WriteLine($"  Building reverse FST...");
            FstLib.FstBuildApi.BuildAndSaveSorted(reverseEntries, reverseFstPath);
            Console.WriteLine($"  ✓ Reverse FST saved to {reverseFstPath}");
        }
    }
}
