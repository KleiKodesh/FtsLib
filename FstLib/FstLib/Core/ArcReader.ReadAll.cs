using System.Collections.Generic;
using FstLib.Core;

namespace FstLib.Lookup
{
    // Full-node enumeration: yield every arc in each of the four node formats.
    internal sealed partial class FstLookup
    {
        // ── Variable-length linear scan ───────────────────────────

        private IEnumerable<ArcData> ReadAllLinear(byte[] b, long nodeAddr)
        {
            long pos = nodeAddr - 1;
            while (pos >= 0)
            {
                byte flags    = b[pos--];
                int label     = _labelBytes == 1 ? b[pos--] & 0xFF : ReadLabelRev(b, ref pos);
                long output   = (flags & Fst.FLAG_HAS_OUTPUT)    != 0 ? ReadVLongRev(b, ref pos) : 0;
                long finalOut = (flags & Fst.FLAG_HAS_FINAL_OUT) != 0 ? ReadVLongRev(b, ref pos) : 0;

                bool isTargetNext = (flags & Fst.FLAG_TARGET_NEXT) != 0;
                long targetAddr   = ReadTargetLinear(b, ref pos, flags);

                yield return new ArcData
                {
                    Label = label, Output = output, FinalOutput = finalOut,
                    IsFinal = (flags & Fst.FLAG_FINAL_ARC) != 0,
                    IsLast  = (flags & Fst.FLAG_LAST_ARC)  != 0,
                    IsTargetNext = isTargetNext,
                    TargetAddress = targetAddr,
                };
                if ((flags & Fst.FLAG_LAST_ARC) != 0) break;
            }
        }

        // ── Fixed-length binary-search node (0x20) ────────────────

        private IEnumerable<ArcData> ReadAllFixed(byte[] b, long nodeAddr)
        {
            long pos = nodeAddr - 2;
            int maxTargetB = (int)ReadVLongRev(b, ref pos);
            int maxFinalB  = (int)ReadVLongRev(b, ref pos);
            int maxOutB    = (int)ReadVLongRev(b, ref pos);
            long numArcs   = ReadVLongRev(b, ref pos);

            int bytesPerArc = 1 + _labelBytes + maxOutB + maxFinalB + maxTargetB;
            long arcStart = pos + 1 - numArcs * bytesPerArc;

            for (int i = 0; i < numArcs; i++)
            {
                long arcPos   = arcStart + (numArcs - i) * bytesPerArc - 1;
                byte flags    = b[arcPos];
                long rp       = arcPos - 1;
                int label     = _labelBytes == 1 ? b[rp--] & 0xFF : ReadLabelRev(b, ref rp);
                long output   = ReadFixedBERev(b, ref rp, maxOutB);
                long finalOut = ReadFixedBERev(b, ref rp, maxFinalB);
                long target   = ReadFixedBERev(b, ref rp, maxTargetB);

                yield return new ArcData
                {
                    Label = label, Output = output, FinalOutput = finalOut,
                    IsFinal = (flags & Fst.FLAG_FINAL_ARC) != 0,
                    IsLast  = false,
                    TargetAddress = (flags & Fst.FLAG_STOP_NODE) == 0 ? target : -1,
                };
            }
        }

        // ── Direct-addressing node (0x40) ─────────────────────────

        private IEnumerable<ArcData> ReadAllDirect(byte[] b, long nodeAddr)
        {
            var (numArcs, firstLabel, labelRange, maxOutB, maxFinalB, maxTargetB, arcsStart, bitmapStart)
                = ReadDirectHeader(b, nodeAddr);

            int bytesPerArc = 1 + maxOutB + maxFinalB + maxTargetB;
            int arcIndex = 0;
            for (int bitIdx = 0; bitIdx < labelRange; bitIdx++)
            {
                if ((b[bitmapStart + (bitIdx / 8)] & (1 << (bitIdx & 7))) == 0) continue;

                long arcPos   = arcsStart + (numArcs - 1 - arcIndex) * bytesPerArc + bytesPerArc - 1;
                byte flags    = b[arcPos];
                long rp       = arcPos - 1;
                long output   = ReadFixedBERev(b, ref rp, maxOutB);
                long finalOut = ReadFixedBERev(b, ref rp, maxFinalB);
                long target   = ReadFixedBERev(b, ref rp, maxTargetB);

                yield return new ArcData
                {
                    Label = (int)(firstLabel + bitIdx),
                    Output = output, FinalOutput = finalOut,
                    IsFinal = (flags & Fst.FLAG_FINAL_ARC) != 0,
                    IsLast  = false,
                    TargetAddress = (flags & Fst.FLAG_STOP_NODE) == 0 ? target : -1,
                };
                arcIndex++;
            }
        }

        // ── Continuous-label array node (0x60) ────────────────────

        private IEnumerable<ArcData> ReadAllContinuous(byte[] b, long nodeAddr)
        {
            long pos = nodeAddr - 2;
            int maxTargetB = (int)ReadVLongRev(b, ref pos);
            int maxFinalB  = (int)ReadVLongRev(b, ref pos);
            int maxOutB    = (int)ReadVLongRev(b, ref pos);
            long baseLabel = ReadVLongRev(b, ref pos);
            long numArcs   = ReadVLongRev(b, ref pos);

            int bytesPerArc = 1 + maxOutB + maxFinalB + maxTargetB;
            long arcStart = pos + 1 - numArcs * bytesPerArc;

            for (int i = 0; i < numArcs; i++)
            {
                long arcPos   = arcStart + (numArcs - i) * bytesPerArc - 1;
                byte flags    = b[arcPos];
                long rp       = arcPos - 1;
                long output   = ReadFixedBERev(b, ref rp, maxOutB);
                long finalOut = ReadFixedBERev(b, ref rp, maxFinalB);
                long target   = ReadFixedBERev(b, ref rp, maxTargetB);

                yield return new ArcData
                {
                    Label = (int)(baseLabel + i),
                    Output = output, FinalOutput = finalOut,
                    IsFinal = (flags & Fst.FLAG_FINAL_ARC) != 0,
                    IsLast  = false,
                    TargetAddress = (flags & Fst.FLAG_STOP_NODE) == 0 ? target : -1,
                };
            }
        }

    }
}
