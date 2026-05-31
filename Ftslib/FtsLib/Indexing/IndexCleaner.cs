using System;
using System.IO;

namespace FtsLib.Indexing
{
    /// <summary>
    /// Utility for cleaning up legacy FtsLib index directories.
    /// Used during migration from FtsLib to SearchEngine project library.
    /// </summary>
    public static class IndexCleaner
    {
        /// <summary>
        /// Deletes the legacy FtsLib index directory if it exists.
        /// This should be called once during application startup or migration.
        /// </summary>
        /// <param name="indexPath">Optional custom index path. If null, uses default fts-index directory.</param>
        /// <returns>True if directory was deleted or didn't exist; false if deletion failed.</returns>
        public static bool DeleteLegacyIndex(string indexPath = null)
        {
            try
            {
                string pathToDelete = !string.IsNullOrEmpty(indexPath) ? indexPath :
                    Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "fts-index");

                if (Directory.Exists(pathToDelete))
                {
                    Directory.Delete(pathToDelete, recursive: true);
                    return true;
                }

                return true; // Directory didn't exist, so "cleanup" succeeded
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Failed to delete legacy index directory: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Safely attempts to delete the legacy index directory, logging any errors.
        /// Non-throwing variant for use in application startup routines.
        /// </summary>
        /// <param name="indexPath">Optional custom index path. If null, uses default fts-index directory.</param>
        public static void TryDeleteLegacyIndex(string indexPath = null)
        {
            DeleteLegacyIndex(indexPath);
        }
    }
}
