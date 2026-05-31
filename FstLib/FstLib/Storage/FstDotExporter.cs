using System.Collections.Generic;
using System.IO;
using FstLib.Core;
using FstLib.Lookup;

namespace FstLib.Storage
{
    /// <summary>
    /// Exports a compiled <see cref="Fst"/> as a Graphviz DOT graph for visualization and debugging.
    /// Arc reading is delegated to <see cref="FstLookup"/> to avoid duplication.
    /// </summary>
    internal static class FstDotExporter
    {
        /// <summary>Writes a Graphviz DOT representation of <paramref name="fst"/> to <paramref name="writer"/>.</summary>
        internal static void ToDot(Fst fst, TextWriter writer)
        {
            writer.WriteLine("digraph FST {");
            writer.WriteLine("  rankdir = LR;");
            writer.WriteLine("  node [shape=circle, width=.3, height=.3, style=filled, fillcolor=white];");
            writer.WriteLine("  -1 [shape=doublecircle, fillcolor=black, fontcolor=white, label=\"\"];");

            var lookup  = new FstLookup(fst);
            var visited = new HashSet<long>();
            VisitNode(lookup, fst.RootAddress, visited, writer);

            writer.WriteLine("}");
        }

        private static void VisitNode(FstLookup lookup, long nodeAddr, HashSet<long> visited, TextWriter w)
        {
            if (nodeAddr < 0 || !visited.Add(nodeAddr)) return;

            foreach (var arc in lookup.ReadAllArcsPublic(nodeAddr))
            {
                string edgeLabel = arc.Label < 0x20 || arc.Label > 0x7e
                    ? $"0x{arc.Label:X2}"
                    : $"{(char)arc.Label}";
                string extra = "";
                if (arc.Output      != 0) extra += $"/{arc.Output}";
                if (arc.IsFinal)          extra += " [F]";
                if (arc.IsTargetNext)     extra += " [TN]";

                string color = arc.IsTargetNext ? "red" : "black";

                if (arc.TargetAddress >= 0)
                {
                    w.WriteLine($"  {nodeAddr} -> {arc.TargetAddress} [label=\"{edgeLabel}{extra}\", color={color}];");
                    VisitNode(lookup, arc.TargetAddress, visited, w);
                }
                else
                {
                    w.WriteLine($"  {nodeAddr} -> {(arc.IsFinal ? -1 : -2)} [label=\"{edgeLabel}{extra}\", color={color}];");
                }
            }
        }
    }
}
