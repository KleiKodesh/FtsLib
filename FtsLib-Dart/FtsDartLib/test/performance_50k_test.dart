import 'dart:io';
import 'package:fts_lib/fts_lib.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Quick performance test - 50k tier
/// Faster test for development and verification
void main() async {
  final stopwatch = Stopwatch()..start();

  print('═══ PERFORMANCE TEST — 50K (QUICK) ═══');

  // Initialize FFI
  sqfliteFfiInit();

  const int limit = 50000;
  final String indexDir = './index_50k';

  // Clean up any existing index
  final dir = Directory(indexDir);
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
  await dir.create(recursive: true);
  print('Created index directory: $indexDir');

  // ── PHASE 1: INDEXING ────────────────────────────────────────
  print('\n║ PHASE 1: INDEXING');
  print('║  Target: $limit lines from database');

  final indexStopwatch = Stopwatch()..start();
  int processedLines = 0;
  int indexTime = 0;
  double indexRate = 0.0;

  try {
    final zayitDb = ZayitDb(null);
    await zayitDb.open();

    if (!zayitDb.isOpen) {
      print('║  ✗ Could not open database');
      return;
    }

    print('║  ✓ Database opened successfully');

    // Use higher flush threshold to reduce merging
    final indexWriter = IndexWriter(indexDir);
    indexWriter.flushThreshold = 100000; // Higher threshold = fewer merges
    indexWriter.firstFlushThreshold = 25000; // Higher first threshold

    int currentLineId = 1;
    const int batchSize = 5000;

    await for (final (_, content) in zayitDb.readLines(limit)) {
      // Simple tokenization
      final words = content.toLowerCase().split(RegExp(r'[^a-zA-Zא-ת]+'));

      for (final word in words) {
        if (word.length >= 2) {
          indexWriter.add(currentLineId, word);
          currentLineId++;
        }
      }

      processedLines++;

      // Progress reporting
      if (processedLines % batchSize == 0) {
        final elapsed = indexStopwatch.elapsedMilliseconds;
        final rate = (processedLines * 1000) / elapsed;
        final percent = (processedLines / limit * 100).toStringAsFixed(1);
        print(
            '║  Progress: $processedLines/$limit ($percent%) - ${rate.toStringAsFixed(0)} lines/sec');
      }

      if (processedLines >= limit) break;
    }

    // Flush the index
    print('║  Flushing index to disk...');
    await indexWriter.forceFlush();
    await indexWriter.dispose();

    indexStopwatch.stop();
    indexTime = indexStopwatch.elapsedMilliseconds;
    indexRate = (processedLines * 1000) / indexTime;

    print('║  ✓ Indexing completed');
    print('║  ✓ Processed: $processedLines lines');
    print(
        '║  ✓ Time: ${indexTime}ms (${(indexTime / 1000).toStringAsFixed(1)}s)');
    print('║  ✓ Rate: ${indexRate.toStringAsFixed(0)} lines/sec');

    zayitDb.dispose();
  } catch (e) {
    print('║  ✗ Indexing failed: $e');
    return;
  }

  // ── PHASE 2: SEARCH PERFORMANCE ───────────────────────────────────
  print('\n║ PHASE 2: SEARCH PERFORMANCE');

  try {
    final indexReader = await IndexReader.openFromDir(indexDir);
    print('║  ✓ Index opened for searching');

    final testCases = [
      ('Single word', 'torah'),
      ('Hebrew word', 'תורה'),
      ('Wildcard prefix', 'tor*'),
      ('Common word', 'and'),
      ('Rare word', 'leviticus'),
    ];

    for (final (label, query) in testCases) {
      final searchStopwatch = Stopwatch()..start();

      try {
        final results = await indexReader.searchOr([query]);
        searchStopwatch.stop();

        final searchTime = searchStopwatch.elapsedMilliseconds;
        print('║  $label: ${results.length} results in ${searchTime}ms');
      } catch (e) {
        print('║  $label: FAILED - $e');
      }
    }

    // Quick stress test
    print('\n║  STRESS TEST: 50 rapid searches...');
    final stressStopwatch = Stopwatch()..start();

    for (int i = 0; i < 50; i++) {
      final queries = ['torah', 'moses', 'god', 'israel'];
      final query = queries[i % queries.length];
      await indexReader.searchOr([query]);
    }

    stressStopwatch.stop();
    final avgTime = stressStopwatch.elapsedMilliseconds / 50;
    print('║  ✓ 50 searches in ${stressStopwatch.elapsedMilliseconds}ms');
    print('║  ✓ Average: ${avgTime.toStringAsFixed(1)}ms per search');

    await indexReader.dispose();
  } catch (e) {
    print('║  ✗ Search test failed: $e');
  }

  // ── SUMMARY ───────────────────────────────────────────────────────
  stopwatch.stop();
  final totalTime = stopwatch.elapsedMilliseconds;

  print('\n═══ PERFORMANCE TEST SUMMARY ═══');
  print('║  Total time: ${(totalTime / 1000).toStringAsFixed(1)}s');
  print('║  Index time: ${(indexTime / 1000).toStringAsFixed(1)}s');
  print('║  Lines processed: $processedLines');
  print('║  Indexing rate: ${indexRate.toStringAsFixed(0)} lines/sec');
  print('║  Status: ✓ COMPLETED SUCCESSFULLY');
  print('═════════════════════════════════════');
}
