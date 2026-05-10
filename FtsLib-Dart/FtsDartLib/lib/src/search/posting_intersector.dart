import 'posting_iterator.dart';
import 'posting_matcher.dart';
import 'roaring_bitmap.dart';
import 'roaring_bitmap_iterator.dart';
import 'union_iterator.dart';

/// Search orchestration shared by RamIndex and IndexReader.
///
/// All three search modes (AND, OR, mixed AND/OR) are implemented here.
/// Callers supply two functions:
///   resolve  — term → PostingIterator (return PostingIterator.empty if missing)
///   getCount — term → doc count       (used to sort rarest-first for AND)
class PostingIntersector {
  /// Minimum number of OR-group terms that triggers the Roaring bitmap path.
  static const int roaringOrThreshold = 20;

  // ── AND ──────────────────────────────────────────────────────

  static Iterable<int> andSearch(
    Iterable<String> terms,
    PostingIterator Function(String) resolve,
    int Function(String) getCount, {
    bool Function()? isCancelled,
  }) sync* {
    final termList = List<String>.from(terms);
    if (termList.isEmpty) return;

    termList.sort((a, b) => getCount(a).compareTo(getCount(b)));
    yield* _andMerge(termList, resolve, isCancelled: isCancelled);
  }

  // ── OR ───────────────────────────────────────────────────────

  static Iterable<int> orSearch(
    Iterable<String> terms,
    PostingIterator Function(String) resolve, {
    bool Function()? isCancelled,
  }) sync* {
    final termList = List<String>.from(terms);

    if (termList.length >= roaringOrThreshold) {
      final roaringIter =
          _buildRoaringIterator(termList, resolve, isCancelled);
      if (!roaringIter.moveNext()) return;
      yield* _drainStarted(roaringIter, isCancelled: isCancelled);
      return;
    }

    final started = _startedIterators(termList, resolve, skipMissing: true);
    if (started.isEmpty) return;
    if (started.length == 1) {
      yield* _drainStarted(started[0], isCancelled: isCancelled);
      return;
    }
    yield* PostingMatcher.union(started, isCancelled: isCancelled);
  }

  // ── Mixed AND/OR ─────────────────────────────────────────────

  static Iterable<int> mixedSearch(
    Iterable<Iterable<String>> groups,
    PostingIterator Function(String) resolve, {
    bool Function()? isCancelled,
  }) sync* {
    final groupIters = <PostingIterator>[];

    for (final group in groups) {
      final termList = List<String>.from(group);
      if (termList.isEmpty) return;

      PostingIterator groupIter;

      if (termList.length >= roaringOrThreshold) {
        groupIter = _buildRoaringIterator(termList, resolve, isCancelled);
        if (groupIter.isDone) return;
        if (!groupIter.moveNext()) return;
      } else {
        final started =
            _startedIterators(termList, resolve, skipMissing: true);
        if (started.isEmpty) return;
        if (started.length == 1) {
          groupIter = started[0];
        } else {
          final union = UnionIterator(started);
          if (!union.moveNext()) continue;
          groupIter = union;
        }
      }

      groupIters.add(groupIter);
    }

    if (groupIters.isEmpty) return;
    if (groupIters.length == 1) {
      yield* _drainStarted(groupIters[0], isCancelled: isCancelled);
      return;
    }
    yield* PostingMatcher.intersect(groupIters, isCancelled: isCancelled);
  }

  // ── Helpers ──────────────────────────────────────────────────

  static RoaringBitmapIterator _buildRoaringIterator(
    List<String> terms,
    PostingIterator Function(String) resolve,
    bool Function()? isCancelled,
  ) {
    final bitmap = RoaringBitmap();
    for (final term in terms) {
      if (isCancelled != null && isCancelled()) break;
      final it = resolve(term);
      if (it.isDone) continue;
      while (it.moveNext()) bitmap.add(it.current);
    }
    return RoaringBitmapIterator(bitmap);
  }

  static Iterable<int> _andMerge(
    List<String> terms,
    PostingIterator Function(String) resolve, {
    bool Function()? isCancelled,
  }) sync* {
    final iters = <PostingIterator>[];
    for (final term in terms) {
      final it = resolve(term);
      if (it.isDone) return; // term not in index
      iters.add(it);
    }

    for (final it in iters) {
      if (!it.moveNext()) return;
    }

    yield* PostingMatcher.intersect(iters, isCancelled: isCancelled);
  }

  static List<PostingIterator> _startedIterators(
    Iterable<String> terms,
    PostingIterator Function(String) resolve, {
    required bool skipMissing,
  }) {
    final result = <PostingIterator>[];
    for (final term in terms) {
      final it = resolve(term);
      if (it.isDone) {
        if (!skipMissing) return [];
        continue;
      }
      if (it.moveNext()) result.add(it);
    }
    return result;
  }

  /// Yields all values from a pre-advanced iterator (current is already valid).
  static Iterable<int> _drainStarted(
    PostingIterator it, {
    bool Function()? isCancelled,
  }) sync* {
    do {
      if (isCancelled != null && isCancelled()) return;
      yield it.current;
    } while (it.moveNext());
  }
}
