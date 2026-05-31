import 'posting_iterator.dart';

/// Sequences multiple PostingIterators end-to-end.
/// Doc IDs are globally ascending across segments (flush order = index order),
/// so simple sequencing produces a valid sorted posting list.
class ConcatIterator extends PostingIterator {
  final List<PostingIterator> _iters;
  int _idx = 0;
  bool _exhausted = false;

  @override
  int get current => _exhausted ? 0 : _iters[_idx].current;

  @override
  bool get isDone => _exhausted;

  ConcatIterator(this._iters) : super(const [], 0, null, 0);

  @override
  bool moveNext() {
    if (_exhausted) return false;
    while (_idx < _iters.length) {
      if (_iters[_idx].moveNext()) return true;
      _idx++;
    }
    _exhausted = true;
    return false;
  }

  @override
  bool skipTo(int target) {
    if (_exhausted) return false;
    while (_idx < _iters.length) {
      if (_iters[_idx].isDone) { _idx++; continue; }
      if (_iters[_idx].skipTo(target)) return true;
      _idx++;
    }
    _exhausted = true;
    return false;
  }

  @override
  Iterable<int> asEnumerable() sync* {
    while (moveNext()) yield current;
  }
}
