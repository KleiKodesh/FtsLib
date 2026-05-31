using System;

namespace FstLib.Lookup
{
    /// <summary>
    /// DFA for matching strings that contain a specific substring.
    /// Uses KMP-style failure function for efficient state transitions.
    /// 
    /// This DFA is used during FST traversal to prune branches where the pattern
    /// cannot possibly be found, reducing the search space from O(n) to O(m + k)
    /// where m = pattern length and k = results.
    /// </summary>
    internal class ContainsDfa
    {
        public const int DEAD_STATE = -1;
        
        private readonly int[] _pattern;
        private readonly int[] _failure;
        private readonly int _patternLen;

        internal ContainsDfa(int[] pattern)
        {
            _pattern = pattern;
            _patternLen = pattern.Length;
            _failure = BuildFailureFunction(pattern);
        }

        /// <summary>
        /// Transitions the DFA given a label.
        /// Returns the new state, or DEAD_STATE if no match is possible.
        /// 
        /// Once the pattern is fully matched (state == _patternLen), the DFA
        /// stays in the accepting state for all subsequent transitions.
        /// </summary>
        internal int Transition(int state, int label)
        {
            // If we've already matched the pattern, stay in accepting state
            if (state == _patternLen)
                return _patternLen;

            // Try to extend the match using KMP-style failure function
            while (state > 0 && _pattern[state] != label)
                state = _failure[state - 1];

            if (_pattern[state] == label)
                state++;

            return state;
        }

        /// <summary>
        /// Returns true if the DFA state indicates the pattern has been seen.
        /// </summary>
        internal bool IsAccepting(int state)
        {
            return state == _patternLen;
        }

        /// <summary>
        /// Builds the KMP failure function for the pattern.
        /// failure[i] = length of the longest proper prefix of pattern[0..i]
        /// that is also a suffix of pattern[0..i].
        /// </summary>
        private static int[] BuildFailureFunction(int[] pattern)
        {
            int len = pattern.Length;
            var failure = new int[len];
            int j = 0;

            for (int i = 1; i < len; i++)
            {
                while (j > 0 && pattern[i] != pattern[j])
                    j = failure[j - 1];

                if (pattern[i] == pattern[j])
                    j++;

                failure[i] = j;
            }

            return failure;
        }
    }
}
