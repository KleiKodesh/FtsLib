using FstLib.Core;

namespace FstLib.Lookup
{
    // Point-lookup: find a single arc by label in each of the four node formats.
    internal sealed partial class FstLookup
    {
        // ── Variable-length linear scan ───────────────────────────

        private bool FindArcLinear(byte[] b, long nodeAddr, int label, out ArcData found)
        {
            found = default;
            long pos = nodeAddr - 1;
            while (pos >= 0)
            {
                byte flags   = b[pos--];
                int arcLabel = _labelBytes == 1 ? b[pos--] & 0xFF : ReadLabelRev(b, ref pos);
                long output   = (flags & Fst.FLAG_HAS_OUTPUT)    != 0 ? ReadVLongRev(b, ref pos) : 0;
                long finalOut = (flags & Fst.FLAG_HAS_FINAL_OUT) != 0 ? ReadVLongRev(b, ref pos) : 0;
                long targetAddr = ReadTargetLinear(b, ref pos, flags);

                if (arcLabel == label)
                {
                    found = new ArcData
                    {
                        Label = arcLabel, Output = output, FinalOutput = finalOut,
                        IsFinal = (flags & Fst.FLAG_FINAL_ARC) != 0,
                        IsLast  = (flags & Fst.FLAG_LAST_ARC)  != 0,
                        TargetAddress = targetAddr,
                    };
                    return true;
                }
                if (arcLabel > label) return false;
                if ((flags & Fst.FLAG_LAST_ARC) != 0) break;
            }
            return false;
        }

        // ── Fixed-length binary-search node (0x20) ────────────────

        private bool FindArcFixed(byte[] b, long nodeAddr, int label, out ArcData found)
        {
            found = default;
            long pos = nodeAddr - 2;
            int maxTargetB = (int)ReadVLongRev(b, ref pos);
            int maxFinalB  = (int)ReadVLongRev(b, ref pos);
            int maxOutB    = (int)ReadVLongRev(b, ref pos);
            long numArcs   = ReadVLongRev(b, ref pos);

            int bytesPerArc = 1 + _labelBytes + maxOutB + maxFinalB + maxTargetB;
            long arcStart = pos + 1 - numArcs * bytesPerArc;

            int low = 0, high = (int)numArcs - 1;
            while (low <= high)
            {
                int mid = (low + high) / 2;
                long arcPos  = arcStart + (numArcs - mid) * bytesPerArc - 1;
                byte flags   = b[arcPos];
                long rp      = arcPos - 1;
                int arcLabel = _labelBytes == 1 ? b[rp--] & 0xFF : ReadLabelRev(b, ref rp);

                if (arcLabel == label)
                {
                    long output   = ReadFixedBERev(b, ref rp, maxOutB);
                    long finalOut = ReadFixedBERev(b, ref rp, maxFinalB);
                    long target   = ReadFixedBERev(b, ref rp, maxTargetB);
                    found = new ArcData
                    {
                        Label = arcLabel, Output = output, FinalOutput = finalOut,
                        IsFinal = (flags & Fst.FLAG_FINAL_ARC) != 0,
                        IsLast  = (flags & Fst.FLAG_LAST_ARC)  != 0,
                        TargetAddress = (flags & Fst.FLAG_STOP_NODE) == 0 ? target : -1,
                    };
                    return true;
                }
                if (arcLabel < label) low = mid + 1; else high = mid - 1;
            }
            return false;
        }

        // ── Direct-addressing node (0x40) ─────────────────────────

        private bool FindArcDirect(byte[] b, long nodeAddr, int label, out ArcData found)
        {
            found = default;
            var (numArcs, firstLabel, labelRange, maxOutB, maxFinalB, maxTargetB, arcsStart, bitmapStart)
                = ReadDirectHeader(b, nodeAddr);

            if (label < firstLabel || label >= firstLabel + labelRange) return false;
            int bitIndex = (int)(label - firstLabel);
            if ((b[bitmapStart + (bitIndex / 8)] & (1 << (bitIndex & 7))) == 0) return false;

            int arcIndex = CountBitsBefore(b, bitmapStart, bitIndex);
            int bytesPerArc = 1 + maxOutB + maxFinalB + maxTargetB;
            long arcPos = arcsStart + (numArcs - 1 - arcIndex) * bytesPerArc + bytesPerArc - 1;

            byte flags = b[arcPos];
            long rp = arcPos - 1;
            long output   = maxOutB   > 0 ? ReadFixedBERev(b, ref rp, maxOutB)   : 0;
            long finalOut = maxFinalB > 0 ? ReadFixedBERev(b, ref rp, maxFinalB) : 0;
            long target   = maxTargetB > 0 ? ReadFixedBERev(b, ref rp, maxTargetB) : 0;

            found = new ArcData
            {
                Label = label, Output = output, FinalOutput = finalOut,
                IsFinal = (flags & Fst.FLAG_FINAL_ARC) != 0,
                IsLast  = false,
                TargetAddress = (flags & Fst.FLAG_STOP_NODE) == 0 ? target : -1,
            };
            return true;
        }

        // ── Continuous-label array node (0x60) ────────────────────

        private bool FindArcContinuous(byte[] b, long nodeAddr, int label, out ArcData found)
        {
            found = default;
            long pos = nodeAddr - 2;
            int maxTargetB = (int)ReadVLongRev(b, ref pos);
            int maxFinalB  = (int)ReadVLongRev(b, ref pos);
            int maxOutB    = (int)ReadVLongRev(b, ref pos);
            long baseLabel = ReadVLongRev(b, ref pos);
            long numArcs   = ReadVLongRev(b, ref pos);

            int idx = label - (int)baseLabel;
            if (idx < 0 || idx >= numArcs) return false;

            int bytesPerArc = 1 + maxOutB + maxFinalB + maxTargetB;
            long arcStart = pos + 1 - numArcs * bytesPerArc;
            long arcPos   = arcStart + (numArcs - idx) * bytesPerArc - 1;

            byte flags = b[arcPos];
            long rp = arcPos - 1;
            long output   = maxOutB   > 0 ? ReadFixedBERev(b, ref rp, maxOutB)   : 0;
            long finalOut = maxFinalB > 0 ? ReadFixedBERev(b, ref rp, maxFinalB) : 0;
            long target   = maxTargetB > 0 ? ReadFixedBERev(b, ref rp, maxTargetB) : 0;

            found = new ArcData
            {
                Label = label, Output = output, FinalOutput = finalOut,
                IsFinal = (flags & Fst.FLAG_FINAL_ARC) != 0,
                IsLast  = false,
                TargetAddress = (flags & Fst.FLAG_STOP_NODE) == 0 ? target : -1,
            };
            return true;
        }
    }
}
