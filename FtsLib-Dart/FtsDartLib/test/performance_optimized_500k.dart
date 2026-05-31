import 'dart:io';
import 'package:fts_lib/fts_lib.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Optimized 500k performance test with reduced merging overhead
void main() async {
  final stopwatch = Stopwatch()..start();

  print('═══ PERFORMANCE TEST — 500K (OPTIMIZED) ═══');
  print('Optimized for reduced merging overhead...');

  // Initialize FFI
  sqfliteFfiInit();

  const int limit = 500000;
  final String indexDir = './index_500k_optimized';

  // Clean up any existing index
  final dir = Directory(indexDir);
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
  await dir.create(recursive: true);
  print('Created index directory: $indexDir');

  // ── PHASE 1: OPTIMIZED INDEXING ───────────────────────────────────
  print('\n║ PHASE 1: OPTIMIZED INDEXING');
  print('║  Target: $limit lines from database');
  print('║  Strategy: High flush threshold to minimize merges');

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

    // OPTIMIZATION: Very high flush thresholds = fewer segments = less merging
    final indexWriter = IndexWriter(indexDir);
    indexWriter.flushThreshold = 1000000; // 1M terms per segment
    indexWriter.firstFlushThreshold = 500000; // 500k terms for first segment

    int currentLineId = 1;
    const int batchSize = 25000;

    print('║  ✓ Optimized flush thresholds set');
    print('║  ✓ Target: Create minimal number of segments');

    await for (final (_, content) in zayitDb.readLines(limit)) {
      // OPTIMIZATION: More aggressive filtering to reduce term count
      final words = content.toLowerCase().split(RegExp(r'[^a-zA-Zא-ת]+'));

      for (final word in words) {
        // Skip very common short words and very long words
        if (word.length >= 3 && word.length <= 20) {
          indexWriter.add(currentLineId, word);
          currentLineId++;
        }
      }

      processedLines++;

      // Progress reporting (less frequent to reduce overhead)
      if (processedLines % batchSize == 0) {
        final elapsed = indexStopwatch.elapsedMilliseconds;
        final rate = (processedLines * 1000) / elapsed;
        final percent = (processedLines / limit * 100).toStringAsFixed(1);
        print(
            '║  Progress: $processedLines/$limit ($percent%) - ${rate.toStringAsFixed(0)} lines/sec');
      }

      if (processedLines >= limit) break;
    }

    print('║  ✓ Data processing completed');
    print('║  ✓ Starting final flush (this may take time)...');

    // Final flush - this is where the major merging happens
    final flushStopwatch = Stopwatch()..start();
    await indexWriter.forceFlush();
    flushStopwatch.stop();

    print(
        '║  ✓ Final flush completed in ${flushStopwatch.elapsedMilliseconds}ms');

    await indexWriter.dispose();

    indexStopwatch.stop();
    indexTime = indexStopwatch.elapsedMilliseconds;
    indexRate = (processedLines * 1000) / indexTime;

    print('║  ✓ Indexing completed');
    print('║  ✓ Processed: $processedLines lines');
    print(
        '║  ✓ Total time: ${indexTime}ms (${(indexTime / 1000).toStringAsFixed(1)}s)');
    print('║  ✓ Flush time: ${flushStopwatch.elapsedMilliseconds}ms');
    print('║  ✓ Rate: ${indexRate.toStringAsFixed(0)} lines/sec');

    zayitDb.dispose();
  } catch (e) {
    print('║  ✗ Indexing failed: $e');
    return;
  }

  // ── PHASE 2: QUICK SEARCH VERIFICATION ─────────────────────────────
  print('\n║ PHASE 2: SEARCH VERIFICATION');

  try {
    final indexReader = await IndexReader.openFromDir(indexDir);
    print('║  ✓ Index opened for searching');

    // Just a few quick searches to verify it works
    final quickTests = ['torah', 'moses', 'god'];

    for (final query in quickTests) {
      final searchStopwatch = Stopwatch()..start();
      final results = await indexReader.searchOr([query]);
      searchStopwatch.stop();
      print(
          '║  Quick test "$query": ${results.length} results in ${searchStopwatch.elapsedMilliseconds}ms');
    }

    await indexReader.dispose();
  } catch (e) {
    print('║  ✗ Search verification failed: $e');
  }

  // ── DISK USAGE ANALYSIS ────────────────────────────────────────────
  print('\n║ PHASE 3: DISK USAGE ANALYSIS');

  try {
    int totalSize = 0;
    int fileCount = 0;
    int datFiles = 0;
    int dbFiles = 0;

    await for (final entity in dir.list()) {
      if (entity is File) {
        final size = await entity.length();
        totalSize += size;
        fileCount++;

        if (entity.path.endsWith('.dat')) datFiles++;
        if (entity.path.endsWith('.db')) dbFiles++;
      }
    }

    final sizeMB = totalSize / (1024 * 1024);
    print('║  ✓ Total files: $fileCount ($datFiles .dat, $dbFiles .db)');
    print('║  ✓ Total size: ${sizeMB.toStringAsFixed(1)} MB');
    print(
        '║  ✓ Avg per line: ${(totalSize / processedLines).toStringAsFixed(0)} bytes');

    // Efficiency analysis
    final segmentsCount = datFiles;
    print('║  ✓ Segments created: $segmentsCount');
    if (segmentsCount <= 3) {
      print('║  ✓ Excellent: Minimal segments achieved!');
    } else if (segmentsCount <= 10) {
      print('║  ✓ Good: Reasonable segment count');
    } else {
      print('║  ⚠ Many segments: Consider higher flush threshold');
    }
  } catch (e) {
    print('║  ⚠ Could not analyze disk usage: $e');
  }

  // ── SUMMARY ───────────────────────────────────────────────────────
  stopwatch.stop();
  final totalTime = stopwatch.elapsedMilliseconds;

  print('\n═══ OPTIMIZED PERFORMANCE SUMMARY ═══');
  print('║  Total time: ${(totalTime / 1000).toStringAsFixed(1)}s');
  print('║  Index time: ${(indexTime / 1000).toStringAsFixed(1)}s');
  print('║  Lines processed: $processedLines');
  print('║  Indexing rate: ${indexRate.toStringAsFixed(0)} lines/sec');
  print('║  Optimization: High flush thresholds');
  print('║  Status: ✓ COMPLETED');
  print('║');
  print('║  Index preserved at: $indexDir');
  print('║  Use for further testing or delete with:');
  print('║  rm -rf $indexDir');
  print('═════════════════════════════════════════');
}
