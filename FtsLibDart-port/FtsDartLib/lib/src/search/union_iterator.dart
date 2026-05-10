import 'posting_iterator.dart';

/// Wraps multiple PostingIterators into a single sorted, deduplicated iterator
/// using a min-heap. Implements the PostingIterator interface so it can be fed
/// directly into PostingMatcher.intersect for mixed AND/OR queries.
class UnionIterator extends PostingIterator {
  final List<PostingIterator> _iters;
  final List<int> _heap;
  int _heapSize = 0;
  bool _started = false;
  int _current = 0;
  bool _isDone = false;

  @override
  int get current => _current;

  @override
  bool get isDone => _isDone;

  UnionIterator(List<PostingIterator> iters)
      : _iters = iters,
        _heap = List<int>.filled(iters.length, 0),
        super(const [], 0, null, 0);

  @override
  bool moveNext() {
    if (_isDone) return false;

    if (!_started) {
      _started = true;
      // Sub-iterators are already pre-advanced by startedIterators.
      // Build the heap using current directly — do NOT call moveNext again.
      for (int i = 0; i < _iters.length; i++) {
        if (!_iters[i].isDone) _heap[_heapSize++] = i;
      }
      for (int i = _heapSize ~/ 2 - 1; i >= 0; i--) _siftDown(i);

      if (_heapSize == 0) {
        _isDone = true;
        return false;
      }
      _current = _iters[_heap[0]].current;
      return true;
    }

    // Advance all iterators currently sitting on _current (dedup)
    while (_heapSize > 0 && _iters[_heap[0]].current == _current) {
      int topIdx = _heap[0];
      if (_iters[topIdx].moveNext()) {
        _siftDown(0);
      } else {
        _heapSize--;
        if (_heapSize > 0) {
          _heap[0] = _heap[_heapSize];
          _siftDown(0);
        }
      }
    }

    if (_heapSize == 0) {
      _isDone = true;
      return false;
    }
    _current = _iters[_heap[0]].current;
    return true;
  }

  @override
  bool skipTo(int target) {
    if (_isDone) return false;
    if (!_started && !moveNext()) return false;
    if (_current >= target) return true;

    // Rebuild heap: skip all underlying iterators to target
    _heapSize = 0;
    for (int i = 0; i < _iters.length; i++) {
      if (_iters[i].isDone) continue;
      if (_iters[i].skipTo(target)) _heap[_heapSize++] = i;
    }
    for (int i = _heapSize ~/ 2 - 1; i >= 0; i--) _siftDown(i);

    if (_heapSize == 0) {
      _isDone = true;
      return false;
    }
    _current = _iters[_heap[0]].current;
    return true;
  }

  @override
  Iterable<int> asEnumerable() sync* {
    while (moveNext()) yield current;
  }

  void _siftDown(int i) {
    while (true) {
      int smallest = i;
      int left = (i << 1) + 1;
      int right = left + 1;

      if (left < _heapSize &&
          _iters[_heap[left]].current < _iters[_heap[smallest]].current) {
        smallest = left;
      }
      if (right < _heapSize &&
          _iters[_heap[right]].current < _iters[_heap[smallest]].current) {
        smallest = right;
      }

      if (smallest == i) break;
      int tmp = _heap[i];
      _heap[i] = _heap[smallest];
      _heap[smallest] = tmp;
      i = smallest;
    }
  }
}
