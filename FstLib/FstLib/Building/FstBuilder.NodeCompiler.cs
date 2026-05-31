using System;
using System.Collections.Generic;
using FstLib.Building;
using FstLib.Core;

namespace FstLib.Building
{
    // Serialises UncompiledNodes into the four binary arc formats:
    //   variable-length (linear scan)  — default
    //   fixed-length (binary search)   — NODE_FIXED_LEN  0x20
    //   direct-addressing with bitmap  — NODE_DIRECT_ADDR 0x40
    //   continuous-label array         — NODE_CONTINUOUS  0x60
    //
    // Byte-encoding primitives (VLong, WriteFixed, WriteLabel, etc.) live in
    // FstBuilder.Encoding.cs to keep this file focused on format selection and layout.
    internal sealed partial class FstBuilder
    {
        // ── Format selection ──────────────────────────────────────

        private long CompileNode(UncompiledNode node, int depth)
        {
            if (node.Arcs.Count == 0) return -1L;

            int numArcs = node.Arcs.Count;
            long nodeAddr = _bytes.Position;
            bool lastArcCanTargetNext = node.Arcs[numArcs - 1].Target >= 0
                                     && node.Arcs[numArcs - 1].Target == nodeAddr;

            if (numArcs >= 2 && AreLabelsConsecutive(node))
                return CompileNodeContinuous(node, lastArcCanTargetNext, nodeAddr);

            int labelRange = node.Arcs[numArcs - 1].Label - node.Arcs[0].Label + 1;
            if (ShouldUseDirectAddressing(numArcs, labelRange))
                return CompileNodeDirect(node, lastArcCanTargetNext, nodeAddr, labelRange);

            if (ShouldUseFixedLength(depth, numArcs))
                return CompileNodeFixed(node, lastArcCanTargetNext, nodeAddr);

            return CompileNodeLinear(node, lastArcCanTargetNext, nodeAddr);
        }

        private bool ShouldUseFixedLength(int depth, int numArcs)
            => depth <= Fst.FIXED_LEN_SHALLOW_MAX_DEPTH
                ? numArcs >= Fst.FIXED_LEN_SHALLOW_MIN_ARCS
                : numArcs >= Fst.FIXED_LEN_DEEP_MIN_ARCS;

        private bool ShouldUseDirectAddressing(int numArcs, int labelRange)
            => numArcs >= 4 && (float)labelRange / numArcs < Fst.DIRECT_ADDR_OVERSIZE_FACTOR;

        private static bool AreLabelsConsecutive(UncompiledNode node)
        {
            var arcs = node.Arcs;
            int label = arcs[0].Label;
            for (int i = 1; i < arcs.Count; i++)
                if (arcs[i].Label != ++label) return false;
            return true;
        }

        // ── Variable-length (linear scan) ─────────────────────────

        private long CompileNodeLinear(UncompiledNode node, bool lastArcCanTargetNext, long nodeAddr)
        {
            int numArcs = node.Arcs.Count;
            var fwd = new List<byte>(numArcs * 12);

            for (int i = 0; i < numArcs; i++)
            {
                MutableArc arc = node.Arcs[i];
                bool isStop = arc.Target < 0;
                bool canTargetNext = i == numArcs - 1 && !isStop && lastArcCanTargetNext;

                byte flags = BuildFlags(arc, i == numArcs - 1, isStop, canTargetNext);
                fwd.Add(flags);
                WriteLabel(fwd, arc.Label);
                if (arc.Output != 0) WriteVLong(fwd, arc.Output);
                if (arc.FinalOutput != 0) WriteVLong(fwd, arc.FinalOutput);
                if (!isStop && !canTargetNext) WriteVLong(fwd, arc.Target);
            }

            int len = fwd.Count;
            byte[] rev = new byte[len];
            for (int i = 0; i < len; i++) rev[i] = fwd[len - 1 - i];

            if (!lastArcCanTargetNext)
            {
                long hash = NodeHash.ComputeHash(rev, len);
                long existing = _nodeHash.Find(hash, rev, len, _bytes);
                if (existing >= 0) return existing;
                _nodeHash.Add(hash, nodeAddr + len);
            }

            _bytes.WriteBytes(rev);
            return nodeAddr + len;
        }

        // ── Fixed-length binary-search node (0x20) ────────────────

