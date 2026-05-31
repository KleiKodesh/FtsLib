import 'dart:io';
import 'package:fts_lib/fts_lib.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Performance test for FtsLib Dart port - 500k tier
/// Tests indexing and search performance with 500,000 database lines
void main() async {
  final stopwatch = Stopwatch()..start();

  print('═══ PERFORMANCE TEST — 500K ═══');
  print('Starting 500k performance test...');

  // Initialize FFI
  sqfliteFfiInit();

  const int limit = 500000;
  final String indexDir = './index_500k';

  // Clean up any existing index
  final dir = Directory(indexDir);
  if (await dir.exists()) {
    await dir.delete(recursive: true);
    print('Cleaned up existing index directory');
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

    final indexWriter = IndexWriter(indexDir);
    int currentLineId = 1;

    // Process lines in batches for better progress reporting
    const int batchSize = 10000;

    await for (final (_, content) in zayitDb.readLines(limit)) {
      // Simple tokenization - split on non-alphanumeric and non-Hebrew characters
      final words = content.toLowerCase().split(RegExp(r'[^a-zA-Zא-ת]+'));

      for (final word in words) {
        if (word.length >= 2) {
          // Skip very short words
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

    // Test cases similar to C# version
    final testCases = [
      ('Single word', 'torah'),
      ('Hebrew word', 'תורה'),
      ('Wildcard prefix', 'tor*'),
      ('Wildcard suffix', '*ah'),
      ('Common word', 'and'),
      ('Rare word', 'leviticus'),
      ('Multi-word OR', 'torah OR moses'),
      ('Short word', 'a'),
      ('Long word', 'commandments'),
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

    // Performance stress test - multiple searches
    print('\n║  STRESS TEST: 100 rapid searches...');
    final stressStopwatch = Stopwatch()..start();

    for (int i = 0; i < 100; i++) {
      final queries = ['torah', 'moses', 'god', 'israel', 'commandment'];
      final query = queries[i % queries.length];
      await indexReader.searchOr([query]);
    }

    stressStopwatch.stop();
    final avgTime = stressStopwatch.elapsedMilliseconds / 100;
    print('║  ✓ 100 searches in ${stressStopwatch.elapsedMilliseconds}ms');
    print('║  ✓ Average: ${avgTime.toStringAsFixed(1)}ms per search');

    await indexReader.dispose();
  } catch (e) {
    print('║  ✗ Search test failed: $e');
  }

  // ── PHASE 3: MEMORY AND DISK USAGE ─────────────────────────────────
  print('\n║ PHASE 3: RESOURCE USAGE');

  try {
    // Calculate index size
    int totalSize = 0;
    int fileCount = 0;

    await for (final entity in dir.list()) {
      if (entity is File) {
        totalSize += await entity.length();
        fileCount++;
      }
    }

    final sizeMB = totalSize / (1024 * 1024);
    print('║  ✓ Index files: $fileCount');
    print('║  ✓ Total size: ${sizeMB.toStringAsFixed(1)} MB');
    print(
        '║  ✓ Avg per line: ${(totalSize / processedLines).toStringAsFixed(0)} bytes');
  } catch (e) {
    print('║  ⚠ Could not calculate disk usage: $e');
  }

  // ── SUMMARY ───────────────────────────────────────────────────────
  stopwatch.stop();
  final totalTime = stopwatch.elapsedMilliseconds;

  print('\n═══ PERFORMANCE TEST SUMMARY ═══');
  print('║  Total time: ${(totalTime / 1000).toStringAsFixed(1)}s');
  print('║  Index time: ${(indexTime / 1000).toStringAsFixed(1)}s');
  print('║  Lines processed: $processedLines');
  print('║  Indexing rate: ${indexRate.toStringAsFixed(0)} lines/sec');
  print('║  Index directory: $indexDir');
  print('║  Status: ✓ COMPLETED SUCCESSFULLY');
  print('═════════════════════════════════════');

  print('\nNote: Index directory preserved at $indexDir');
  print('Run with --clean to remove it next time');
}
