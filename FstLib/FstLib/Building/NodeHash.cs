using System;
using System.Runtime.CompilerServices;

namespace FstLib.Building
{
    /// <summary>
    /// Deduplicates compiled nodes by hashing the raw bytes they produced in the ByteStore.
    /// Avoids all string allocation — operates entirely on the byte representation.
    /// Uses open-addressing with linear probing (load factor ≤ 0.5).
    ///
    /// RAM-limited: when estimated memory exceeds <paramref name="maxRamBytes"/>, the
    /// oldest entries (by insertion epoch) are evicted to keep memory bounded.
    /// </summary>
    internal sealed class NodeHash
    {
        private long[] _hashes;
        private long[] _addrs;
        private int[] _epochs;
        private int _count;
        private int _mask;
        private int _nextEpoch;
        private readonly int _maxRamBytes;
        private int _initialCapacity;

        public NodeHash(int initialCapacity = 256, int maxRamBytes = 16 * 1024 * 1024)
        {
            _initialCapacity = NextPow2(Math.Max(initialCapacity, 4));
            int cap = _initialCapacity;
            _maxRamBytes = maxRamBytes;
            _hashes = new long[cap];
            _addrs = new long[cap];
            _epochs = new int[cap];
            _mask = cap - 1;
        }

        public int EstimatedRamBytes =>
            (_hashes.Length * 8 + _addrs.Length * 8 + _epochs.Length * 4) + 64;

        /// <summary>
        /// Find a previously stored node whose bytes match store[nodeStart..nodeEnd].
        /// </summary>
        public long Find(long contentHash, ByteStore store, long nodeStart, long nodeEnd)
        {
            long len = nodeEnd - nodeStart;
            int slot = Slot(contentHash);
            while (_hashes[slot] != 0)
            {
                if (_hashes[slot] == contentHash &&
                    ByteRangeEquals(store, nodeStart, nodeEnd, _addrs[slot], len))
                    return _addrs[slot];
                slot = (slot + 1) & _mask;
            }
            return -1L;
        }

        /// <summary>
        /// Find a previously stored node whose bytes match <paramref name="candidate"/>[0..<paramref name="len"/>).
        /// The candidate is already in reversed format (ready to write). Comparisons iterate the
        /// candidate forward vs. stored bytes at [bEnd-len, bEnd).
        /// </summary>
        public long Find(long contentHash, byte[] candidate, long len, ByteStore store)
        {
            int slot = Slot(contentHash);
            while (_hashes[slot] != 0)
            {
                if (_hashes[slot] == contentHash &&
                    ByteRangeEquals(candidate, len, _addrs[slot], store))
                    return _addrs[slot];
                slot = (slot + 1) & _mask;
            }
            return -1L;
        }

        public void Add(long contentHash, long endAddress)
        {
            if (_count >= _hashes.Length / 2)
            {
                if (EstimatedRamBytes > _maxRamBytes && _hashes.Length > _initialCapacity)
                    EvictOldest();
                else
                    Grow();
            }
            int slot = Slot(contentHash);
            while (_hashes[slot] != 0)
                slot = (slot + 1) & _mask;
            _hashes[slot] = contentHash;
            _addrs[slot] = endAddress;
            _epochs[slot] = _nextEpoch++;
            _count++;
        }