        private long CompileNodeFixed(UncompiledNode node, bool lastArcCanTargetNext, long nodeAddr)
        {
            int numArcs = node.Arcs.Count;
            MeasureArcs(node, lastArcCanTargetNext, nodeAddr,
                out int maxOutB, out int maxFinalB, out int maxTargetB);

            int bytesPerArc = 1 + _labelBytes + maxOutB + maxFinalB + maxTargetB;
            int hdrSize = VLongByteCount(numArcs) + VLongByteCount(maxOutB)
                        + VLongByteCount(maxFinalB) + VLongByteCount(maxTargetB);
            int totalLen = numArcs * bytesPerArc + hdrSize + 1;
            var buf = new byte[totalLen];
            int p = 0;

            for (int i = numArcs - 1; i >= 0; i--)
            {
                MutableArc arc = node.Arcs[i];
                bool isStop = arc.Target < 0;
                bool canTargetNext = i == numArcs - 1 && !isStop && lastArcCanTargetNext;
                long tgt = isStop ? 0 : canTargetNext ? nodeAddr : arc.Target;

                WriteFixedBE(buf, p, tgt, maxTargetB);
                WriteFixedBE(buf, p + maxTargetB, arc.FinalOutput, maxFinalB);
                WriteFixedBE(buf, p + maxTargetB + maxFinalB, arc.Output, maxOutB);
                WriteLabelBE(buf, p + maxTargetB + maxFinalB + maxOutB, arc.Label);
                buf[p + bytesPerArc - 1] = BuildFlags(arc, i == numArcs - 1, isStop, canTargetNext);
                p += bytesPerArc;
            }

            WriteVLongRev(buf, ref p, numArcs);
            WriteVLongRev(buf, ref p, maxOutB);
            WriteVLongRev(buf, ref p, maxFinalB);
            WriteVLongRev(buf, ref p, maxTargetB);
            buf[p++] = Fst.NODE_FIXED_LEN;

            return WriteAndDedup(buf, totalLen, lastArcCanTargetNext, nodeAddr);
        }

        // ── Direct-addressing node (0x40) ─────────────────────────

        private long CompileNodeDirect(UncompiledNode node, bool lastArcCanTargetNext,
            long nodeAddr, int labelRange)
        {
            int numArcs = node.Arcs.Count;
            int firstLabel = node.Arcs[0].Label;
            MeasureArcs(node, lastArcCanTargetNext, nodeAddr,
                out int maxOutB, out int maxFinalB, out int maxTargetB);

            int bytesPerArc = 1 + maxOutB + maxFinalB + maxTargetB;
            int bitmapBytes = (labelRange + 7) / 8;
            int hdrSize = VLongByteCount(numArcs) + VLongByteCount(labelRange)
                        + VLongByteCount(firstLabel) + VLongByteCount(maxOutB)
                        + VLongByteCount(maxFinalB) + VLongByteCount(maxTargetB);
            int totalLen = bitmapBytes + numArcs * bytesPerArc + hdrSize + 1;
            var buf = new byte[totalLen];
            int p = 0;

            // Bitmap: one bit per label in [firstLabel, firstLabel+labelRange)
            for (int i = 0; i < numArcs; i++)
            {
                int bit = node.Arcs[i].Label - firstLabel;
                buf[p + bit / 8] |= (byte)(1 << (bit & 7));
            }
            p += bitmapBytes;

            // Arcs in reverse order
            for (int i = numArcs - 1; i >= 0; i--)
            {
                MutableArc arc = node.Arcs[i];
                bool isStop = arc.Target < 0;
                bool canTargetNext = i == numArcs - 1 && !isStop && lastArcCanTargetNext;
                long tgt = isStop ? 0 : canTargetNext ? nodeAddr : arc.Target;

                WriteFixedBE(buf, p, tgt, maxTargetB);
                WriteFixedBE(buf, p + maxTargetB, arc.FinalOutput, maxFinalB);
                WriteFixedBE(buf, p + maxTargetB + maxFinalB, arc.Output, maxOutB);
                buf[p + bytesPerArc - 1] = BuildFlags(arc, i == numArcs - 1, isStop, canTargetNext);
                p += bytesPerArc;
            }

            WriteVLongRev(buf, ref p, numArcs);
            WriteVLongRev(buf, ref p, labelRange);
            WriteVLongRev(buf, ref p, firstLabel);
            WriteVLongRev(buf, ref p, maxOutB);
            WriteVLongRev(buf, ref p, maxFinalB);
            WriteVLongRev(buf, ref p, maxTargetB);
            buf[p++] = Fst.NODE_DIRECT_ADDR;

            return WriteAndDedup(buf, totalLen, lastArcCanTargetNext, nodeAddr);
        }

