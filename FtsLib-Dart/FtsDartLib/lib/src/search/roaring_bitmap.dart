/// A 32-bit Roaring bitmap optimised for the OR-accumulation pattern used during
/// wildcard and fuzzy query expansion.
///
/// The 32-bit doc ID space is split into 65536 blocks of 65536 values each.
/// The high 16 bits of a doc ID select the block; the low 16 bits are the
/// position within the block.
///
/// Each block independently chooses its storage format:
///   ArrayContainer  — used when the block holds fewer than 4096 values.
///                     Stores the low-16 values as a sorted int list.
///                     Cost: ~8 bytes per value (Dart int).
///
///   BitmapContainer — used when the block holds 4096 or more values.
///                     Stores a flat 65536-bit array (1024 × int64).
///                     Cost: always 8 KB regardless of cardinality.
///
/// The crossover at 4096 matches the C# implementation.
///
/// Supports only: add(docId), getValues(), count.
class RoaringBitmap {
  static const int _promotionThreshold = 4096;

  final List<int> _keys = [];
  final List<_Container> _containers = [];

  int count = 0;

  // ── Mutation ──────────────────────────────────────────────────

  void add(int docId) {
    // Treat docId as uint32 — same as C# `(uint)docId`.
    final u    = docId & 0xFFFFFFFF;
    final high = (u >> 16) & 0xFFFF;
    final low  = u & 0xFFFF;

    int idx = _findKey(high);
    if (idx < 0) {
      idx = ~idx;
      _keys.insert(idx, high);
      final container = _ArrayContainer();
      container.add(low);
      _containers.insert(idx, container);
      count++;
      return;
    }

    final existing = _containers[idx];
    bool added;

    if (existing is _ArrayContainer) {
      added = existing.add(low);
      if (added && existing.cardinality == _promotionThreshold) {
        _containers[idx] = existing.toBitmapContainer();
      }
    } else {
      added = (existing as _BitmapContainer).add(low);
    }

    if (added) count++;
  }

  // ── Iteration ─────────────────────────────────────────────────

  Iterable<int> getValues() sync* {
    for (int b = 0; b < _keys.length; b++) {
      // Reconstruct the uint32 base, then convert back to signed int32.
      final baseU32 = _keys[b] << 16;
      for (final low in _containers[b].getValues()) {
        final u32 = (baseU32 | low) & 0xFFFFFFFF;
        // Convert uint32 back to signed int32 (same as C# (int)u32).
        yield u32 >= 0x80000000 ? u32 - 0x100000000 : u32;
      }
    }
  }

  // ── Binary search over sorted key list ────────────────────────

  int _findKey(int key) {
    int lo = 0, hi = _keys.length - 1;
    while (lo <= hi) {
      int mid = (lo + hi) >> 1;
      int k = _keys[mid];
      if (k == key) return mid;
      if (k < key) lo = mid + 1;
      else         hi = mid - 1;
    }
    return ~lo;
  }
}

// ── Container base ────────────────────────────────────────────

abstract class _Container {
  int get cardinality;
  bool add(int value);
  Iterable<int> getValues();
}

// ── Array container ───────────────────────────────────────────

/// Sorted list of low-16 values. Used when cardinality < 4096.
class _ArrayContainer extends _Container {
  List<int> _values = List<int>.filled(64, 0, growable: true);
  int _count = 0;

  @override
  int get cardinality => _count;

  @override
  bool add(int value) {
    // Binary search for insertion point.
    int lo = 0, hi = _count - 1;
    while (lo <= hi) {
      int mid = (lo + hi) >> 1;
      if (_values[mid] == value) return false; // duplicate
      if (_values[mid] < value) lo = mid + 1;
      else                      hi = mid - 1;
    }
    // lo is the insertion point.
    _ensureCapacity();
    for (int i = _count; i > lo; i--) {
      _values[i] = _values[i - 1];
    }
    _values[lo] = value;
    _count++;
    return true;
  }

  @override
  Iterable<int> getValues() sync* {
    for (int i = 0; i < _count; i++) yield _values[i];
  }

  _BitmapContainer toBitmapContainer() {
    final bm = _BitmapContainer();
    for (int i = 0; i < _count; i++) bm.add(_values[i]);
    return bm;
  }

  void _ensureCapacity() {
    if (_count < _values.length) return;
    int newSize = (_values.length * 2).clamp(0, RoaringBitmap._promotionThreshold);
    final newBuf = List<int>.filled(newSize, 0, growable: true);
    for (int i = 0; i < _count; i++) newBuf[i] = _values[i];
    _values = newBuf;
  }
}

// ── Bitmap container ──────────────────────────────────────────

/// 65536-bit flat bitset stored as 1024 int64 words.
/// Used when cardinality >= 4096.
///
/// NOTE: Dart ints are 64-bit signed. Bit 63 of each word is the sign bit.
/// We use `>>>` (unsigned right shift) for iteration to avoid sign-bit issues,
/// and a conditional for the mask when setting bit 63.
class _BitmapContainer extends _Container {
  // 1024 words × 64 bits = 65536 bits total.
  final List<int> _bits = List<int>.filled(1024, 0);
  int _cardinality = 0;

  @override
  int get cardinality => _cardinality;

  @override
  bool add(int value) {
    // value is always in [0, 65535] — low 16 bits of a doc ID.
    final word = value >> 6;
    final bit  = value & 63;
    // 1 << 63 is negative in Dart's signed 64-bit ints, so handle it specially.
    final mask = bit < 63 ? (1 << bit) : (1 << 62) << 1;
    if ((_bits[word] & mask) != 0) return false;
    _bits[word] |= mask;
    _cardinality++;
    return true;
  }

  @override
  Iterable<int> getValues() sync* {
    for (int word = 0; word < 1024; word++) {
      final w = _bits[word];
      if (w == 0) continue;
      final basePos = word << 6;
      // Use unsigned right shift (>>>) to iterate set bits safely.
      for (int bit = 0; bit < 64; bit++) {
        if ((w >>> bit) & 1 != 0) yield basePos + bit;
      }
    }
  }
}
