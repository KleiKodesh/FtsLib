import 'dart:io';

import '../indexing/corrupt_index_exception.dart';
import '../indexing/index_writer.dart';
import '../indexing/segment_store.dart';
import '../tokenization/tokenizer.dart';
import 'zayit_db.dart';

/// Builds the full-text index from the seforim SQLite database.
/// Streams every line through the tokenizer and writes term/docId pairs
/// to the index in strictly ascending ID order (required by the codec).
///
/// Supports resuming an interrupted build: a [build.progress] file in the
/// index directory records the last line ID that was fully flushed to a segment.
class IndexingPipeline {
  // Format: three integers separated by newlines.
  //   Line 1: last flushed line ID
  //   Line 2: total line count
  //   Line 3: count of lines up to (and including) the last flushed line ID
  static const String _progressFileName = 'build.progress';

  // ── Progress file helpers ─────────────────────────────────────

  static int readResumeLineId(String indexPath) {
    int lineId = 0;
    readProgressFile(indexPath,
        lineId: (v) => lineId = v, totalLines: (_) {}, resumeOffset: (_) {});
    return lineId;
  }

  static void readProgressFile(
    String indexPath, {
    required void Function(int) lineId,
    required void Function(int) totalLines,
    required void Function(int) resumeOffset,
  }) {
    lineId(0);
    totalLines(0);
    resumeOffset(0);
    final path = '$indexPath${Platform.pathSeparator}$_progressFileName';
    try {
      final f = File(path);
      if (!f.existsSync()) return;
      final lines = f.readAsStringSync().trim().split('\n');
      if (lines.isNotEmpty) lineId(int.tryParse(lines[0].trim()) ?? 0);
      if (lines.length >= 2) totalLines(int.tryParse(lines[1].trim()) ?? 0);
      if (lines.length >= 3) resumeOffset(int.tryParse(lines[2].trim()) ?? 0);
    } catch (_) {}
  }

  static void _writeProgressFile(
      String indexPath, int lineId, int totalLines, int resumeOffset) {
    try {
      File('$indexPath${Platform.pathSeparator}$_progressFileName')
          .writeAsStringSync('$lineId\n$totalLines\n$resumeOffset');
    } catch (_) {
      // best-effort
    }
  }

  static void deleteProgressFile(String indexPath) {
    try {
      final path = '$indexPath${Platform.pathSeparator}$_progressFileName';
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────

  /// Builds (or resumes) the index at [indexPath] from the database at [dbPath].
  static Future<bool> build(
    String indexPath,
    String dbPath, {
    SegmentStore? store,
    int limit = 0,
    int totalLines = 0,
    int resumeOffset = 0,
    void Function(int)? onProgress,
    void Function()? onFlush,
    bool Function()? isCancelled,
  }) async {
    int resumeLineId = 0;
    int cachedTotalLines = 0;
    readProgressFile(
      indexPath,
      lineId: (v) => resumeLineId = v,
      totalLines: (v) => cachedTotalLines = v,
      resumeOffset: (_) {},
    );

    if (resumeLineId != 0) {
      int segCount = 0;
      try {
        final dir = Directory(indexPath);
        if (dir.existsSync()) {
          segCount = dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.dat') &&
                  f.path.split(Platform.pathSeparator).last.startsWith('seg_'))
              .length;
        }
      } catch (_) {}
      print('[IndexingPipeline] Resuming from line id $resumeLineId — $segCount segment file(s) on disk');
    } else {
      print('[IndexingPipeline] Starting fresh build');
    }

    final tokenizer = Tokenizer();
    int n = 0;
    bool anyLinesProcessed = false;

    const forceFlushLineInterval = 250000;

    IndexWriter writer;
    try {
      writer = store != null
          ? IndexWriter.withStore(indexPath, store)
          : IndexWriter(indexPath);
    } on CorruptIndexException catch (ex) {
      print('[IndexingPipeline] ${ex.message}');
      print('[IndexingPipeline] Wiping index directory for clean rebuild...');
      try {
        final dir = Directory(indexPath);
        if (dir.existsSync()) {
          for (final f in dir.listSync().whereType<File>()) f.deleteSync();
        }
      } catch (wipeEx) {
        print('[IndexingPipeline] Failed to wipe index directory: $wipeEx');
        rethrow;
      }
      print('[IndexingPipeline] Starting fresh build from scratch...');
      resumeLineId = 0;
      writer = IndexWriter(indexPath);
    }

    int lastWrittenLineId = resumeLineId;
    int lastProgressLineId = resumeLineId;

    int effectiveTotalLines = totalLines > 0 ? totalLines : cachedTotalLines;
    int effectiveResumeOffset = resumeOffset > 0 ? resumeOffset : 0;

    if (resumeLineId != 0) {
      print('[IndexingPipeline] Writer ready — LastFlushedLineId=${writer.lastFlushedLineId}, resumeLineId=$resumeLineId');
    }

    final db = ZayitDb(dbPath);
    await db.open();
    try {
      final lineSource = resumeLineId != 0
          ? db.readLinesFrom(resumeLineId, limit: limit, isCancelled: isCancelled)
          : db.readLines(limit, isCancelled: isCancelled);

      await for (final (id, content) in lineSource) {
        if (isCancelled != null && isCancelled()) break;
        anyLinesProcessed = true;

        for (final term in tokenizer.extract(content)) {
          await writer.add(id, term);
        }

        lastWrittenLineId = id;
        n++;
        onProgress?.call(n);

        if (n % forceFlushLineInterval == 0) await writer.forceFlush();

        int flushed = writer.lastFlushedLineId;
        if (flushed > lastProgressLineId) {
          _writeProgressFile(indexPath, flushed, effectiveTotalLines,
              effectiveResumeOffset + n);
          print('[IndexingPipeline] Progress file updated: lineId=$flushed (written=$lastWrittenLineId, n=$n)');
          lastProgressLineId = flushed;
          onFlush?.call();
        }
      }

      await writer.dispose();
    } finally {
      await db.dispose();
    }

    if (anyLinesProcessed) {
      _writeProgressFile(indexPath, lastWrittenLineId, effectiveTotalLines,
          effectiveResumeOffset + n);
      print('[IndexingPipeline] Build complete — final progress lineId=$lastWrittenLineId');
    } else {
      print('[IndexingPipeline] No lines processed (WAL recovery only or empty DB) — progress file unchanged at $resumeLineId');
    }

    return anyLinesProcessed;
  }
}
