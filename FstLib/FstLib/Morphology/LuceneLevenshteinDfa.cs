// Ported from Lucene's LevenshteinAutomata.ParametricDescription,
// Lev1ParametricDescription, and Lev2ParametricDescription.
// The transition tables are auto-generated data; splitting them would obscure
// the algorithm and make the port harder to verify against the Lucene source.
// Apache License 2.0 — see NOTICE.txt.

using System;

namespace FstLib.Morphology
{
    // Ported from Lucene's LevenshteinAutomata.ParametricDescription.
    internal abstract class ParametricDescription
    {
        protected readonly int w;
        protected readonly int n;
        private readonly int[] minErrors;

        protected ParametricDescription(int w, int n, int[] minErrors)
        {
            this.w = w;
            this.n = n;
            this.minErrors = minErrors;
        }

        public bool IsAccept(int absState)
        {
            int state  = absState / (w + 1);
            int offset = absState % (w + 1);
            return w - offset + minErrors[state] <= n;
        }

        // Returns the position (offset into the input word) for this abs state.
        public int GetPosition(int absState) => absState % (w + 1);

        public abstract int Transition(int absState, int position, int vector);

        // ── packed-bit helpers (mirrors Lucene's unpack) ──────────────
        // Tables are stored as ulong[] to avoid signed-overflow on large hex literals.
        private static readonly ulong[] Masks = new ulong[]
        {
            0x1UL, 0x3UL, 0x7UL, 0xfUL, 0x1fUL, 0x3fUL, 0x7fUL, 0xffUL,
            0x1ffUL, 0x3ffUL, 0x7ffUL, 0xfffUL, 0x1fffUL, 0x3fffUL, 0x7fffUL, 0xffffUL,
            0x1ffffUL, 0x3ffffUL, 0x7ffffUL, 0xfffffUL, 0x1fffffUL, 0x3fffffUL, 0x7fffffUL, 0xffffffUL,
            0x1ffffffUL, 0x3ffffffUL, 0x7ffffffUL, 0xfffffffUL, 0x1fffffffUL, 0x3fffffffUL,
            0x7fffffffUL, 0xffffffffUL
        };

        protected static int Unpack(ulong[] data, int index, int bitsPerValue)
        {
            long  bitLoc   = (long)bitsPerValue * index;
            int   dataLoc  = (int)(bitLoc >> 6);
            int   bitStart = (int)(bitLoc & 63);
            if (bitStart + bitsPerValue <= 64)
            {
                return (int)((data[dataLoc] >> bitStart) & Masks[bitsPerValue - 1]);
            }
            else
            {
                int part = 64 - bitStart;
                return (int)(((data[dataLoc] >> bitStart) & Masks[part - 1])
                           + ((data[dataLoc + 1] & Masks[bitsPerValue - part - 1]) << part));
            }
        }
    }

    // ── Levenshtein distance 1 ────────────────────────────────────────────────
    // Ported from Lucene's Lev1ParametricDescription (auto-generated).
    internal sealed class Lev1ParametricDescription : ParametricDescription
    {
        public Lev1ParametricDescription(int w)
            : base(w, 1, new int[] { 0, 1, 0, -1, -1 }) { }

        public override int Transition(int absState, int position, int vector)
        {
            int state  = absState / (w + 1);
            int offset = absState % (w + 1);

            if (position == w)
            {
                if (state < 2)
                {
                    int loc = vector * 2 + state;
                    offset += Unpack(OffsetIncrs0, loc, 1);
                    state   = Unpack(ToStates0,    loc, 2) - 1;
                }
            }
            else if (position == w - 1)
            {
                if (state < 3)
                {
                    int loc = vector * 3 + state;
                    offset += Unpack(OffsetIncrs1, loc, 1);
                    state   = Unpack(ToStates1,    loc, 2) - 1;
                }
            }
            else if (position == w - 2)
            {
                if (state < 5)
                {
                    int loc = vector * 5 + state;
                    offset += Unpack(OffsetIncrs2, loc, 2);
                    state   = Unpack(ToStates2,    loc, 3) - 1;
                }
            }
            else
            {
                if (state < 5)
                {
                    int loc = vector * 5 + state;
                    offset += Unpack(OffsetIncrs3, loc, 2);
                    state   = Unpack(ToStates3,    loc, 3) - 1;
                }
            }

            if (state == -1) return -1;
            return state * (w + 1) + offset;
        }

