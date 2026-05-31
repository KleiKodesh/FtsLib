using System;
using System.IO;
using FstLib.Core;

namespace FstLib.Storage
{
    /// <summary>
    /// Serializes and deserializes an <see cref="Fst"/> to/from a binary file.
    ///
    /// File format (little-endian):
    ///   [4 bytes]  magic   = 0x46535400  ("FST\0")
    ///   [4 bytes]  version = 2
    ///   [8 bytes]  rootAddress (Int64)
    ///   [8 bytes]  byteLength  (Int64)
    ///   [1 byte]   inputType (0=BYTE1, 1=BYTE2, 2=BYTE4)
    ///   [N bytes]  raw FST bytes
    /// </summary>
    internal static class FstPersistence
    {
        private static readonly byte[] Magic   = { 0x46, 0x53, 0x54, 0x00 }; // "FST\0"
        private const int              Version = 2;

        /// <summary>Write <paramref name="fst"/> to <paramref name="filePath"/>.</summary>
        internal static void Save(Fst fst, string filePath)
        {
            if (fst      == null) throw new ArgumentNullException(nameof(fst));
            if (filePath == null) throw new ArgumentNullException(nameof(filePath));

            string dir = Path.GetDirectoryName(filePath);
            if (!string.IsNullOrEmpty(dir))
                Directory.CreateDirectory(dir);

            using var fs = new FileStream(filePath, FileMode.Create, FileAccess.Write, FileShare.None);
            using var bw = new BinaryWriter(fs);

            bw.Write(Magic);
            bw.Write(Version);
            bw.Write(fst.RootAddress);
            bw.Write((long)fst.Bytes.Length);
            bw.Write((byte)fst.InputType);
            bw.Write(fst.Bytes);
        }

        /// <summary>Load an <see cref="Fst"/> previously saved with <see cref="Save"/>.</summary>
        internal static Fst Load(string filePath)
        {
            if (filePath == null) throw new ArgumentNullException(nameof(filePath));
            if (!File.Exists(filePath))
                throw new FileNotFoundException($"FST file not found: {filePath}", filePath);

            using var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read);
            using var br = new BinaryReader(fs);

            byte[] magic = br.ReadBytes(4);
            for (int i = 0; i < 4; i++)
                if (magic[i] != Magic[i])
                    throw new InvalidDataException("File does not appear to be a saved FST (bad magic bytes).");

            int version = br.ReadInt32();
            if (version > Version || version < 2)
                throw new InvalidDataException($"Unsupported FST file version {version}. Expected 2.");

            long rootAddress = br.ReadInt64();
            long byteLength = br.ReadInt64();
            if (byteLength > int.MaxValue)
                throw new InvalidDataException($"FST byte length {byteLength} exceeds maximum supported size ({int.MaxValue}).");

            byte inputTypeVal = br.ReadByte();
            if (inputTypeVal != 1 && inputTypeVal != 2 && inputTypeVal != 4)
                throw new InvalidDataException($"Unknown input type {inputTypeVal}.");
            var inputType = (InputType)inputTypeVal;

            byte[] bytes = br.ReadBytes((int)byteLength);

            return new Fst(bytes, rootAddress, inputType, false, 0);
        }
    }
}

