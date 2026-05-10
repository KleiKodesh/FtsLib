import '../indexing/delete_set.dart';
import 'posting_iterator.dart';

/// Wraps a [PostingIterator] and skips any doc ID that appears in a [DeleteSet].
///
/// Used by IndexReader when the delete set is non-empty. When the delete set is
/// empty, IndexReader uses the raw iterator directly — zero overhead on the
/// common path.
///
/// Allocation: one object per term per query. No per-doc allocation.
class FilteringIterator extends PostingIterator {
  final PostingIterator _inner;
  final DeleteSet _deletes;
  bool _done = false;
  int _current = 0;

  @override
  int get current => _current;

  @override
  bool get isDone => _done;

  FilteringIterator(this._inner, this._deletes)
      : super(const [], 0, null, 0);

  @override
  bool moveNext() {
    while (_inner.moveNext()) {
      if (!_deletes.contains(_inner.current)) {
        _current = _inner.current;
        return true;
      }
    }
    _done = true;
    return false;
  }

  @override
  bool skipTo(int target) {
    if (_done) return false;

    // Delegate the skip to the inner iterator for skip-list acceleration,
    // then advance past any deleted IDs at or after the target.
    if (!_inner.skipTo(target)) {
      _done = true;
      return false;
    }

    // Walk forward until we land on a non-deleted ID.
    while (_deletes.contains(_inner.current)) {
      if (!_inner.moveNext()) {
        _done = true;
        return false;
      }
    }
    _current = _inner.current;
    return true;
  }
}
