import 'posting_iterator.dart';
import 'roaring_bitmap.dart';

/// Wraps a [RoaringBitmap] as a [PostingIterator] so that a materialised
/// OR-union result can be fed directly into [PostingMatcher.intersect] without
/// changing any of the AND intersection logic.
class RoaringBitmapIterator extends PostingIterator {
  final Iterator<int> _enumerator;
  bool _started = false;
  bool _done = false;
  int _current = 0;

  @override
  int get current => _current;

  @override
  bool get isDone => _done;

  RoaringBitmapIterator(RoaringBitmap bitmap)
      : _enumerator = bitmap.getValues().iterator,
        super(const [], 0, null, 0);

  @override
  bool moveNext() {
    if (_done) return false;
    _started = true;
    if (_enumerator.moveNext()) {
      _current = _enumerator.current;
      return true;
    }
    _done = true;
    return false;
  }

  @override
  bool skipTo(int target) {
    if (_done) return false;
    if (!_started && !moveNext()) return false;
    while (_current < target) {
      if (!moveNext()) return false;
    }
    return true;
  }

  @override
  Iterable<int> asEnumerable() sync* {
    while (moveNext()) yield current;
  }
}
