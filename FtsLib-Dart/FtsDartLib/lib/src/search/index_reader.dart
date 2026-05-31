import 'dart:io';
import 'dart:typed_data';

import '../indexing/delete_set.dart';
import '../indexing/index_directory.dart';
import '../indexing/search_lease.dart';
import '../indexing/segment_handle.dart';
import 'concat_iterator.dart';
import 'filtering_iterator.dart';
import 'fuzzy_expander.dart';
import 'hebrew_wildcard_expander.dart';
import 'posting_intersector.dart';
import 'posting_iterator.dart';

/// Searches a segment-based index. Works at any point — mid-build or finalized.
/// Queries all live segment pairs (seg_L_ID.dat + seg_L_ID.db) and merges results.
///
/// Three search modes:
///   search(groups)  — Mixed AND/OR: each group is OR'd, all groups are AND'd
///   searchAnd(terms) — AND: all terms must appear
///   searchOr(terms)  — OR:  any term must appear
class IndexReader extends IndexDirectory {
  final List<SegmentHandle> _segments = [];
  final DeleteSet _deletes;
  final SearchLease? _lease;
  bool _disposed = false;

  IndexReader._(String indexPath, this._deletes, this._lease)
      : super(indexPath);

  /// Opens an IndexReader using an explicit snapshot of live segment paths,
  /// holding a [SearchLease] for the reader's entire lifetime.
  static Future<IndexReader> open(
    String indexPath,
    List<(String dat, String db)> livePaths,
    SearchLease? lease,
  ) async {
    final deletes = DeleteSet.load(
        '$indexPath${Platform.pathSeparator}deletes.bin');
    final reader = IndexReader._(indexPath, deletes, lease);

    if (livePaths.isEmpty) return reader;

    // Sort by segId so ConcatIterator sees doc IDs in ascending order.
    livePaths.sort((a, b) => _parseSegId(a.$1).compareTo(_parseSegId(b.$1)));

    for (final (dat, db) in livePaths) {
      if (File(dat).existsSync() && File(db).existsSync()) {
        reader._segments.add(await SegmentHandle.open(dat, db));
      }
    }

    return reader;
  }

  /// Opens an IndexReader by scanning the index directory for seg_*.dat files.
  /// Only use this when no SegmentStore is available.
  static Future<IndexReader> openFromDir(String indexPath) async {
    final deletes = DeleteSet.load(
        '$indexPath${Platform.pathSeparator}deletes.bin');
    final reader = IndexReader._(indexPath, deletes, null);

    final dir = Directory(indexPath);
    if (!dir.existsSync()) return reader;

    final datFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.dat') &&
            f.path.split(Platform.pathSeparator).last.startsWith('seg_'))
        .map((f) => f.path)
        .toList()
      ..sort((a, b) => _parseSegId(a).compareTo(_parseSegId(b)));

    for (final datFile in datFiles) {
      final dbFile = datFile.replaceAll('.dat', '.db');
      if (File(dbFile).existsSync()) {
        reader._segments.add(await SegmentHandle.open(datFile, dbFile));
      }
    }

