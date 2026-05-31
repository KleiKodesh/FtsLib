using System;
using System.Collections.Generic;
using System.Text;
using FstLib.Core;

namespace FstLib.Lookup
{
    /// <summary>
    /// Reads a compiled <see cref="Fst"/> and answers exact-match, fuzzy, range,
    /// and enumeration queries.
    ///
    /// The class is split across partial files by concern:
    ///   ExactLookup.cs          — exact lookup, full enumeration, key encoding
    ///   ArcReader.cs            — low-level binary arc I/O (all node formats)
    ///   FuzzySearch.cs          — Levenshtein / automaton fuzzy walk
    ///   RangeSearch.cs          — ceiling / floor / ordered-range queries
    /// </summary>
    internal sealed partial class FstLookup
    {
        private readonly Fst _fst;
        private readonly byte _labelBytes;
        private readonly FstLookup _reverseLookup;

        internal FstLookup(Fst fst, FstLookup reverseLookup = null)
        {
            _fst = fst;
            _labelBytes = fst.LabelBytes;
            _reverseLookup = reverseLookup;
        }

        // ── Exact lookup ──────────────────────────────────────────

        internal bool TryGet(string key, out long output)
        {
            output = 0;
            int[] keyLabels = EncodeKey(key);
            return TryGet(keyLabels, out output);
        }

        public bool TryGet(byte[] key, out long output)
        {
            output = 0;
            if (_fst.RootAddress < 0) return false;

            if (key.Length == 0)
            {
                if (!_fst.HasRootFinal) return false;
                output = _fst.RootFinalOutput;
                return true;
            }

            // Convert raw bytes to int labels and delegate to the int[] overload.
            var labels = new int[key.Length];
            for (int i = 0; i < key.Length; i++) labels[i] = key[i] & 0xFF;
            return TryGet(labels, out output);
        }

        private bool TryGet(int[] key, out long output)
        {
            output = 0;
            if (_fst.RootAddress < 0) return false;

            if (key.Length == 0)
            {
                if (!_fst.HasRootFinal) return false;
                output = _fst.RootFinalOutput;
                return true;
            }

            long accum = 0;
            long nodeAddr = _fst.RootAddress;

            for (int i = 0; i < key.Length; i++)
            {
                if (!FindArc(nodeAddr, key[i], out ArcData arc)) return false;

                accum += arc.Output;

                if (i == key.Length - 1)
                {
                    if (!arc.IsFinal) return false;
                    output = accum + arc.FinalOutput;
                    return true;
                }

                nodeAddr = arc.TargetAddress;
                if (nodeAddr < 0) return false;
            }
            return false;
        }


        // ── Full enumeration ──────────────────────────────────────

        internal IEnumerable<(string Key, long Value)> EnumerateAll()
        {
            if (_fst.RootAddress < 0) yield break;
            if (_fst.HasRootFinal)
                yield return ("", _fst.RootFinalOutput);
            var path = new List<(int Label, long Output, long NextNodeAddr)>();
            foreach (var kv in Walk(_fst.RootAddress, 0L, path, false, 0))
                yield return kv;
        }

        private IEnumerable<(string Key, long Value)> Walk(
            long nodeAddr, long accumulated,
            List<(int Label, long Output, long NextNodeAddr)> path,
            bool isFinal, long finalOutput)
        {
            if (isFinal)
                yield return (BuildKey(path), accumulated + finalOutput);

            foreach (var arc in ReadAllArcs(nodeAddr))
            {
                path.Add((arc.Label, arc.Output, arc.TargetAddress));
                long childAccum = accumulated + arc.Output;

                if (arc.TargetAddress < 0)
                {
                    if (arc.IsFinal)
                        yield return (BuildKey(path), childAccum + arc.FinalOutput);
                }
                else
                {
                    foreach (var kv in Walk(arc.TargetAddress, childAccum, path, arc.IsFinal, arc.FinalOutput))
                        yield return kv;
                }
                path.RemoveAt(path.Count - 1);
            }
        }

        // ── Key encoding / decoding ───────────────────────────────

