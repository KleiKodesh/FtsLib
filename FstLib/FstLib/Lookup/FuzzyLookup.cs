using System;
using System.Collections.Generic;
using FstLib.Core;
using FstLib.Morphology;

namespace FstLib.Lookup
{
    // Levenshtein fuzzy search over the FST.
    // Uses the Lucene parametric DFA for maxEdits 1 or 2 (fast), and falls back
    // to the DP-row walk for higher values.
    internal sealed partial class FstLookup
    {
        // ── Public fuzzy API ──────────────────────────────────────

        /// <summary>
        /// Enumerates all keys whose Levenshtein distance to <paramref name="key"/> is at most <paramref name="maxEdits"/>.
        /// Uses the Lucene parametric DFA for maxEdits 1 or 2 (optimized), and falls back to
        /// the DP-row walk for higher values.
        /// </summary>
        internal IEnumerable<(string Key, long Value)> EnumerateFuzzy(string key, int maxEdits)
        {
            if (key == null) throw new ArgumentNullException(nameof(key));
            if (maxEdits < 0) throw new ArgumentOutOfRangeException(nameof(maxEdits), "Max edits must be non-negative.");
            if (_fst.RootAddress < 0) yield break;

            int[] pattern = EncodeKey(key);

            // Fast path: use Lucene parametric DFA for distance 1 or 2
            if (maxEdits == 1 || maxEdits == 2)
            {
                foreach (var kv in WalkFuzzyDfa(pattern, maxEdits))
                    yield return kv;
                yield break;
            }

            // Fallback: DP-row walk for any distance
            var row = new int[pattern.Length + 1];
            for (int i = 0; i <= pattern.Length; i++) row[i] = i;

            if (_fst.HasRootFinal && row[pattern.Length] <= maxEdits)
                yield return ("", _fst.RootFinalOutput);

            var path = new List<int>();
            foreach (var kv in WalkFuzzy(_fst.RootAddress, path, row, 0, pattern, maxEdits))
                yield return kv;
        }

        // ── DP-row walk ───────────────────────────────────────────

        private IEnumerable<(string Key, long Value)> WalkFuzzy(
            long nodeAddr, List<int> path, int[] prevRow, long accum,
            int[] pattern, int maxEdits)
        {
            if (nodeAddr < 0) yield break;

            int patLen = pattern.Length;
            foreach (var arc in ReadAllArcs(nodeAddr))
            {
                var nextRow = new int[patLen + 1];
                nextRow[0] = prevRow[0] + 1;
                int best = nextRow[0];

                for (int j = 1; j <= patLen; j++)
                {
                    int cost = arc.Label == pattern[j - 1] ? 0 : 1;
                    int val = Math.Min(Math.Min(prevRow[j] + 1, nextRow[j - 1] + 1), prevRow[j - 1] + cost);
                    nextRow[j] = val;
                    if (val < best) best = val;
                }

                if (best > maxEdits) continue;

                path.Add(arc.Label);
                long childAccum = accum + arc.Output;

                if (arc.IsFinal && nextRow[patLen] <= maxEdits)
                    yield return (BuildKey(path), childAccum + arc.FinalOutput);

                if (arc.TargetAddress >= 0)
                    foreach (var kv in WalkFuzzy(arc.TargetAddress, path, nextRow, childAccum, pattern, maxEdits))
                        yield return kv;

                path.RemoveAt(path.Count - 1);
            }
        }

        // ── Lucene parametric-DFA walk ────────────────────────────
        // Walks the FST while simultaneously running the Lucene parametric DFA.
        // Each stack frame pairs an FST node with the DFA state reached so far.
        // We must NOT deduplicate on DFA state alone — the same DFA state can be
        // reached from many different FST nodes with different accumulated paths.

        private IEnumerable<(string Key, long Value)> WalkFuzzyDfa(int[] pattern, int maxEdits)
        {
            ParametricDescription dfa = maxEdits == 1
                ? (ParametricDescription)new Lev1ParametricDescription(pattern.Length)
                : (ParametricDescription)new Lev2ParametricDescription(pattern.Length);

            int range = 2 * maxEdits + 1;

            var stack = new Stack<(long node, List<int> path, int state, long accum)>();
            stack.Push((_fst.RootAddress, new List<int>(), 0, 0));

            if (_fst.HasRootFinal && dfa.IsAccept(0))
                yield return ("", _fst.RootFinalOutput);

            while (stack.Count > 0)
            {
                var (node, path, state, accum) = stack.Pop();
                if (node < 0) continue;

                foreach (var arc in ReadAllArcs(node))
                {
                    int xpos = dfa.GetPosition(state);
                    // Characteristic vector: window of length min(w-xpos, range),
                    // built MSB-first exactly as Lucene's getVector().
                    int end  = xpos + Math.Min(pattern.Length - xpos, range);
                    int cvec = 0;
                    for (int i = xpos; i < end; i++)
                    {
                        cvec <<= 1;
                        if (pattern[i] == arc.Label) cvec |= 1;
                    }

                    int dest = dfa.Transition(state, xpos, cvec);
                    if (dest < 0) continue;

                    var newPath = new List<int>(path);
                    newPath.Add(arc.Label);
                    long childAccum = accum + arc.Output;

                    if (arc.IsFinal && dfa.IsAccept(dest))
                        yield return (BuildKey(newPath), childAccum + arc.FinalOutput);

                    if (arc.TargetAddress >= 0)
                        stack.Push((arc.TargetAddress, newPath, dest, childAccum));
                }
            }
        }

        // ── Classic automaton walk ────────────────────────────────

        // Removed: WalkFuzzyAutomaton was only used by EnumerateFuzzyAutomaton (now deleted).
        // The DP-row walk (WalkFuzzy) handles all distances and is simpler to maintain.
    }
}