        // position == w  (1 vector × 2 states)
        private static readonly ulong[] ToStates0    = { 0x2UL };
        private static readonly ulong[] OffsetIncrs0 = { 0x0UL };

        // position == w-1  (2 vectors × 3 states)
        private static readonly ulong[] ToStates1    = { 0xa43UL };
        private static readonly ulong[] OffsetIncrs1 = { 0x38UL };

        // position == w-2  (4 vectors × 5 states)
        private static readonly ulong[] ToStates2    = { 0x4da292442420003UL };
        private static readonly ulong[] OffsetIncrs2 = { 0x5555528000UL };

        // position <= w-3  (8 vectors × 5 states)
        private static readonly ulong[] ToStates3    = { 0x14d0812112018003UL, 0xb1a29b46d48a49UL };
        private static readonly ulong[] OffsetIncrs3 = { 0x555555e80a0f0000UL, 0x5555UL };
    }

    // ── Levenshtein distance 2 ────────────────────────────────────────────────
    // Ported from Lucene's Lev2ParametricDescription (auto-generated).
    internal sealed class Lev2ParametricDescription : ParametricDescription
    {
        public Lev2ParametricDescription(int w)
            : base(w, 2, new int[]
            {
                0, 1, 2, 0, 1, -1, 0, -1, 0, -1, 0, -1, -1, -1, -1,
                -2, -1, -2, -1, -2, -1, -2, -2, -2, -2, -2, -2, -2, -2, -2
            }) { }

        public override int Transition(int absState, int position, int vector)
        {
            int state  = absState / (w + 1);
            int offset = absState % (w + 1);

            if (position == w)
            {
                if (state < 3)
                {
                    int loc = vector * 3 + state;
                    offset += Unpack(OffsetIncrs0, loc, 1);
                    state   = Unpack(ToStates0,    loc, 2) - 1;
                }
            }
            else if (position == w - 1)
            {
                if (state < 5)
                {
                    int loc = vector * 5 + state;
                    offset += Unpack(OffsetIncrs1, loc, 1);
                    state   = Unpack(ToStates1,    loc, 3) - 1;
                }
            }
            else if (position == w - 2)
            {
                if (state < 11)
                {
                    int loc = vector * 11 + state;
                    offset += Unpack(OffsetIncrs2, loc, 2);
                    state   = Unpack(ToStates2,    loc, 4) - 1;
                }
            }
            else if (position == w - 3)
            {
                if (state < 21)
                {
                    int loc = vector * 21 + state;
                    offset += Unpack(OffsetIncrs3, loc, 2);
                    state   = Unpack(ToStates3,    loc, 5) - 1;
                }
            }
            else if (position == w - 4)
            {
                if (state < 30)
                {
                    int loc = vector * 30 + state;
                    offset += Unpack(OffsetIncrs4, loc, 3);
                    state   = Unpack(ToStates4,    loc, 5) - 1;
                }
            }
            else
            {
                if (state < 30)
                {
                    int loc = vector * 30 + state;
                    offset += Unpack(OffsetIncrs5, loc, 3);
                    state   = Unpack(ToStates5,    loc, 5) - 1;
                }
            }

            if (state == -1) return -1;
            return state * (w + 1) + offset;
        }

        // position == w  (1 vector × 3 states)
        private static readonly ulong[] ToStates0    = { 0xeUL };
        private static readonly ulong[] OffsetIncrs0 = { 0x0UL };

        // position == w-1  (2 vectors × 5 states)
        private static readonly ulong[] ToStates1    = { 0x1a688a2cUL };
        private static readonly ulong[] OffsetIncrs1 = { 0x3e0UL };

