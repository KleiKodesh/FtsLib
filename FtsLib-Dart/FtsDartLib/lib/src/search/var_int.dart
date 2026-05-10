/// Little-endian base-128 varint codec.
/// Each byte holds 7 data bits; the high bit signals "more bytes follow".
/// A uint encodes in at most 5 bytes.
/// All methods are static and allocation-free.
class VarInt {
  // ── Write ─────────────────────────────────────────────────────

  /// Writes a varint by invoking [writeByte] for each byte.
  /// Used by PostingStream which manages its own growable buffer.
  static void write(int v, void Function(int) writeByte) {
    int u = v & 0xFFFFFFFF;
    while (u >= 0x80) {
      writeByte((u | 0x80) & 0xFF);
      u >>= 7;
    }
    writeByte(u & 0xFF);
  }

  /// Encodes a varint into [buf] starting at index 0.
  /// Returns the number of bytes written (1–5).
  static int encode(int v, List<int> buf) {
    int u = v & 0xFFFFFFFF;
    int i = 0;
    while (u >= 0x80) {
      buf[i++] = (u | 0x80) & 0xFF;
      u >>= 7;
    }
    buf[i++] = u & 0xFF;
    return i;
  }

  // ── Read ──────────────────────────────────────────────────────

  /// Decodes a varint from [buf] at [pos[0]], advancing [pos[0]] past the
  /// bytes consumed. [pos] is a single-element list used as a mutable reference.
  static int read(List<int> buf, List<int> pos, int len) {
    int shift = 0;
    int result = 0;
    while (pos[0] < len) {
      int b = buf[pos[0]++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return result & 0xFFFFFFFF;
  }
}
