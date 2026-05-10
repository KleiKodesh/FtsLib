import 'dart:io';

/// Thread-safe registry of which segment files are live at each LSM level.
///
/// Owns:
///   - the level → segId sets
///   - the segment ID counter
///   - path helpers (segDatPath / segDbPath)
///   - rebuildFromDisk (called once during crash recovery)
///   - all mutations: addToLive, removeFromLive, promoteSegment, ensureLevel
///   - all queries: liveSegCount, totalLiveSegs, getLevelsWithMultiple,
///     getLiveSegIds, getLiveSegmentPaths
///
/// Note: Dart is single-threaded (isolate model), so the lock in the C# version
/// is not needed here. All access is safe within a single isolate.
class SegmentLiveState {
  final String _dir;

  List<int> _levelCount = List<int>.filled(4, 0, growable: true);
  int _nextSegId = 0;

  // level → set of live segIds
  final Map<int, Set<int>> _liveSegs = {};

  SegmentLiveState(this._dir);

  // ── Path helpers ─────────────────────────────────────────────

  String segDatPath(int level, int segId) =>
      '$_dir${Platform.pathSeparator}seg_${level}_$segId.dat';

  String segDbPath(int level, int segId) =>
      '$_dir${Platform.pathSeparator}seg_${level}_$segId.db';

  // ── ID counter ───────────────────────────────────────────────

  int nextSegId() => _nextSegId++;

  // ── Queries ──────────────────────────────────────────────────

  int liveSegCount(int level) => _liveSegs[level]?.length ?? 0;

  int totalLiveSegs() {
    int n = 0;
    for (final s in _liveSegs.values) n += s.length;
    return n;
  }

  /// Returns all level numbers that currently have more than one live segment.
  List<int> getLevelsWithMultiple() {
    final result = <int>[];
    for (final kv in _liveSegs.entries) {
      if (kv.value.length >= 2) result.add(kv.key);
    }
    return result;
  }

  List<int> getLiveSegIds(int level) {
    final set = _liveSegs[level];
    if (set == null) return [];
    return List<int>.from(set);
  }

  /// Returns all live (datPath, dbPath) pairs across every level.
  List<(String dat, String db)> getLiveSegmentPaths() {
    final result = <(String, String)>[];
    for (final kv in _liveSegs.entries) {
      for (final sid in kv.value) {
        result.add((segDatPath(kv.key, sid), segDbPath(kv.key, sid)));
      }
    }
    return result;
  }

  // ── Mutations ────────────────────────────────────────────────

  void addToLive(int level, int segId) => _addToLiveUnlocked(level, segId);

  void removeFromLive(int level, int segId) {
    final set = _liveSegs[level];
    if (set != null) {
      set.remove(segId);
      _ensureLevelCount(level, set.length);
    }
  }

  void promoteSegment(int srcLevel, List<int> removed, int dstLevel, int newSegId) {
    final src = _liveSegs[srcLevel];
    if (src != null) {
      src.removeAll(removed);
      _ensureLevelCount(srcLevel, src.length);
    }
    _addToLiveUnlocked(dstLevel, newSegId);
  }

  void ensureLevel(int level) => _ensureLevelUnlocked(level);

  // ── Recovery ─────────────────────────────────────────────────

  /// Scans the segment directory and rebuilds live state from the files on disk.
  /// Must be called before any background tasks start.
  void rebuildFromDisk({int maxSegId = -1}) {
    _liveSegs.clear();
    _nextSegId = 0;

    final dir = Directory(_dir);
    if (!dir.existsSync()) return;

    for (final file in dir.listSync().whereType<File>()) {
      final name = file.path
          .split(Platform.pathSeparator)
          .last
          .replaceAll('.dat', '');
      if (!name.startsWith('seg_')) continue;
      final parts = name.split('_');
      if (parts.length != 3) continue;
      final level = int.tryParse(parts[1]);
      final segId = int.tryParse(parts[2]);
      if (level == null || segId == null) continue;
      if (!file.path.endsWith('.dat')) continue;

      _addToLiveUnlocked(level, segId);
      if (segId >= _nextSegId) _nextSegId = segId + 1;
    }

    if (maxSegId >= _nextSegId) _nextSegId = maxSegId + 1;

    if (_liveSegs.isNotEmpty) {
      print('[Recovery] Found ${totalLiveSegs()} segment(s), nextSegId=$_nextSegId');
    }
  }

  // ── Private ──────────────────────────────────────────────────

  void _addToLiveUnlocked(int level, int segId) {
    _liveSegs.putIfAbsent(level, () => {}).add(segId);
    _ensureLevelUnlocked(level);
    _ensureLevelCount(level, _liveSegs[level]!.length);
  }

  void _ensureLevelUnlocked(int level) {
    while (_levelCount.length <= level + 1) {
      _levelCount.add(0);
    }
  }

  void _ensureLevelCount(int level, int count) {
    _ensureLevelUnlocked(level);
    _levelCount[level] = count;
  }
}