        // position == w-2  (4 vectors × 11 states)
        private static readonly ulong[] ToStates2 =
        {
            0x3a07603570707054UL, 0x522323232103773aUL, 0x352254543213UL
        };
        private static readonly ulong[] OffsetIncrs2 =
        {
            0x5555520880080000UL, 0x555555UL
        };

        // position == w-3  (8 vectors × 21 states)
        private static readonly ulong[] ToStates3 =
        {
            0x7000a560180380a4UL, 0xc015a0180a0194aUL,  0x8032c58318a301c0UL, 0x9d8350d403980318UL,
            0x3006028ca73a8602UL, 0xc51462640b21a807UL, 0x2310c4100c62194eUL, 0xce35884218ce248dUL,
            0xa9285a0691882358UL, 0x1046b5a86b1252b5UL, 0x2110a33892521483UL, 0xe62906208d63394eUL,
            0xd6a29c4921d6a4a0UL, 0x1aUL
        };
        private static readonly ulong[] OffsetIncrs3 =
        {
            0xf0c000c8c0080000UL, 0xca808822003f303UL,  0x5555553fa02f0880UL,
            0x5555555555555555UL, 0x5555555555555555UL, 0x5555UL
        };

        // position == w-4  (16 vectors × 30 states)
        private static readonly ulong[] ToStates4 =
        {
            0x7000a560180380a4UL, 0xa000000280e0294aUL, 0x6c0b00e029000000UL, 0x8c4350c59cdc6039UL,
            0x600ad00c03380601UL, 0x2962c18c5180e00UL,  0x18c4000c6028c4UL,   0x8a314603801802b4UL,
            0x6328c4520c59c5UL,   0x60d43500e600c651UL, 0x280e339cea180a7UL,  0x4039800000a318c6UL,
            0xd57be96039ec3d0dUL, 0xc0338d6358c4352UL,  0x28c4c81643500e60UL, 0x3194a028c4339d8aUL,
            0x590d403980018c4UL,  0xc4522d57b68e3132UL, 0xc4100c6510d6538UL,  0x9884218ce248d231UL,
            0x318ce318c6398d83UL, 0xa3609c370c431046UL, 0xea3ad6958568f7beUL, 0x2d0348c411d47560UL,
            0x9ad43989295ad494UL, 0x3104635ad431ad63UL, 0x8f73a6b5250b40d2UL, 0x57350eab9d693956UL,
            0x8ce24948520c411dUL, 0x294a398d85608442UL, 0x5694831046318ce5UL, 0x958460f7b623609cUL,
            0xc411d475616258d6UL, 0x9243ad4941cc520UL,  0x5ad4529ce39ad456UL, 0xb525073148310463UL,
            0x27656939460f7358UL, 0x1d573516UL
        };
        private static readonly ulong[] OffsetIncrs4 =
        {
            0x610600010000000UL,  0x2040000000001000UL, 0x1044209245200UL,    0x80d86d86006d80c0UL,
            0x2001b6030000006dUL, 0x8200011b6237237UL,  0x12490612400410UL,   0x2449001040208000UL,
            0x4d80820001044925UL, 0x6da4906da400UL,     0x9252369001360208UL, 0x24924924924911b6UL,
            0x9249249249249249UL, 0x4924924924924924UL, 0x2492492492492492UL, 0x9249249249249249UL,
            0x4924924924924924UL, 0x2492492492492492UL, 0x9249249249249249UL, 0x4924924924924924UL,
            0x2492492492492492UL, 0x9249249249249249UL, 0x24924924UL
        };

