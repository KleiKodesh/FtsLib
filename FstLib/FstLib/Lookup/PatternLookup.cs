using System;
using System.Collections.Generic;
using FstLib.Core;

namespace FstLib.Lookup
{
    /// <summary>
    /// Pattern-based lookups using FST arc traversal.
    /// 
    /// Efficiently finds all keys matching a pattern by:
    /// 1. Traversing the FST following pattern characters
    /// 2. Enumerating descendants from the matched node
    /// 
    /// Complexity: O(m + k) where m = pattern length, k = results
    /// </summary>
    internal sealed partial class FstLookup
    {
        /// <summary>
        /// Enumerates all keys that start with the given pattern (word*).
        /// Uses arc traversal: O(m + k) instead of O(n) full enumeration.
        /// </summary>
        internal IEnumerable<(string Key, long Value)> EnumerateStartsWith(string pattern)
        {
            if (pattern == null) throw new ArgumentNullException(nameof(pattern));
            if (pattern.Length == 0) throw new ArgumentException("Pattern cannot be empty");

            long? nodeAddr = TraversePattern(pattern);
            if (nodeAddr == null) yield break;

            var pathLabels = new List<int>();
            foreach (var label in EncodeKey(pattern))
                pathLabels.Add(label);

            foreach (var result in EnumerateDescendants(nodeAddr.Value, pathLabels, 0))
                yield return result;
        }

        /// <summary>
        /// Enumerates all keys that end with the given pattern (*word).
        /// Uses reverse FST for efficiency if available, otherwise uses efficient traversal.
        /// </summary>
        internal IEnumerable<(string Key, long Value)> EnumerateEndsWith(string pattern)
        {
            if (pattern == null) throw new ArgumentNullException(nameof(pattern));
            if (pattern.Length == 0) throw new ArgumentException("Pattern cannot be empty");

            if (_reverseLookup == null)
            {
                // If this IS the reverse FST (no _reverseLookup), we cannot efficiently find keys ending with a pattern
                // because we don't have a reverse-of-reverse FST. Fall back to full enumeration.
                foreach (var (key, value) in EnumerateAll())
                {
                    if (key.EndsWith(pattern))
                        yield return (key, value);
                }
                yield break;
            }

            string reversedPattern = ReverseString(pattern);
            long? nodeAddr = _reverseLookup.TraversePattern(reversedPattern);
            if (nodeAddr == null) yield break;

            var pathLabels = new List<int>();
            foreach (var label in _reverseLookup.EncodeKey(reversedPattern))
                pathLabels.Add(label);

            foreach (var (key, value) in _reverseLookup.EnumerateDescendants(nodeAddr.Value, pathLabels, 0))
                yield return (ReverseString(key), value);
        }

        /// <summary>
        /// Enumerates all keys that contain the given pattern (*word*).
        /// 
        /// Uses DFA intersection with FST traversal to prune subtrees where the pattern
        /// cannot possibly be found. This reduces complexity from O(n) to O(m + k)
        /// where m = pattern length and k = results.
        /// 
        /// Complexity: O(m + k) where m = pattern length, k = results
        /// </summary>
        internal IEnumerable<(string Key, long Value)> EnumerateContains(string pattern)
        {
            if (pattern == null) throw new ArgumentNullException(nameof(pattern));
            if (pattern.Length == 0) throw new ArgumentException("Pattern cannot be empty");

            // Build a DFA that matches any string containing the pattern
            int[] patternLabels = EncodeKey(pattern);
            var dfa = new ContainsDfa(patternLabels);
            
            var pathLabels = new List<int>();
            foreach (var result in WalkWithDfaIntersection(_fst.RootAddress, 0L, pathLabels, dfa, 0, false, 0))
                yield return result;
        }

        /// <summary>
        /// Walks the FST while intersecting with a DFA state machine.
        /// Prunes branches where the DFA state is dead (no match possible).
        /// </summary>
        private IEnumerable<(string Key, long Value)> WalkWithDfaIntersection(
            long nodeAddr,
            long accumulated,
            List<int> pathLabels,
            ContainsDfa dfa,
            int dfaState,
            bool isFinal,
            long finalOutput)
        {
            // Yield if this node is final and DFA has seen the pattern
            if (isFinal && dfa.IsAccepting(dfaState))
                yield return (BuildKey(pathLabels), accumulated + finalOutput);

            if (nodeAddr < 0)
                yield break;

            foreach (var arc in ReadAllArcs(nodeAddr))
            {
                // Advance DFA with this label
                int nextDfaState = dfa.Transition(dfaState, arc.Label);
                
                // Prune: if DFA is dead, skip this entire subtree
                if (nextDfaState == ContainsDfa.DEAD_STATE)
                    continue;

                pathLabels.Add(arc.Label);
                long childAccum = accumulated + arc.Output;

                if (arc.TargetAddress < 0)
                {
                    if (arc.IsFinal && dfa.IsAccepting(nextDfaState))
                        yield return (BuildKey(pathLabels), childAccum + arc.FinalOutput);
                }
                else
                {
                    foreach (var result in WalkWithDfaIntersection(
                        arc.TargetAddress, childAccum, pathLabels, dfa, nextDfaState, arc.IsFinal, arc.FinalOutput))
                        yield return result;
                }

                pathLabels.RemoveAt(pathLabels.Count - 1);
            }
        }

        private static string ReverseString(string s)
        {
            var chars = s.ToCharArray();
            System.Array.Reverse(chars);
            return new string(chars);
        }
    }
}