        private int[] EncodeKey(string key)
        {
            return _labelBytes switch
            {
                1 => Array.ConvertAll(Encoding.UTF8.GetBytes(key), bt => bt & 0xFF),
                2 => ToLabels(Encoding.Unicode.GetBytes(key), 2),
                4 => ToLabels(Encoding.UTF32.GetBytes(key), 4),
                _ => throw new InvalidOperationException($"Unsupported label width {_labelBytes}.")
            };

            static int[] ToLabels(byte[] bytes, int labelBytes)
            {
                if (bytes.Length % labelBytes != 0) throw new ArgumentException("Invalid encoded length.");
                int len = bytes.Length / labelBytes;
                var labels = new int[len];
                for (int i = 0; i < len; i++)
                {
                    int val = 0;
                    for (int b = 0; b < labelBytes; b++)
                        val |= (bytes[i * labelBytes + b] & 0xFF) << (8 * b);
                    labels[i] = val;
                }
                return labels;
            }
        }

        internal static byte[] EncodeLabels(List<int> labels, int labelBytes)
        {
            var bytes = new byte[labels.Count * labelBytes];
            for (int i = 0; i < labels.Count; i++)
            {
                int v = labels[i];
                for (int b = 0; b < labelBytes; b++)
                    bytes[i * labelBytes + b] = (byte)((v >> (8 * b)) & 0xFF);
            }
            return bytes;
        }

        private string DecodeKey(byte[] key)
        {
            return _labelBytes switch
            {
                1 => Encoding.UTF8.GetString(key),
                2 => Encoding.Unicode.GetString(key),
                4 => Encoding.UTF32.GetString(key),
                _ => throw new InvalidOperationException($"Unsupported label width {_labelBytes}.")
            };
        }

        private string BuildKey(List<(int Label, long Output, long NextNodeAddr)> path)
        {
            int labelBytes = _labelBytes;
            var bytes = new byte[path.Count * labelBytes];
            for (int i = 0; i < path.Count; i++)
            {
                int label = path[i].Label;
                for (int b = 0; b < labelBytes; b++)
                    bytes[i * labelBytes + b] = (byte)((label >> (8 * b)) & 0xFF);
            }
            return DecodeKey(bytes);
        }

        private string BuildKey(List<int> labels)
        {
            var bytes = EncodeLabels(labels, _labelBytes);
            return DecodeKey(bytes);
        }

        /// <summary>
        /// Traverses the FST following the given pattern characters.
        /// Returns the node address where the pattern ends, or null if pattern not found.
        /// Complexity: O(m) where m = pattern length
        /// </summary>
        private long? TraversePattern(string pattern)
        {
            if (pattern == null || pattern.Length == 0)
                return _fst.RootAddress;

            long nodeAddr = _fst.RootAddress;
            if (nodeAddr < 0) return null;

            int[] patternLabels = EncodeKey(pattern);

            for (int i = 0; i < patternLabels.Length; i++)
            {
                if (!FindArc(nodeAddr, patternLabels[i], out ArcData arc))
                    return null;

                nodeAddr = arc.TargetAddress;
                if (nodeAddr < 0 && i < patternLabels.Length - 1)
                    return null;
            }

            return nodeAddr;
        }

        /// <summary>
        /// Enumerates all descendants of the given node.
        /// Used for prefix/suffix/contains queries after pattern traversal.
        /// Complexity: O(k) where k = number of descendants
        /// </summary>
        private IEnumerable<(string Key, long Value)> EnumerateDescendants(
            long nodeAddr,
            List<int> pathLabels,
            long accumulated)
        {
            return EnumerateDescendantsInternal(nodeAddr, pathLabels, accumulated, false, 0);
        }

        private IEnumerable<(string Key, long Value)> EnumerateDescendantsInternal(
            long nodeAddr,
            List<int> pathLabels,
            long accumulated,
            bool isFinal,
            long finalOutput)
        {
            if (isFinal)
                yield return (BuildKey(pathLabels), accumulated + finalOutput);

            if (nodeAddr < 0)
                yield break;

            foreach (var arc in ReadAllArcs(nodeAddr))
            {
                pathLabels.Add(arc.Label);
                long childAccum = accumulated + arc.Output;

                if (arc.TargetAddress < 0)
                {
                    if (arc.IsFinal)
                        yield return (BuildKey(pathLabels), childAccum + arc.FinalOutput);
                }
                else
                {
                    foreach (var result in EnumerateDescendantsInternal(arc.TargetAddress, pathLabels, childAccum, arc.IsFinal, arc.FinalOutput))
                        yield return result;
                }

                pathLabels.RemoveAt(pathLabels.Count - 1);
            }
        }
    }
}
