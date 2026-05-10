import 'dart:io';
import '../search/var_int.dart';

/// Lucene-style delete bitmap: a sorted set of doc IDs that have been logically
/// deleted from the index.
///
/// Persisted as a sorted varint-delta file (same codec as posting lists).
/// Loaded by both IndexReader (to filter search results) and SegmentMerger
/// (to purge deleted IDs permanently during merge).
class DeleteSet {
  final Set<int> _ids = {};

  int get count => _ids.length;
  bool get isEmpty => _ids.isEmpty;

  // ── Query ─────────────────────────────────────────────────────

  bool contains(int docId) => _ids.contains(docId);

  // ── Mutation ──────────────────────────────────────────────────

  void add(int docId) => _ids.add(docId);

  void clear() => _ids.clear();

  // ── Persistence ───────────────────────────────────────────────

  /// Writes the delete set to [path] as a sorted varint-delta stream.
  /// Creates or overwrites the file. Does nothing if the set is empty
  /// (removes the file if it exists).
  void save(String path) {
    if (_ids.isEmpty) {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      return;
    }

    final sorted = List<int>.from(_ids)..sort();

    final buf = List<int>.filled(sorted.length * 5, 0);
    final tmp = List<int>.filled(5, 0);
    int pos = 0;
    int prev = 0;

    for (final id in sorted) {
      // delta = (id - prev) + (int.maxValue + 1) to make it unsigned
      int delta = ((id - prev) + 2147483648) & 0xFFFFFFFF;
      int nBytes = VarInt.encode(delta, tmp);
      for (int i = 0; i < nBytes; i++) buf[pos++] = tmp[i];
      prev = id;
    }

    File(path).writeAsBytesSync(buf.sublist(0, pos));
  }

  /// Loads a previously saved delete set from [path].
  /// Returns an empty [DeleteSet] if the file does not exist.
  static DeleteSet load(String path) {
    final ds = DeleteSet();
    final f = File(path);
    if (!f.existsSync()) return ds;

    final buf = f.readAsBytesSync();
    final pos = [0];
    int len = buf.length;
    int prev = 0;

    while (pos[0] < len) {
      int delta = VarInt.read(buf, pos, len);
      // id = delta + prev - (int.maxValue + 1)
      int id = (delta + prev - 2147483648);
      ds._ids.add(id);
      prev = id;
    }

    return ds;
  }
}