        // ── Continuous-label array node (0x60) ────────────────────

        private long CompileNodeContinuous(UncompiledNode node, bool lastArcCanTargetNext, long nodeAddr)
        {
            int numArcs = node.Arcs.Count;
            int baseLabel = node.Arcs[0].Label;
            MeasureArcs(node, lastArcCanTargetNext, nodeAddr,
                out int maxOutB, out int maxFinalB, out int maxTargetB);

            int bytesPerArc = 1 + maxOutB + maxFinalB + maxTargetB;
            int hdrSize = VLongByteCount(numArcs) + VLongByteCount(baseLabel)
                        + VLongByteCount(maxOutB) + VLongByteCount(maxFinalB)
                        + VLongByteCount(maxTargetB);
            int totalLen = numArcs * bytesPerArc + hdrSize + 1;
            var buf = new byte[totalLen];
            int p = 0;

            for (int i = numArcs - 1; i >= 0; i--)
            {
                MutableArc arc = node.Arcs[i];
                bool isStop = arc.Target < 0;
                bool canTargetNext = i == numArcs - 1 && !isStop && lastArcCanTargetNext;
                long tgt = isStop ? 0 : canTargetNext ? nodeAddr : arc.Target;

                WriteFixedBE(buf, p, tgt, maxTargetB);
                WriteFixedBE(buf, p + maxTargetB, arc.FinalOutput, maxFinalB);
                WriteFixedBE(buf, p + maxTargetB + maxFinalB, arc.Output, maxOutB);
                buf[p + bytesPerArc - 1] = BuildFlags(arc, i == numArcs - 1, isStop, canTargetNext);
                p += bytesPerArc;
            }

            WriteVLongRev(buf, ref p, numArcs);
            WriteVLongRev(buf, ref p, baseLabel);
            WriteVLongRev(buf, ref p, maxOutB);
            WriteVLongRev(buf, ref p, maxFinalB);
            WriteVLongRev(buf, ref p, maxTargetB);
            buf[p++] = Fst.NODE_CONTINUOUS;

            return WriteAndDedup(buf, totalLen, lastArcCanTargetNext, nodeAddr);
        }

        // ── Shared helpers ────────────────────────────────────────

        private void MeasureArcs(UncompiledNode node, bool lastArcCanTargetNext, long nodeAddr,
            out int maxOutB, out int maxFinalB, out int maxTargetB)
        {
            maxOutB = 0; maxFinalB = 0; maxTargetB = 0;
            int numArcs = node.Arcs.Count;
            for (int i = 0; i < numArcs; i++)
            {
                MutableArc arc = node.Arcs[i];
                if (arc.Output != 0) maxOutB = Math.Max(maxOutB, VLongByteCount(arc.Output));
                if (arc.FinalOutput != 0) maxFinalB = Math.Max(maxFinalB, VLongByteCount(arc.FinalOutput));
                bool isTargetNext = i == numArcs - 1 && arc.Target >= 0 && lastArcCanTargetNext;
                if (arc.Target >= 0 && !isTargetNext)
                    maxTargetB = Math.Max(maxTargetB, VLongByteCount(arc.Target));
            }
            if (lastArcCanTargetNext)
                maxTargetB = Math.Max(maxTargetB, VLongByteCount(nodeAddr));
        }

        private long WriteAndDedup(byte[] buf, int totalLen, bool lastArcCanTargetNext, long nodeAddr)
        {
            if (!lastArcCanTargetNext)
            {
                long hash = NodeHash.ComputeHash(buf, totalLen);
                long existing = _nodeHash.Find(hash, buf, totalLen, _bytes);
                if (existing >= 0) return existing;
                _nodeHash.Add(hash, nodeAddr + totalLen);
            }
            _bytes.WriteBytes(buf);
            return nodeAddr + totalLen;
        }

        private static byte BuildFlags(MutableArc arc, bool isLast, bool isStop, bool canTargetNext)
        {
            byte flags = 0;
            if (arc.IsFinal)          flags |= Fst.FLAG_FINAL_ARC;
            if (isLast)               flags |= Fst.FLAG_LAST_ARC;
            if (arc.Output != 0)      flags |= Fst.FLAG_HAS_OUTPUT;
            if (arc.FinalOutput != 0) flags |= Fst.FLAG_HAS_FINAL_OUT;
            if (isStop)               flags |= Fst.FLAG_STOP_NODE;
            if (canTargetNext)        flags |= Fst.FLAG_TARGET_NEXT;
            return flags;
        }
    }
}
