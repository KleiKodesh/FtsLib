import 'var_int.dart';

/// Compressed posting list for a single term.
/// Stores delta+varint encoded doc IDs in a raw byte list.
/// IDs must be added in strictly ascending order.
class PostingStream {
  List<int> _buf = List<int>.filled(8, 0, growable: true);
  int _len = 0;
  int _count = 0;
  int _last = 0;
  int _lastEncoded = 0;
  bool _hasLast = false;

  int get byteLength => _len;
  int get count => _count;
  // Always return as uint32 — matches the C# uint field.
  int get lastEncoded => _lastEncoded & 0xFFFFFFFF;
  List<int> get buffer => _buf;

  /// Byte offset at which the next add will write — used by skip list.
  int get nextByteOffset => _len;

  // encode: treat v as signed 32-bit, shift to unsigned range
  static int _encode(int v) => (v - (-2147483648)) & 0xFFFFFFFF;

  void add(int entryId) {
    if (_hasLast && entryId <= _last) {
      throw ArgumentError(
          'IDs must be strictly ascending. Got $entryId after $_last.');
    }

    int encoded = _encode(entryId);
    int toWrite = _hasLast ? (encoded - _lastEncoded) & 0xFFFFFFFF : encoded;

    _last = entryId;
    _lastEncoded = encoded;
    _hasLast = true;
    _count++;

    VarInt.write(toWrite, _writeByte);
  }

  void reset() {
    _len = 0;
    _count = 0;
    _hasLast = false;
    _lastEncoded = 0;
  }

  void _writeByte(int b) {
    if (_len == _buf.length) {
      final newBuf = List<int>.filled(_buf.length * 2, 0, growable: true);
      for (int i = 0; i < _len; i++) newBuf[i] = _buf[i];
      _buf = newBuf;
    }
    _buf[_len++] = b;
  }
}
