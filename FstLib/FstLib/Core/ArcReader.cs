using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using FstLib.Core;

namespace FstLib.Lookup
{
    // Low-level binary arc I/O — shared types, dispatch, and primitive readers.
    // Point-lookup (FindArc*) and enumeration (ReadAll*) are in separate partial files:
    //   ArcReader.cs            — this file: ArcData, dispatch, primitives
    //   ArcReader.FindArc.cs    — FindArc* methods (point lookup per node format)
    //   ArcReader.ReadAll.cs    — ReadAll* methods (full-node enumeration)
    internal sealed partial class FstLookup
    {
        // ── Arc data ──────────────────────────────────────────────

        internal struct ArcData
        {
            public int Label;
            public long Output;
            public long FinalOutput;
            public bool IsFinal;
            public bool IsLast;
            public bool IsTargetNext;
            public long TargetAddress;
        }

        // ── Dispatch ──────────────────────────────────────────────

        private bool FindArc(long nodeAddr, int label, out ArcData found)
        {
            byte[] b = _fst.Bytes;
            if (nodeAddr < 1 || nodeAddr > b.Length) { found = default; return false; }

            return b[nodeAddr - 1] switch
            {
                Fst.NODE_FIXED_LEN   => FindArcFixed(b, nodeAddr, label, out found),
                Fst.NODE_DIRECT_ADDR => FindArcDirect(b, nodeAddr, label, out found),
                Fst.NODE_CONTINUOUS  => FindArcContinuous(b, nodeAddr, label, out found),
                _                    => FindArcLinear(b, nodeAddr, label, out found),
            };
        }

        private IEnumerable<ArcData> ReadAllArcs(long nodeAddr)
        {
            byte[] b = _fst.Bytes;
            return b[nodeAddr - 1] switch
            {
                Fst.NODE_FIXED_LEN   => ReadAllFixed(b, nodeAddr),
                Fst.NODE_DIRECT_ADDR => ReadAllDirect(b, nodeAddr),
                Fst.NODE_CONTINUOUS  => ReadAllContinuous(b, nodeAddr),
                _                    => ReadAllLinear(b, nodeAddr),
            };
        }

        /// <summary>
        /// Internal: exposes arc enumeration to <see cref="FstDotExporter"/> for DOT output.
        /// </summary>
        internal IEnumerable<ArcData> ReadAllArcsPublic(long nodeAddr) => ReadAllArcs(nodeAddr);

        // ── Primitive readers (reversed byte order) ───────────────

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private int ReadLabelRev(byte[] b, ref long pos)
        {
            if (_labelBytes == 2)
            {
                int b0 = b[pos--] & 0xFF;
                int b1 = b[pos--] & 0xFF;
                return b0 | (b1 << 8);
            }
            int c0 = b[pos--] & 0xFF; int c1 = b[pos--] & 0xFF;
            int c2 = b[pos--] & 0xFF; int c3 = b[pos--] & 0xFF;
            return c0 | (c1 << 8) | (c2 << 16) | (c3 << 24);
        }

        private static long ReadFixedBERev(byte[] b, ref long pos, int byteCount)
        {
            long val = 0;
            for (int i = 0; i < byteCount; i++) val |= (long)b[pos--] << (8 * i);
            return val;
        }

        private static long ReadVLongRev(byte[] b, ref long pos)
        {
            long result = 0; int shift = 0;
            while (true)
            {
                byte byt = b[pos--];
                result |= (long)(byt & 0x7F) << shift;
                if ((byt & 0x80) == 0) break;
                shift += 7;
            }
            return result;
        }

        private static long ReadTargetLinear(byte[] b, ref long pos, byte flags)
        {
            if ((flags & Fst.FLAG_STOP_NODE)   != 0) return -1;
            if ((flags & Fst.FLAG_TARGET_NEXT) != 0) return pos + 1;
            return ReadVLongRev(b, ref pos);
        }

        // ── Direct-address node header ────────────────────────────
        // Shared by FindArcDirect (FindArc.cs) and ReadAllDirect (ReadAll.cs).

        private (int numArcs, long firstLabel, int labelRange,
                 int maxOutB, int maxFinalB, int maxTargetB,
                 long arcsStart, long bitmapStart)
            ReadDirectHeader(byte[] b, long nodeAddr)
        {
            long pos = nodeAddr - 2;
            int maxTargetB  = (int)ReadVLongRev(b, ref pos);
            int maxFinalB   = (int)ReadVLongRev(b, ref pos);
            int maxOutB     = (int)ReadVLongRev(b, ref pos);
            long firstLabel = ReadVLongRev(b, ref pos);
            long labelRange = ReadVLongRev(b, ref pos);
            long numArcs    = ReadVLongRev(b, ref pos);

            int bytesPerArc  = 1 + maxOutB + maxFinalB + maxTargetB;
            int bitmapBytes  = (int)((labelRange + 7) / 8);
            long headerStart = pos + 1;
            long arcsStart   = headerStart - numArcs * bytesPerArc;
            long bitmapStart = arcsStart - bitmapBytes;

            return ((int)numArcs, firstLabel, (int)labelRange,
                    maxOutB, maxFinalB, maxTargetB, arcsStart, bitmapStart);
        }

        /// <summary>Counts the number of set bits in the bitmap before <paramref name="bitIndex"/>.</summary>
        private static int CountBitsBefore(byte[] b, long start, int bitIndex)
        {
            int count = 0;
            int fullBytes = bitIndex / 8;
            for (int i = 0; i < fullBytes; i++) count += PopCount(b[start + i]);
            byte partial = b[start + fullBytes];
            int remaining = bitIndex & 7;
            for (int i = 0; i < remaining; i++)
                if ((partial & (1 << i)) != 0) count++;
            return count;
        }

        /// <summary>
        /// Counts the number of set bits in a byte.
        /// Uses System.Numerics.BitOperations.PopCount on .NET 5+, falls back to manual implementation on .NET Framework.
        /// </summary>
        private static int PopCount(byte b)
        {
#if NET5_0_OR_GREATER
            return System.Numerics.BitOperations.PopCount(b);
#else
            // Fallback for .NET Framework: Brian Kernighan's algorithm
            int v = b;
            int count = 0;
            while (v != 0)
            {
                v &= v - 1;
                count++;
            }
            return count;
#endif
        }
    }
}
