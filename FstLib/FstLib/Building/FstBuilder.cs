using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using FstLib.Building;
using FstLib.Core;

namespace FstLib.Building
{
    /// <summary>
    /// Builds a minimal acyclic FST from a sorted sequence of (key, value) pairs.
    ///
    /// Split across partial files:
    ///   FstBuilder.cs             — public API, frontier management, key utilities
    ///   FstBuilder.NodeCompiler.cs — node serialisation for all four arc formats
    /// </summary>
    internal sealed partial class FstBuilder
    {
        private const int MaxDepth = 256;

        private readonly UncompiledNode[] _frontier;
        private readonly long[] _nodeOutput;
        private ByteStore _bytes = new ByteStore();
        private readonly NodeHash _nodeHash;
        private readonly InputType _inputType;
        private readonly byte _labelBytes;

        private byte[] _lastKey = Array.Empty<byte>();
        private bool _finished = false;
        private long _rootAddress = -1;

        public FstBuilder(InputType inputType = InputType.BYTE2, int suffixRamLimitMb = 32)
        {
            _inputType = inputType;
            _labelBytes = (byte)inputType;
            int maxRam = suffixRamLimitMb <= 0 ? int.MaxValue : suffixRamLimitMb * 1024 * 1024;
            _nodeHash = new NodeHash(maxRamBytes: maxRam);
            _frontier = new UncompiledNode[MaxDepth];
            _nodeOutput = new long[MaxDepth];
            for (int i = 0; i < MaxDepth; i++)
                _frontier[i] = new UncompiledNode();
        }

        // ── Public API ────────────────────────────────────────────

        internal void Add(string key, long output = 0)
        {
            if (_finished) throw new InvalidOperationException("Builder already finished.");

            byte[] keyBytes = EncodeKey(key);
            if (keyBytes.Length % _labelBytes != 0)
                throw new ArgumentException($"Key encoding length {keyBytes.Length} is not aligned to label width {_labelBytes}.");

            int keyLen = keyBytes.Length / _labelBytes;
            if (keyLen >= MaxDepth)
                throw new ArgumentException($"Key length {keyLen} exceeds maximum supported length {MaxDepth - 1}.");

            if (_lastKey.Length > 0)
            {
                int cmp = Compare(_lastKey, keyBytes, _labelBytes);
                if (cmp > 0) throw new ArgumentException($"Keys must be in sorted order. '{key}' is out of order.");
                if (cmp == 0) throw new ArgumentException($"Duplicate key '{key}'.");
            }

            int prefixLen = CommonPrefixLength(_lastKey, keyBytes, _labelBytes);
            FreezeFrom(prefixLen + 1);

            for (int i = prefixLen; i < keyLen; i++)
            {
                int label = GetLabel(keyBytes, i, _labelBytes);
                _frontier[i].AddArc(label, _frontier[i + 1]);
                _frontier[i + 1].Clear();
            }

            UncompiledNode terminal = _frontier[keyLen];
            terminal.IsFinal = true;

            if (prefixLen < keyLen)
                _frontier[prefixLen].LastArc.Output = output - _nodeOutput[prefixLen];
            else
                terminal.FinalOutput = output - _nodeOutput[prefixLen];

            _nodeOutput[0] = 0;
            for (int d = 0; d < keyLen; d++)
                _nodeOutput[d + 1] = _nodeOutput[d] + _frontier[d].LastArc.Output;

            _lastKey = keyBytes;
        }

        internal Fst Finish()
        {
            if (_finished) throw new InvalidOperationException("Builder already finished.");
            _finished = true;
            bool rootFinal = _frontier[0].IsFinal;
            long rootFinalOut = _frontier[0].FinalOutput;
            FreezeFrom(0);
            return new Fst(_bytes.ToArray(), _rootAddress, _inputType, rootFinal, rootFinalOut);
        }

        internal void Finish(Stream outputStream)
        {
            if (_finished) throw new InvalidOperationException("Builder already finished.");
            _finished = true;
            FreezeFrom(0);
            var bytes = _bytes.ToArray();
            outputStream.Write(bytes, 0, bytes.Length);
        }

        // ── Frontier management ───────────────────────────────────

