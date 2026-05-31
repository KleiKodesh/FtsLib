using System;
using System.IO;
using System.Data.SQLite;

namespace FstTest
{
    class InspectSqliteProgram
    {
        public static void InspectDatabase()
        {
            string sqliteDir = Path.Combine(AppContext.BaseDirectory, "SqliteIndex");
            var dbFiles = Directory.GetFiles(sqliteDir, "*.db");

            if (dbFiles.Length == 0)
            {
                Console.WriteLine("No SQLite files found");
                return;
            }

            string dbPath = dbFiles[0];
            Console.WriteLine($"Inspecting: {Path.GetFileName(dbPath)}\n");

            var connectionString = $"Data Source={dbPath}";
            using (var connection = new SQLiteConnection(connectionString))
            {
                connection.Open();

                // List tables
                Console.WriteLine("Tables:");
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT name FROM sqlite_master WHERE type='table'";
                    using (var reader = command.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            Console.WriteLine($"  - {reader.GetString(0)}");
                        }
                    }
                }

                // Inspect first table
                Console.WriteLine("\nFirst table schema:");
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT name FROM sqlite_master WHERE type='table' LIMIT 1";
                    var tableName = command.ExecuteScalar() as string;

                    if (tableName != null)
                    {
                        Console.WriteLine($"Table: {tableName}");
                        command.CommandText = $"PRAGMA table_info({tableName})";
                        using (var reader = command.ExecuteReader())
                        {
                            while (reader.Read())
                            {
                                Console.WriteLine($"  Column: {reader.GetString(1)} ({reader.GetString(2)})");
                            }
                        }

                        // Sample data
                        Console.WriteLine($"\nSample data from {tableName}:");
                        command.CommandText = $"SELECT * FROM {tableName} LIMIT 5";
                        using (var reader = command.ExecuteReader())
                        {
                            int colCount = reader.FieldCount;
                            while (reader.Read())
                            {
                                for (int i = 0; i < colCount; i++)
                                {
                                    Console.Write($"  {reader.GetName(i)}: {reader.GetValue(i)}");
                                }
                                Console.WriteLine();
                            }
                        }
                    }
                }
            }
        }
    }
}
