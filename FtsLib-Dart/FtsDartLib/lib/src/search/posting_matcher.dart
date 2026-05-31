import 'posting_iterator.dart';

/// Reusable merge algorithms over PostingIterator sequences.
/// Both RamIndex and IndexReader delegate here so the logic lives in one place.
class PostingMatcher {
  // ── AND merge ────────────────────────────────────────────────

  /// Skip-list-accelerated AND intersection.
  /// Precondition: all iterators have already been advanced once (moveNext called,
  /// returned true). iters[0] is the rarest (smallest) list — it drives the loop.
  static Iterable<int> intersect(
    List<PostingIterator> iters, {
    bool Function()? isCancelled,
  }) sync* {
    while (!iters[0].isDone) {
      if (isCancelled != null && isCancelled()) return;

      int candidate = iters[0].current;
      bool match = true;

      for (int i = 1; i < iters.length; i++) {
        if (!iters[i].skipTo(candidate)) return;

        if (iters[i].current != candidate) {
          int newTarget = iters[i].current;
          if (!iters[0].skipTo(newTarget)) return;
          match = false;
          break;
        }
      }

      if (match) {
        yield candidate;
        if (!iters[0].moveNext()) return;
      }
    }
  }

  // ── OR merge (min-heap) ──────────────────────────────────────

  /// Min-heap OR union: yields every doc ID that appears in at least one iterator,
  /// in ascending order with no duplicates.
  /// Precondition: all iterators have already been advanced once.
  /// O(n log k) where n = total postings, k = number of iterators.
  static Iterable<int> union(
    List<PostingIterator> iters, {
    bool Function()? isCancelled,
  }) sync* {
    int heapSize = iters.length;
    final List<int> heap = List<int>.generate(heapSize, (i) => i);
    for (int i = heapSize ~/ 2 - 1; i >= 0; i--) {
      _siftDown(heap, iters, i, heapSize);
    }

    int lastYielded = -2147483648;

    while (heapSize > 0) {
      if (isCancelled != null && isCancelled()) return;

      int topIdx = heap[0];
      int val = iters[topIdx].current;

      if (val != lastYielded) {
        yield val;
        lastYielded = val;
      }

      if (iters[topIdx].moveNext()) {
        _siftDown(heap, iters, 0, heapSize);
      } else {
        heapSize--;
        if (heapSize > 0) {
          heap[0] = heap[heapSize];
          _siftDown(heap, iters, 0, heapSize);
        }
      }
    }
  }

  // ── Heap helper ──────────────────────────────────────────────

  static void _siftDown(
      List<int> heap, List<PostingIterator> iters, int i, int size) {
    while (true) {
      int smallest = i;
      int left = (i << 1) + 1;
      int right = left + 1;

      if (left < size &&
          iters[heap[left]].current < iters[heap[smallest]].current) {
        smallest = left;
      }
      if (right < size &&
          iters[heap[right]].current < iters[heap[smallest]].current) {
        smallest = right;
      }

      if (smallest == i) break;

      int tmp = heap[i];
      heap[i] = heap[smallest];
      heap[smallest] = tmp;
      i = smallest;
    }
  }
}
