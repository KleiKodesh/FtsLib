using System.Collections.Generic;

namespace FstLib.Building
{
    internal sealed class MutableArc
    {
        public int Label;
        public long Output;
        public long FinalOutput;
        public bool IsFinal;
        public long Target = -2;
    }

    internal sealed class UncompiledNode
    {
        public readonly List<MutableArc> Arcs = new List<MutableArc>(4);
        public long Output;
        public bool IsFinal;
        public long FinalOutput;

        public void Clear()
        {
            Arcs.Clear();
            IsFinal = false;
            Output = 0;
            FinalOutput = 0;
        }

        public MutableArc LastArc => Arcs[Arcs.Count - 1];

        public void AddArc(int label, UncompiledNode target)
            => Arcs.Add(new MutableArc { Label = label, Target = -2 });
    }
}
