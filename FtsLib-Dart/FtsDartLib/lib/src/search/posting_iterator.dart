import 'var_int.dart';

/// Forward-only iterator over a delta+varint compressed posting list.
/// Supports skip-list acceleration via skipTo.
class PostingIterator {
  static final PostingIterator empty = PostingIterator._empty();

  final List<int> _buf;
  final int _len;
  final List<int>? _skip;
  final int _skipLen;

  final List<int> _pos = [0]; // mutable position reference for VarInt.read
  int _encoded = 0;
  bool _started = false;
  bool _done = false;
  int _current = 0;

  int get current => _current;
  bool get isDone => _done;

  PostingIterator._empty()
      : _buf = const [],
        _len = 0,
        _skip = null,
        _skipLen = 0 {
    _done = true;
  }

  PostingIterator(List<int> buf, int len, List<int>? skip, int skipLen)
      : _buf = buf,
        _len = len,
        _skip = skip,
        _skipLen = skipLen;

  Iterable<int> asEnumerable() sync* {
    while (moveNext()) yield current;
  }

  bool moveNext() {
    if (_done) return false;
    if (!_started) {
      _started = true;
      if (_pos[0] >= _len) {
        _done = true;
        return false;
      }
      _encoded = _readVarInt();
      _current = _decode(_encoded);
      return true;
    }
    if (_pos[0] >= _len) {
      _done = true;
      return false;
    }
    _encoded = (_encoded + _readVarInt()) & 0xFFFFFFFF;
    _current = _decode(_encoded);
    return true;
  }

  bool skipTo(int target) {
    if (_done) return false;
    if (!_started && !moveNext()) return false;
    if (_current >= target) return true;

    if (_skip != null) {
      int bestOffset = -1;
      int bestPrevEncoded = 0;

      for (int i = 0; i < _skipLen; i += 3) {
        if (_skip![i] >= target) break;
        if (_skip![i + 1] > _pos[0]) {
          bestOffset = _skip![i + 1];
          bestPrevEncoded = _skip![i + 2];
        }
      }

      if (bestOffset > _pos[0]) {
        _pos[0] = bestOffset;
        // bestPrevEncoded is stored as int32 in the skip table; treat as uint32.
        _encoded =
            ((bestPrevEncoded & 0xFFFFFFFF) + _readVarInt()) & 0xFFFFFFFF;
        _current = _decode(_encoded);
        if (_current >= target) return true;
      }
    }

    while (_current < target) {
      if (_pos[0] >= _len) {
        _done = true;
        return false;
      }
      _encoded = (_encoded + _readVarInt()) & 0xFFFFFFFF;
      _current = _decode(_encoded);
    }
    return true;
  }

  int _readVarInt() => VarInt.read(_buf, _pos, _len);

  // decode: v is unsigned 32-bit; result = (long)v + int.MinValue
  // In Dart all ints are 64-bit, so this is exact.
  static int _decode(int v) => (v & 0xFFFFFFFF) - 2147483648;
}
