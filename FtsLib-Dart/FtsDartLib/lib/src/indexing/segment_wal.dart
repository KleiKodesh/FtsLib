import 'dart:convert';
import 'dart:io';

/// Write-ahead log for crash recovery during segment merges.
///
/// Log format (one operation per line):
///   BEGIN_MERGE level=N sources=id1,id2,... target=id
///   END_MERGE   level=N target=id
///
/// Recovery rules:
///   - BEGIN_MERGE present, sources exist → target is partial; delete target, redo merge.
///   - BEGIN_MERGE present, sources gone, target exists → merge completed but END_MERGE
///     was not written; register target as live and write END_MERGE to close the WAL.
///   - BEGIN_MERGE present, sources gone, target missing → unrecoverable; wipe and rebuild.
///   - No BEGIN_MERGE (or matched END_MERGE) → nothing to recover.
///
/// Uses [RandomAccessFile] with [writeFromSync] + [flushSync] to guarantee each
/// log entry is on disk before the method returns — matching C#'s AutoFlush=true.
class SegmentWal {
  final String _walPath;
  RandomAccessFile? _writer;

  SegmentWal(String segmentsDir)
      : _walPath = '$segmentsDir${Platform.pathSeparator}wal.log';

  void open() {
    if (_writer != null) return;
    _writer = File(_walPath).openSync(mode: FileMode.writeOnlyAppend);
  }

  void close() {
    _writer?.closeSync();
    _writer = null;
  }

  void clear() {
    close();
    final f = File(_walPath);
    if (f.existsSync()) f.deleteSync();
  }

  // ── Write ─────────────────────────────────────────────────────

  void beginMerge(int level, List<int> sources, int target) {
    _writeLine(
        'BEGIN_MERGE level=$level sources=${sources.join(',')} target=$target');
  }

  void endMerge(int level, int target) {
    _writeLine('END_MERGE level=$level target=$target');
  }

  void _writeLine(String line) {
    final bytes = utf8.encode('$line\n');
    _writer!.writeFromSync(bytes);
    _writer!.flushSync();
  }

  // ── Analyze ───────────────────────────────────────────────────

  RecoveryState analyze() {
    final state = RecoveryState();
    final f = File(_walPath);
    if (!f.existsSync()) return state;

    for (final line in f.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;

      if (line.startsWith('BEGIN_MERGE ')) {
        final parts = _parseKV(line.substring('BEGIN_MERGE '.length));
        int level = int.parse(parts['level']!);
        int target = int.parse(parts['target']!);
        final sources =
            parts['sources']!.split(',').map(int.parse).toList();
        state.pendingMerge = MergeOp(level, sources, target);
      } else if (line.startsWith('END_MERGE ')) {
        state.pendingMerge = null;
      }
      // Legacy entries from old format — ignore safely
    }

    return state;
  }

  static Map<String, String> _parseKV(String s) {
    final result = <String, String>{};
    for (final pair in s.split(' ')) {
      if (pair.isEmpty) continue;
      int eq = pair.indexOf('=');
      if (eq > 0) result[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    return result;
  }
}

// ── Recovery state ────────────────────────────────────────────────

class RecoveryState {
  MergeOp? pendingMerge;
}

class MergeOp {
  final int level;
  final List<int> sources;
  final int target;

  MergeOp(this.level, this.sources, this.target);
}
