using System.IO;

namespace FtsLib.Indexing
{
    /// <summary>Location of one term's posting data within a segment.</summary>
    internal sealed class SegmentChunk
    {
        public readonly SegmentHandle Seg;
        /// <summary>Byte offset of the skip table in the .dat file (0 when no skip table).</summary>
        public readonly long SkipOffset;
        /// <summary>Number of skip entries (triplets). 0 means no skip table.</summary>
        public readonly int  SkipCount;
        /// <summary>Byte offset of the posting data in the .dat file.</summary>
        public readonly long Offset;
        public readonly int  Length;
        public readonly int  Count;

        public SegmentChunk(SegmentHandle seg, long skipOffset, int skipCount,
                            long offset, int length, int count)
        {
            Seg        = seg;
            SkipOffset = skipOffset;
            SkipCount  = skipCount;
            Offset     = offset;
            Length     = length;
            Count      = count;
        }
    }

    /// <summary>Holds open resources for one segment pair (.dat + .db).</summary>
    internal sealed class SegmentHandle : System.IDisposable
    {
        public readonly string         DatPath;
        public readonly System.Data.SQLite.SQLiteConnection Conn;
        public readonly System.Data.SQLite.SQLiteCommand    Lookup;
        /// <summary>
        /// Prepared statement for trigram lookup: returns all terms that contain
        /// a given trigram. Used by FuzzyExpander and HebrewWildcardExpander instead
        /// of a full-table LIKE scan.
        /// Null when the segment was built before the trigram_index table existed
        /// (old index format) — callers fall back to LIKE in that case.
        /// </summary>
        public readonly System.Data.SQLite.SQLiteCommand    TrigramLookup;
        public readonly FileStream DataStream;
        /// <summary>True when this segment's .db has a trigram_index table.</summary>
        public readonly bool HasTrigramIndex;

        public SegmentHandle(string datPath, string dbPath)
        {
            DatPath    = datPath;
            DataStream = new FileStream(datPath, FileMode.Open, FileAccess.Read,
                                        FileShare.Read, bufferSize: 64 * 1024);
            try
            {
                Conn = new System.Data.SQLite.SQLiteConnection(
                    $"Data Source={dbPath};Version=3;Read Only=True;");
                Conn.Open();
                Lookup = Conn.CreateCommand();
                Lookup.CommandText =
                    "SELECT skip_offset, skip_count, offset, length, count FROM term_index WHERE term = @t";
                Lookup.Parameters.Add("@t", System.Data.DbType.String);

                // Detect whether this segment has the trigram_index table.
                using (var chk = Conn.CreateCommand())
                {
                    chk.CommandText =
                        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='trigram_index'";
                    HasTrigramIndex = (long)chk.ExecuteScalar() > 0;
                }

                if (HasTrigramIndex)
                {
                    TrigramLookup = Conn.CreateCommand();
                    TrigramLookup.CommandText =
                        "SELECT DISTINCT term FROM trigram_index WHERE trigram = @g";
                    TrigramLookup.Parameters.Add("@g", System.Data.DbType.String);
                }
            }
            catch
            {
                DataStream.Dispose();
                throw;
            }
        }

        public void Dispose()
        {
            TrigramLookup?.Dispose();
            Lookup?.Dispose();
            Conn?.Dispose();
            DataStream?.Dispose();
        }
    }
}