        /// <summary>Evict approximately half the entries (the oldest by epoch).</summary>
        private void EvictOldest()
        {
            int cap = Math.Max(_initialCapacity, _hashes.Length / 2);
            int minEpoch = _nextEpoch;
            for (int i = 0; i < _hashes.Length; i++)
                if (_hashes[i] != 0 && _epochs[i] < minEpoch) minEpoch = _epochs[i];
            int threshold = _nextEpoch - (_nextEpoch - minEpoch) / 2;
            // simpler: keep entries with epoch > median
            var epochsCopy = new int[_count];
            int idx = 0;
            for (int i = 0; i < _hashes.Length; i++)
                if (_hashes[i] != 0) epochsCopy[idx++] = _epochs[i];
            Array.Sort(epochsCopy, 0, idx);
            int keepThreshold = epochsCopy[idx / 2];

            var newH = new long[cap];
            var newA = new long[cap];
            var newE = new int[cap];
            int newMask = cap - 1;
            int newCount = 0;
            for (int i = 0; i < _hashes.Length; i++)
            {
                if (_hashes[i] == 0 || _epochs[i] < keepThreshold) continue;
                int slot = (int)(_hashes[i] & newMask);
                while (newH[slot] != 0) slot = (slot + 1) & newMask;
                newH[slot] = _hashes[i];
                newA[slot] = _addrs[i];
                newE[slot] = _epochs[i];
                newCount++;
            }
            _hashes = newH;
            _addrs = newA;
            _epochs = newE;
            _mask = newMask;
            _count = newCount;
        }

        /// <summary>
        /// Compares reversed-format bytes. <paramref name="aStart"/> and <paramref name="aEnd"/>
        /// are the test range; <paramref name="bEnd"/> is the stored end address.
        /// Both ranges have length <paramref name="len"/>.
        /// Uses bulk copy and byte-by-byte comparison for compatibility.
        /// </summary>
        private static bool ByteRangeEquals(ByteStore store, long aStart, long aEnd, long bEnd, long len)
        {
            if (aEnd == bEnd) return true;
            
            // Bulk-copy both ranges into scratch buffers, then compare
            var aBuf = new byte[len];
            var bBuf = new byte[len];
            
            store.CopyTo(aStart, aBuf, 0, (int)len);
            store.CopyTo(bEnd - len, bBuf, 0, (int)len);
            
            for (int i = 0; i < len; i++)
                if (aBuf[i] != bBuf[i])
                    return false;
            return true;
        }

        /// <summary>
        /// Compares reversed-format bytes from a byte[] candidate with stored bytes.
        /// Candidate is [0..len), stored bytes are [storedEnd - len..storedEnd).
        /// </summary>
        private static bool ByteRangeEquals(byte[] candidate, long len, long storedEnd, ByteStore store)
        {
            long storedStart = storedEnd - len;
            for (long i = 0; i < len; i++)
                if (candidate[i] != store.ReadByte(storedStart + i))
                    return false;
            return true;
        }

        public static long ComputeHash(ByteStore store, long nodeStart, long nodeEnd)
        {
            ulong hash = 14695981039346656037UL;
            for (long p = nodeStart; p < nodeEnd; p++)
            {
                hash ^= store.ReadByte(p);
                hash *= 1099511628211UL;
            }
            long h = (long)hash;
            return h == 0 ? 1 : h;
        }

        public static long ComputeHash(byte[] data, long len)
        {
            ulong hash = 14695981039346656037UL;
            for (long i = 0; i < len; i++)
            {
                hash ^= data[i];
                hash *= 1099511628211UL;
            }
            long h = (long)hash;
            return h == 0 ? 1 : h;
        }

        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        private int Slot(long hash) => (int)(hash & _mask);

        private void Grow()
        {
            int newCap = _hashes.Length * 2;
            var newH = new long[newCap];
            var newA = new long[newCap];
            var newE = new int[newCap];
            int newMask = newCap - 1;
            for (int i = 0; i < _hashes.Length; i++)
            {
                if (_hashes[i] == 0) continue;
                int slot = (int)(_hashes[i] & newMask);
                while (newH[slot] != 0) slot = (slot + 1) & newMask;
                newH[slot] = _hashes[i];
                newA[slot] = _addrs[i];
                newE[slot] = _epochs[i];
            }
            _hashes = newH;
            _addrs = newA;
            _epochs = newE;
            _mask = newMask;
        }

        private static int NextPow2(int n)
        {
            n--;
            n |= n >> 1; n |= n >> 2; n |= n >> 4; n |= n >> 8; n |= n >> 16;
            return n + 1;
        }
    }
}
