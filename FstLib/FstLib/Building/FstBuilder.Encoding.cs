using System.Collections.Generic;

namespace FstLib.Building
{
    // Low-level byte-encoding primitives used by all four node serialisation formats.
    // These have no dependency on arc format logic and are kept separate so
    // FstBuilder.NodeCompiler.cs can focus purely on format selection and layout.
    internal sealed partial class FstBuilder
    {
        // ── VLong sizing ──────────────────────────────────────────

        private static int VLongByteCount(long v)
        {
            ulong uv = (ulong)v;
            int c = 0;
            do { c++; uv >>= 7; } while (uv != 0);
            return c;
        }

        // ── Buffer writers ────────────────────────────────────────

        /// <summary>Appends a VLong to a forward byte list (used by the linear-scan format).</summary>
        private static void WriteVLong(List<byte> buf, long v)
        {
            ulong uv = (ulong)v;
            while (uv >= 0x80) { buf.Add((byte)(uv | 0x80)); uv >>= 7; }
            buf.Add((byte)uv);
        }

        /// <summary>Appends a label (1, 2, or 4 bytes little-endian) to a forward byte list.</summary>
        private void WriteLabel(List<byte> buf, int label)
        {
            if (_labelBytes == 1) { buf.Add((byte)(label & 0xFF)); return; }
            if (_labelBytes == 2)
            {
                buf.Add((byte)(label & 0xFF));
                buf.Add((byte)((label >> 8) & 0xFF));
                return;
            }
            buf.Add((byte)(label & 0xFF));
            buf.Add((byte)((label >> 8)  & 0xFF));
            buf.Add((byte)((label >> 16) & 0xFF));
            buf.Add((byte)((label >> 24) & 0xFF));
        }

        // ── Fixed-buffer writers (reversed / big-endian) ──────────

        /// <summary>
        /// Writes a VLong into <paramref name="buf"/> starting at <paramref name="pos"/>,
        /// then reverses the written bytes so the most-significant byte is first.
        /// Used when building node buffers that are stored in reversed order.
        /// </summary>
        private static void WriteVLongRev(byte[] buf, ref int pos, long v)
        {
            ulong uv = (ulong)v;
            int start = pos;
            while (uv >= 0x80) { buf[pos++] = (byte)(uv | 0x80); uv >>= 7; }
            buf[pos++] = (byte)uv;
            System.Array.Reverse(buf, start, pos - start);
        }

        /// <summary>Writes <paramref name="value"/> as a big-endian fixed-width integer of <paramref name="bytes"/> bytes.</summary>
        private static void WriteFixedBE(byte[] buf, int pos, long value, int bytes)
        {
            for (int i = bytes - 1; i >= 0; i--)
                buf[pos + (bytes - 1 - i)] = (byte)((value >> (8 * i)) & 0xFF);
        }

        /// <summary>Writes a label as a big-endian fixed-width integer (1, 2, or 4 bytes).</summary>
        private void WriteLabelBE(byte[] buf, int pos, int label)
        {
            if (_labelBytes == 1) { buf[pos] = (byte)label; return; }
            if (_labelBytes == 2)
            {
                buf[pos]     = (byte)((label >> 8) & 0xFF);
                buf[pos + 1] = (byte)(label & 0xFF);
                return;
            }
            buf[pos]     = (byte)((label >> 24) & 0xFF);
            buf[pos + 1] = (byte)((label >> 16) & 0xFF);
            buf[pos + 2] = (byte)((label >> 8)  & 0xFF);
            buf[pos + 3] = (byte)(label & 0xFF);
        }
    }
}
