using System.Runtime.CompilerServices;

[assembly: InternalsVisibleTo("FstTest")]

namespace FstLib.Core
{
    /// <summary>
    /// An immutable compiled FST — a byte array plus the root address and a few header fields.
    /// The binary format is a reversed sequence of arc records; see the flag and sentinel
    /// constants below for the wire-format details.
    /// </summary>
    public sealed class Fst
    {
        internal readonly byte[] Bytes;
        internal readonly long RootAddress;
        internal readonly InputType InputType;
        internal readonly byte LabelBytes;
        internal readonly bool HasRootFinal;
        internal readonly long RootFinalOutput;

        public int Size => Bytes.Length;

        internal Fst(byte[] bytes, long rootAddress, InputType inputType = InputType.BYTE1,
            bool hasRootFinal = false, long rootFinalOutput = 0)
        {
            Bytes = bytes;
            RootAddress = rootAddress;
            InputType = inputType;
            LabelBytes = (byte)inputType;
            HasRootFinal = hasRootFinal;
            RootFinalOutput = rootFinalOutput;
        }

        // ── Per-arc flags (match Lucene bit assignments) ──────────
        // BIT_FINAL_ARC            = 1 << 0  → 0x01
        // BIT_LAST_ARC             = 1 << 1  → 0x02
        // BIT_TARGET_NEXT          = 1 << 2  → 0x04
        // BIT_STOP_NODE            = 1 << 3  → 0x08
        // BIT_ARC_HAS_OUTPUT       = 1 << 4  → 0x10
        // BIT_ARC_HAS_FINAL_OUTPUT = 1 << 5  → 0x20
        internal const byte FLAG_FINAL_ARC     = 0x01;
        internal const byte FLAG_LAST_ARC      = 0x02;
        internal const byte FLAG_TARGET_NEXT   = 0x04;
        internal const byte FLAG_STOP_NODE     = 0x08;
        internal const byte FLAG_HAS_OUTPUT    = 0x10;
        internal const byte FLAG_HAS_FINAL_OUT = 0x20;

        // Maximum possible value for a valid arc flags byte:
        // 0x01 | 0x02 | 0x04 | 0x08 | 0x10 | 0x20 = 0x3F
        // Sentinel values are chosen so they cannot collide with valid arc flags:
        //   0x40 has bit 6 set, which no arc flag uses.
        //   0x60 = 0x40 | 0x20 also has bit 6 set.

        // ── Node header sentinels (match Lucene) ───────────────────
        internal const byte NODE_FIXED_LEN   = 0x20; // binary-search fixed-length arcs
        internal const byte NODE_DIRECT_ADDR = 0x40; // direct-addressing with bitmap
        internal const byte NODE_CONTINUOUS  = 0x60; // continuous-label arcs (0x40|0x20)

        // ── Format-selection heuristic thresholds ─────────────────
        internal const int   FIXED_LEN_SHALLOW_MAX_DEPTH  = 3;
        internal const int   FIXED_LEN_SHALLOW_MIN_ARCS   = 5;
        internal const int   FIXED_LEN_DEEP_MIN_ARCS      = 10;
        internal const float DIRECT_ADDR_OVERSIZE_FACTOR  = 1.66f;
    }
}