        private void FreezeFrom(int startDepth)
        {
            int lastKeyLen = _lastKey.Length / _labelBytes;
            for (int depth = lastKeyLen; depth >= startDepth; depth--)
            {
                UncompiledNode node = _frontier[depth];
                long compiledAddr = CompileNode(node, depth);

                if (depth == 0) _rootAddress = compiledAddr;
                else
                {
                    MutableArc parentArc = _frontier[depth - 1].LastArc;
                    parentArc.Target = compiledAddr;
                    parentArc.IsFinal = node.IsFinal;
                    parentArc.FinalOutput = node.FinalOutput;
                }
                node.Clear();
            }
        }

        // ── Key utilities ─────────────────────────────────────────

        private static int CommonPrefixLength(byte[] a, byte[] b, int labelBytes)
        {
            int len = Math.Min(a.Length / labelBytes, b.Length / labelBytes);
            for (int i = 0; i < len; i++)
                if (GetLabel(a, i, labelBytes) != GetLabel(b, i, labelBytes)) return i;
            return len;
        }

        private static int Compare(byte[] a, byte[] b, int labelBytes)
        {
            int len = Math.Min(a.Length / labelBytes, b.Length / labelBytes);
            for (int i = 0; i < len; i++)
            {
                int d = GetLabel(a, i, labelBytes) - GetLabel(b, i, labelBytes);
                if (d != 0) return d;
            }
            return a.Length - b.Length;
        }

        private static int GetLabel(byte[] keyBytes, int index, int labelBytes)
        {
            int offset = index * labelBytes;
            if (labelBytes == 1) return keyBytes[offset] & 0xFF;
            if (labelBytes == 2) return (keyBytes[offset] & 0xFF) | ((keyBytes[offset + 1] & 0xFF) << 8);
            return (keyBytes[offset] & 0xFF)
                 | ((keyBytes[offset + 1] & 0xFF) << 8)
                 | ((keyBytes[offset + 2] & 0xFF) << 16)
                 | ((keyBytes[offset + 3] & 0xFF) << 24);
        }

        private byte[] EncodeKey(string key)
        {
            return _inputType switch
            {
                InputType.BYTE1 => Encoding.UTF8.GetBytes(key),
                InputType.BYTE2 => Encoding.Unicode.GetBytes(key),
                InputType.BYTE4 => Encoding.UTF32.GetBytes(key),
                _ => throw new InvalidOperationException($"Unsupported input type {_inputType}.")
            };
        }

        // ── Reverse FST support ───────────────────────────────────

        /// <summary>
        /// Builds a reverse FST from the given entries.
        /// Keys are reversed before building, so suffix queries on the forward FST
        /// become prefix queries on the reverse FST.
        /// </summary>
        /// <param name="entries">Sequence of (key, value) pairs in sorted order.</param>
        /// <param name="inputType">Label type (BYTE1/BYTE2/BYTE4). Default BYTE1.</param>
        /// <param name="suffixRamLimitMb">Suffix dedup cache RAM limit in MB. Default 32.</param>
        /// <returns>A reverse FST where keys are reversed.</returns>
        internal static Fst BuildReverse(IEnumerable<(string Key, long Value)> entries,
            InputType inputType = InputType.BYTE1, int suffixRamLimitMb = 32)
        {
            if (entries == null) throw new ArgumentNullException(nameof(entries));

            // Collect and sort entries by reversed key
            var reversedEntries = new List<(string ReversedKey, long Value)>();
            foreach (var (key, value) in entries)
            {
                string reversedKey = ReverseString(key);
                reversedEntries.Add((reversedKey, value));
            }

            // Sort by reversed key
            reversedEntries.Sort((a, b) => string.CompareOrdinal(a.ReversedKey, b.ReversedKey));

            var builder = new FstBuilder(inputType, suffixRamLimitMb);
            foreach (var (reversedKey, value) in reversedEntries)
            {
                builder.Add(reversedKey, value);
            }
            return builder.Finish();
        }

        /// <summary>
        /// Reverses a string character by character.
        /// </summary>
        private static string ReverseString(string s)
        {
            if (string.IsNullOrEmpty(s)) return s;
            var chars = s.ToCharArray();
            System.Array.Reverse(chars);
            return new string(chars);
        }
    }
}