    return reader;
  }

  static int _parseSegId(String path) {
    final name = path
        .split(Platform.pathSeparator)
        .last
        .replaceAll('.dat', '')
        .replaceAll('.db', '');
    final parts = name.split('_');
    return parts.length == 3 ? (int.tryParse(parts[2]) ?? 0) : 0;
  }

  // ── Wildcard expansion ────────────────────────────────────────

  Future<List<String>> expandWildcard(String pattern) =>
      HebrewWildcardExpander.expand(pattern, _segments);

  // ── Fuzzy expansion ───────────────────────────────────────────

  Future<List<String>> expandFuzzy(String term, int maxDistance) =>
      FuzzyExpander.expand(term, maxDistance, _segments);

  // ── Mixed AND/OR search ───────────────────────────────────────

  Iterable<int> search(
    Iterable<Iterable<String>> groups, {
    bool Function()? isCancelled,
  }) {
    if (_segments.isEmpty) return const [];
    return PostingIntersector.mixedSearch(
      groups,
      _resolveIterator,
      isCancelled: isCancelled,
    );
  }

  // ── AND search ───────────────────────────────────────────────

  Iterable<int> searchAnd(
    Iterable<String> terms, {
    bool Function()? isCancelled,
  }) {
    if (_segments.isEmpty) return const [];
    return PostingIntersector.andSearch(
      terms,
      _resolveIterator,
      _getTermCountSync,
      isCancelled: isCancelled,
    );
  }

  // ── OR search ────────────────────────────────────────────────

  Iterable<int> searchOr(
    Iterable<String> terms, {
    bool Function()? isCancelled,
  }) {
    if (_segments.isEmpty) return const [];
    return PostingIntersector.orSearch(
      terms,
      _resolveIterator,
      isCancelled: isCancelled,
    );
  }

  // ── Term count ───────────────────────────────────────────────

  Future<int> getTermCount(String term) async {
    int n = 0;
    for (final chunk in await _lookupTermAsync(term)) n += chunk.count;
    return n;
  }

  // Synchronous approximation used by andSearch for rarest-first sorting.
  // Returns 0 for unknown terms — acceptable since the sort is a hint only.
  int _getTermCountSync(String term) => 0;

  // ── Iterator resolution ───────────────────────────────────────

  /// Resolves a term to a [PostingIterator] by loading all its chunks from
  /// every live segment and concatenating them.
  ///
  /// This is the synchronous path used by the search algorithms.
  /// Chunk data is loaded synchronously via [RandomAccessFile.readSync].
  PostingIterator _resolveIterator(String term) {
    final chunks = _lookupTermSync(term);
    if (chunks.isEmpty) return PostingIterator.empty;

    PostingIterator iter;
    if (chunks.length == 1) {
      iter = _loadChunk(chunks[0]);
    } else {
      // Segments are flushed in doc ID order — ConcatIterator sequences them
      // end-to-end, producing a globally ascending stream.
      final iters = chunks.map(_loadChunk).toList();
      iter = ConcatIterator(iters);
    }

    return _deletes.isEmpty ? iter : FilteringIterator(iter, _deletes);
  }

  /// Synchronous term lookup across all segments.
  List<SegmentChunk> _lookupTermSync(String term) {
    final result = <SegmentChunk>[];
    for (final seg in _segments) {
      final chunk = seg.lookupTermSync(term);
      if (chunk != null) result.add(chunk);
    }
    return result;
  }

  /// Async term lookup — used by [getTermCount].
  Future<List<SegmentChunk>> _lookupTermAsync(String term) async {
    final result = <SegmentChunk>[];
    for (final seg in _segments) {
      final chunk = await seg.lookupTerm(term);
      if (chunk != null) result.add(chunk);
    }
    return result;
  }

  // ── Chunk loading ─────────────────────────────────────────────

  static PostingIterator _loadChunk(SegmentChunk chunk) {
    int skipBytes = chunk.skipCount * 3 * 4; // 12 bytes per entry
    int totalBytes = skipBytes + chunk.length;

    // Read the skip table + posting bytes in one seek+read.
    final raf = chunk.seg.dataStream;
    raf.setPositionSync(
        chunk.skipCount > 0 ? chunk.skipOffset : chunk.offset);

    // Read in a loop — RandomAccessFile.readSync may return fewer bytes.
    final buf = Uint8List(totalBytes);
    int read = 0;
    while (read < totalBytes) {
      final n = raf.readIntoSync(buf, read, totalBytes - read);
      if (n == 0) break; // end of stream — should never happen on a valid segment
      read += n;
    }

    // Deserialise skip table from the front of the buffer.
    List<int>? skip;
    int skipLen = 0;
    if (chunk.skipCount > 0) {
      skipLen = chunk.skipCount * 3;
      skip = List<int>.filled(skipLen, 0);
      for (int i = 0; i < skipLen; i++) {
        final off = i * 4;
        int v = buf[off] |
            (buf[off + 1] << 8) |
            (buf[off + 2] << 16) |
            (buf[off + 3] << 24);
        // Sign-extend
        skip[i] = v >= 0x80000000 ? v - 0x100000000 : v;
      }
    }

    // Posting bytes follow immediately after the skip table.
    final List<int> postBuf;
    if (skipBytes == 0) {
      postBuf = buf;
    } else {
      postBuf = buf.sublist(skipBytes, skipBytes + chunk.length);
    }

    return PostingIterator(postBuf, chunk.length, skip, skipLen);
  }

  // ── Dispose ──────────────────────────────────────────────────

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final seg in _segments) await seg.dispose();
    _segments.clear();
    // Release the search lease last — this unblocks any merge that was
    // waiting for the write lock while we held open segment file handles.
    _lease?.dispose();
  }
}