        // position <= w-5  (32 vectors × 30 states)
        private static readonly ulong[] ToStates5 =
        {
            0x7000a560180380a4UL, 0xa000000280e0294aUL, 0x580600e029000000UL, 0x80e0600e529c0029UL,
            0x380a418c6388c631UL, 0x316737180e5b02c0UL, 0x300ce01806310d4UL,  0xc60396c0b00e0290UL,
            0xca328c4350c59cdUL,  0x80e00600ad194656UL, 0x28c402962c18c51UL,  0x802b40018c4000c6UL,
            0xe58b06314603801UL,  0x8d6b48c6b580e348UL, 0x28c5180e00600ad1UL, 0x18ca31148316716UL,
            0x3801802b4031944UL,  0xc4520c59c58a3146UL, 0xe61956748cab38UL,   0x39cea180a760d435UL,
            0xa318c60280e3UL,     0x6029d8350d403980UL, 0x6b5a80e060d873a8UL, 0xf43500e618c638dUL,
            0x10d4b55efa580e7bUL, 0x3980300ce358d63UL,  0x57be96039ec3d0d4UL, 0x4656567598c4352dUL,
            0x8c4c81643500e619UL, 0x194a028c4339d8a2UL, 0x590d403980018c43UL, 0xe348d87628a31320UL,
            0xe618d6b4d6b1880UL,  0x5eda38c4c8164350UL, 0x19443594e31148b5UL, 0x31320590d4039803UL,
            0x7160c4522d57b68eUL, 0xd2310c41195674d6UL, 0x8d839884218ce248UL, 0x1046318ce318c639UL,
            0x2108633892348c43UL, 0xdebfbdef0f63b0f6UL, 0xd8270dc310c41f7bUL, 0x8eb5a5615a3defa8UL,
            0x70c43104751d583aUL, 0x58568f7bea3609c3UL, 0x41f77ddb7bbeed69UL, 0x9295ad4942d0348cUL,
            0xad431ad639ad4398UL, 0x5250b40d23104635UL, 0xce0f6bd0f624a56bUL, 0x348c41f7b9cd7bdUL,
            0xe55a3dce9ad4942dUL, 0x4755cd43aae75a4UL,  0x73a6b5250b40d231UL, 0xbd7bbcdd6939568fUL,
            0xe24948520c41f779UL, 0x4a398d856084428cUL, 0x14831046318ce529UL, 0xb16c2110a3389252UL,
            0x1f7bdebe739c8f63UL, 0xed88d82715a520c4UL, 0x58589635a561183dUL, 0x9c569483104751dUL,
            0xc56958460f7b6236UL, 0x520c41f77ddb6719UL, 0x45609243ad4941ccUL, 0x4635ad4529ce39adUL,
            0x90eb525073148310UL, 0xd6737b8f6bd16c24UL, 0x941cc520c41f7b9cUL, 0x95a4e5183dcd62d4UL,
            0x483104755cd4589dUL, 0x460f7358b5250731UL, 0xf779bd6717b56939UL
        };
        private static readonly ulong[] OffsetIncrs5 =
        {
            0x610600010000000UL,  0x40000000001000UL,   0xb6d56da184180UL,    0x824914800810000UL,
            0x2002040000000411UL, 0xc0000b2c5659245UL,  0x6d80d86d86006d8UL,  0x1b61801b60300000UL,
            0x6d80c0000b5b76b6UL, 0x46d88dc8dc800UL,    0x6372372001b60300UL, 0x400410082000b1b7UL,
            0x2080000012490612UL, 0x6d49241849001040UL, 0x912400410082000bUL, 0x402080004112494UL,
            0xb2c49252449001UL,   0x4906da4004d80820UL, 0x136020800006daUL,   0x82000b5b69241b69UL,
            0x6da4948da4004d80UL, 0x3690013602080004UL, 0x49249249b1b69252UL, 0x2492492492492492UL,
            0x9249249249249249UL, 0x4924924924924924UL, 0x2492492492492492UL, 0x9249249249249249UL,
            0x4924924924924924UL, 0x2492492492492492UL, 0x9249249249249249UL, 0x4924924924924924UL,
            0x2492492492492492UL, 0x9249249249249249UL, 0x4924924924924924UL, 0x2492492492492492UL,
            0x9249249249249249UL, 0x4924924924924924UL, 0x2492492492492492UL, 0x9249249249249249UL,
            0x4924924924924924UL, 0x2492492492492492UL, 0x9249249249249249UL, 0x4924924924924924UL,
            0x2492492492492492UL
        };
    }
}
