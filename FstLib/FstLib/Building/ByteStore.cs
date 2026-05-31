using System;

namespace FstLib.Building
{
    /// <summary>
    /// Paged append-only byte buffer used during FST construction.
    /// Uses fixed-size 32 KB blocks (2^15 bytes) instead of a flat List&lt;byte&gt; to avoid
    /// large contiguous allocations and GC pressure on big FSTs.
    /// Supports random-access reads and in-place overwrites for back-patching arc targets.
    /// </summary>
    internal sealed class ByteStore
    {
        private const int PageBits = 15;
        private const int PageSize = 1 << PageBits;
        private const int PageMask = PageSize - 1;

        private byte[][] _blocks = new byte[16][];
        private int _blockCount;
        private int _posInBlock;
        private long _totalBytes;

        public ByteStore() => AllocBlock();

        public long Position => _totalBytes;

        public void WriteByte(byte b)
        {
            byte[] cur = _blocks[_blockCount - 1];
            cur[_posInBlock++] = b;
            _totalBytes++;
            if (_posInBlock == PageSize)
            {
                AllocBlock();
                _posInBlock = 0;
            }
        }

        public void WriteBytes(byte[] data)
        {
            int offset = 0;
            int remaining = data.Length;
            while (remaining > 0)
            {
                byte[] cur = _blocks[_blockCount - 1];
                int space = PageSize - _posInBlock;
                int chunk = Math.Min(remaining, space);
                Buffer.BlockCopy(data, offset, cur, _posInBlock, chunk);
                _posInBlock += chunk;
                offset += chunk;
                remaining -= chunk;
                _totalBytes += chunk;
                if (_posInBlock == PageSize)
                {
                    AllocBlock();
                    _posInBlock = 0;
                }
            }
        }

        public void WriteVLong(long v)
        {
            ulong uv = (ulong)v;
            while (uv >= 0x80)
            {
                WriteByte((byte)(uv | 0x80));
                uv >>= 7;
            }
            WriteByte((byte)uv);
        }

        public byte ReadByte(long pos)
        {
            int block = (int)(pos >> PageBits);
            int offset = (int)(pos & PageMask);
            return _blocks[block][offset];
        }

        public void SetByte(long pos, byte value)
        {
            int block = (int)(pos >> PageBits);
            int offset = (int)(pos & PageMask);
            _blocks[block][offset] = value;
        }

        public void OverwriteVLong(long pos, long value, int byteCount)
        {
            ulong uv = (ulong)value;
            for (int i = 0; i < byteCount - 1; i++)
            {
                SetByte(pos + i, (byte)((uv & 0x7F) | 0x80));
                uv >>= 7;
            }
            SetByte(pos + byteCount - 1, (byte)(uv & 0x7F));
        }

        public void WritePaddedVLong(long value, int byteCount)
        {
            ulong uv = (ulong)value;
            for (int i = 0; i < byteCount - 1; i++)
            {
                WriteByte((byte)((uv & 0x7F) | 0x80));
                uv >>= 7;
            }
            WriteByte((byte)(uv & 0x7F));
        }

        public byte[] ToArray()
        {
            var result = new byte[_totalBytes];
            long remaining = _totalBytes;
            int dest = 0;
            for (int b = 0; b < _blockCount; b++)
            {
                int len = (int)Math.Min(PageSize, remaining);
                Buffer.BlockCopy(_blocks[b], 0, result, dest, len);
                dest += len;
                remaining -= len;
            }
            return result;
        }

        /// <summary>
        /// Copies bytes from the store starting at <paramref name="pos"/> into <paramref name="dest"/>
        /// at offset <paramref name="offset"/>, for <paramref name="length"/> bytes.
        /// Uses Buffer.BlockCopy for efficiency across page boundaries.
        /// </summary>
        public void CopyTo(long pos, byte[] dest, int offset, int length)
        {
            long remaining = length;
            long srcPos = pos;
            int dstOffset = offset;

            while (remaining > 0)
            {
                int srcBlock = (int)(srcPos >> PageBits);
                int srcBlockOffset = (int)(srcPos & PageMask);
                int bytesInBlock = PageSize - srcBlockOffset;
                int chunk = (int)Math.Min(remaining, bytesInBlock);

                Buffer.BlockCopy(_blocks[srcBlock], srcBlockOffset, dest, dstOffset, chunk);
                srcPos += chunk;
                dstOffset += chunk;
                remaining -= chunk;
            }
        }

        private void AllocBlock()
        {
            if (_blockCount == _blocks.Length)
                Array.Resize(ref _blocks, _blocks.Length * 2);
            _blocks[_blockCount++] = new byte[PageSize];
            _posInBlock = 0;
        }
    }
}
