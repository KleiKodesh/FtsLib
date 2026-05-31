import '../search/posting_intersector.dart';
import '../search/posting_iterator.dart';
import 'ram_index_entry.dart';

/// In-memory inverted index: maps each term to its PostingStream + skip list.
///
/// Search algorithms are provided by PostingIntersector — the same algorithms
/// used by IndexReader, so both index types behave identically.
class RamIndex {
  final Map<String, RamIndexEntry> _entries = {};
  final bool _useSkipList;

  RamIndex({bool useSkipList = true}) : _useSkipList = useSkipList;

  int get count => _entries.length;

  Iterable<MapEntry<String, RamIndexEntry>> get entries => _entries.entries;

  void add(String term, int lineId) {
    _entries.putIfAbsent(term, () => RamIndexEntry(useSkipList: _useSkipList))
        .add(lineId);
  }

  int getCount(String term) => _entries[term]?.stream.count ?? 0;

  PostingIterator getIterator(String term) {
    final e = _entries[term];
    if (e == null) return PostingIterator.empty;
    return PostingIterator(
      e.stream.buffer,
      e.stream.byteLength,
      e.skip,
      e.skipLen,
    );
  }

  // ── AND ──────────────────────────────────────────────────────

  Iterable<int> search(Iterable<String> terms) =>
      PostingIntersector.andSearch(terms, getIterator, getCount);

  // ── OR ───────────────────────────────────────────────────────

  Iterable<int> searchOr(Iterable<String> terms) =>
      PostingIntersector.orSearch(terms, getIterator);

  // ── Mixed AND/OR ─────────────────────────────────────────────

  Iterable<int> searchMixed(Iterable<Iterable<String>> groups) =>
      PostingIntersector.mixedSearch(groups, getIterator);
}
