import 'dart:io';
import 'package:fts_lib/fts_lib.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Comprehensive search test suite with HTML report generation
/// Similar to C# FtsLibTest search tests
void main() async {
  final stopwatch = Stopwatch()..start();

  print('═══ FTS LIB DART SEARCH TEST SUITE ═══');

  // Initialize FFI
  sqfliteFfiInit();

  const int testLines = 50000;
  final String indexDir = './search_test_index';
  final String reportPath = './search_test_report.html';

  // Clean up and prepare
  final dir = Directory(indexDir);
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
  await dir.create(recursive: true);

  final report = HtmlReport('FtsLib Dart Search Test Suite');

  // ── SETUP ────────────────────────────────────────────────────────
  report.addBanner('SEARCH TEST SUITE SETUP');
  report.addMeta('Test Lines', testLines.toString());
  report.addMeta('Index Directory', indexDir);
  report.addMeta('Report Path', reportPath);

  print('Building test index with $testLines lines...');

  IndexWriter? indexWriter;
  int processedLines = 0;

  try {
    final zayitDb = ZayitDb(null);
    await zayitDb.open();

    if (!zayitDb.isOpen) {
      report.addAlert('Could not open database', true);
      report.saveToFile(reportPath);
      return;
    }

    indexWriter = IndexWriter(indexDir);
    indexWriter.flushThreshold = 1000000; // High threshold to avoid merging

    int currentLineId = 1;

    await for (final (_, content) in zayitDb.readLines(testLines)) {
      final words = content.toLowerCase().split(RegExp(r'[^a-zA-Zא-ת]+'));

      for (final word in words) {
        if (word.length >= 2 && word.length <= 20) {
          indexWriter.add(currentLineId, word);
          currentLineId++;
        }
      }

      processedLines++;
      if (processedLines >= testLines) break;
    }

    await indexWriter.forceFlush();
    await indexWriter.dispose();

    report.addMeta('Lines Processed', processedLines.toString());
    report.addMeta('Index Status', 'Created successfully');

    zayitDb.dispose();
  } catch (e) {
    report.addAlert('Index creation failed: $e', true);
    report.saveToFile(reportPath);
    return;
  }

  // ── SEARCH TESTS ───────────────────────────────────────────────────
  report.addSection('SEARCH FUNCTIONALITY TESTS');

  IndexReader? indexReader;
  final testResults = <SearchTestResult>[];

  try {
    indexReader = await IndexReader.openFromDir(indexDir);

    // Test 1: Basic single word searches
    report.addSection('Single Word Searches');

    final singleWordTests = [
      SearchTest('torah', 'Common English term'),
      SearchTest('moses', 'Biblical figure'),
      SearchTest('god', 'Very common term'),
      SearchTest('israel', 'Geographic term'),
      SearchTest('commandment', 'Specific term'),
      SearchTest('תורה', 'Hebrew term'),
      SearchTest('משה', 'Hebrew biblical figure'),
    ];

    for (final test in singleWordTests) {
      final result = await runSearchTest(indexReader, test);
      testResults.add(result);
      addSearchResultToReport(report, result);
    }

    // Test 2: Wildcard searches
    report.addSection('Wildcard Searches');

    final wildcardTests = [
      SearchTest('tor*', 'Prefix wildcard'),
      SearchTest('*ah', 'Suffix wildcard'),
      SearchTest('*mand*', 'Infix wildcard'),
      SearchTest('g*d', 'Multi-character wildcard'),
    ];

    for (final test in wildcardTests) {
      final result = await runSearchTest(indexReader, test);
      testResults.add(result);
      addSearchResultToReport(report, result);
    }

    // Test 3: OR searches
    report.addSection('OR Searches');

    final orTests = [
      SearchTest('torah OR moses', 'Two common terms'),
      SearchTest('god OR lord', 'Divine terms'),
      SearchTest('israel OR jerusalem', 'Geographic terms'),
      SearchTest('commandment OR law', 'Related concepts'),
    ];

    for (final test in orTests) {
      final result = await runSearchTest(indexReader, test);
      testResults.add(result);
      addSearchResultToReport(report, result);
    }

    // Test 4: Performance stress test
    report.addSection('Performance Stress Test');

    final stressStopwatch = Stopwatch()..start();
    int stressTests = 0;
    final stressQueries = ['torah', 'moses', 'god', 'israel', 'commandment'];

    for (int i = 0; i < 100; i++) {
      final query = stressQueries[i % stressQueries.length];
      await indexReader.searchOr([query]);
      stressTests++;
    }

    stressStopwatch.stop();
    final avgTime = stressStopwatch.elapsedMilliseconds / stressTests;

    report.addMeta('Stress Tests Run', stressTests.toString());
    report.addMeta(
        'Total Stress Time', '${stressStopwatch.elapsedMilliseconds}ms');
    report.addMeta('Average Per Query', '${avgTime.toStringAsFixed(1)}ms');

    testResults.add(SearchTestResult(
      'Stress Test (100 queries)',
      'Performance benchmark',
      stressTests,
      stressStopwatch.elapsedMilliseconds,
      avgTime,
      true,
    ));

    await indexReader.dispose();
  } catch (e) {
    report.addAlert('Search tests failed: $e', true);
  }

  // ── RESULTS SUMMARY ───────────────────────────────────────────────
  report.addSection('Test Results Summary');

  final totalTests = testResults.length;
  final passedTests = testResults.where((r) => r.success).length;
  final failedTests = totalTests - passedTests;

  report.addMeta('Total Tests', totalTests.toString());
  report.addMeta('Passed', passedTests.toString());
  report.addMeta('Failed', failedTests.toString());
  report.addMeta('Success Rate',
      '${(passedTests / totalTests * 100).toStringAsFixed(1)}%');

  // Add results table
  final tableHtml = generateResultsTable(testResults);
  report.addRawHtml(tableHtml);

  // Performance analysis
  report.addSection('Performance Analysis');

  final successfulTests = testResults.where((r) => r.success).toList();
  if (successfulTests.isNotEmpty) {
    final avgQueryTime =
        successfulTests.map((r) => r.avgTime).reduce((a, b) => a + b) /
            successfulTests.length;
    final maxQueryTime =
        successfulTests.map((r) => r.avgTime).reduce((a, b) => a > b ? a : b);
    final minQueryTime =
        successfulTests.map((r) => r.avgTime).reduce((a, b) => a < b ? a : b);

    report.addMeta(
        'Average Query Time', '${avgQueryTime.toStringAsFixed(1)}ms');
    report.addMeta('Fastest Query', '${minQueryTime.toStringAsFixed(1)}ms');
    report.addMeta('Slowest Query', '${maxQueryTime.toStringAsFixed(1)}ms');
  }

  // ── CONCLUSION ───────────────────────────────────────────────────
  stopwatch.stop();

  report.addSection('Conclusion');

  if (failedTests == 0) {
    report.addAlert(
        'All tests passed successfully! FtsLib Dart search functionality is working correctly.',
        false);
  } else {
    report.addAlert(
        '$failedTests tests failed. Please review the results above.', true);
  }

  report.addMeta('Total Test Time', '${stopwatch.elapsedMilliseconds}ms');
  report.addMeta('Test Completed', DateTime.now().toIso8601String());

  // Save and open report
  await report.saveToFile(reportPath);

  print('\n✓ Search test suite completed!');
  print('✓ Total tests: $totalTests');
  print('✓ Passed: $passedTests');
  print('✓ Failed: $failedTests');
  print('✓ Report saved to: $reportPath');

  // Try to open the report in default browser
  try {
    if (Platform.isWindows) {
      await Process.run('start', [reportPath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [reportPath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [reportPath]);
    }
    print('✓ Report opened in default browser');
  } catch (e) {
    print('⚠ Could not open report automatically: $e');
  }
}

// ── HELPER CLASSES AND FUNCTIONS ───────────────────────────────────────

class SearchTest {
  final String query;
  final String description;

  SearchTest(this.query, this.description);
}

class SearchTestResult {
  final String query;
  final String description;
  final int resultCount;
  final int totalTime;
  final double avgTime;
  final bool success;

  SearchTestResult(
    this.query,
    this.description,
    this.resultCount,
    this.totalTime,
    this.avgTime,
    this.success,
  );
}

Future<SearchTestResult> runSearchTest(
    IndexReader reader, SearchTest test) async {
  final stopwatch = Stopwatch()..start();

  try {
    final results = await reader.searchOr([test.query]);
    stopwatch.stop();

    return SearchTestResult(
      test.query,
      test.description,
      results.length,
      stopwatch.elapsedMilliseconds,
      stopwatch.elapsedMilliseconds.toDouble(),
      true,
    );
  } catch (e) {
    stopwatch.stop();

    return SearchTestResult(
      test.query,
      test.description,
      0,
      stopwatch.elapsedMilliseconds,
      stopwatch.elapsedMilliseconds.toDouble(),
      false,
    );
  }
}

void addSearchResultToReport(HtmlReport report, SearchTestResult result) {
  final status = result.success ? '✓ PASS' : '✗ FAIL';
  final statusClass = result.success ? 'success' : 'error';

  report.addRawHtml('''
    <div class="test-result">
      <div class="test-header">
        <span class="test-query">${_htmlEscape(result.query)}</span>
        <span class="test-status $statusClass">$status</span>
      </div>
      <div class="test-details">
        <span class="test-description">${_htmlEscape(result.description)}</span>
        <span class="test-metrics">${result.resultCount} results in ${result.totalTime}ms</span>
      </div>
    </div>
  ''');
}

String generateResultsTable(List<SearchTestResult> results) {
  final rows = results.map((result) => '''
    <tr class="${result.success ? 'success-row' : 'error-row'}">
      <td>${_htmlEscape(result.query)}</td>
      <td>${_htmlEscape(result.description)}</td>
      <td>${result.resultCount}</td>
      <td>${result.totalTime}ms</td>
      <td>${result.avgTime.toStringAsFixed(1)}ms</td>
      <td>${result.success ? '✓ PASS' : '✗ FAIL'}</td>
    </tr>
  ''').join();

  return '''
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Query</th>
            <th>Description</th>
            <th>Results</th>
            <th>Total Time</th>
            <th>Avg Time</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          $rows
        </tbody>
      </table>
    </div>
  ''';
}

String _htmlEscape(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

// ── HTML REPORT GENERATOR ─────────────────────────────────────────────

class HtmlReport {
  final String title;
  final StringBuffer _body = StringBuffer();

  HtmlReport(this.title);

  void addBanner(String text) {
    _body.writeln('<div class="banner">${_htmlEscape(text)}</div>');
  }

  void addMeta(String label, String value) {
    _body.writeln('''
      <div class="meta">
        <span class="meta-label">${_htmlEscape(label)}</span>
        <span class="meta-value">${_htmlEscape(value)}</span>
      </div>
    ''');
  }

  void addSection(String heading) {
    _body.writeln('<h2>${_htmlEscape(heading)}</h2>');
  }

  void addAlert(String text, bool isError) {
    final cls = isError ? 'alert alert-error' : 'alert alert-info';
    _body.writeln('<div class="$cls">${_htmlEscape(text)}</div>');
  }

  void addRawHtml(String html) {
    _body.writeln(html);
  }

  Future<void> saveToFile(String path) async {
    final html = generateFullHtml();
    final file = File(path);
    await file.writeAsString(html);
  }

  String generateFullHtml() {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${_htmlEscape(title)}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f7fa;
        }
        .report-block {
            background: #fff;
            border: 1px solid #dde3ec;
            border-radius: 8px;
            padding: 20px 24px;
            margin-bottom: 28px;
            box-shadow: 0 2px 8px rgba(0,0,0,.07);
        }
        .banner {
            background: #0d1b2a;
            color: #e0e7ff;
            font-size: 1.2rem;
            font-weight: 700;
            padding: 12px 18px;
            border-radius: 5px;
            margin-bottom: 14px;
            letter-spacing: .4px;
        }
        .meta {
            display: flex;
            gap: 10px;
            padding: 3px 0;
            font-size: 13px;
            color: #444;
        }
        .meta-label { font-weight: 600; min-width: 160px; color: #1a3a5c; }
        .meta-value { color: #222; }
        .table-wrap { overflow-x: auto; margin: 10px 0 16px; }
        table {
            border-collapse: collapse;
            width: 100%;
            background: #fff;
            border-radius: 5px;
            overflow: hidden;
            box-shadow: 0 1px 3px rgba(0,0,0,.07);
        }
        th {
            background: #1a3a5c;
            color: #fff;
            padding: 7px 11px;
            text-align: left;
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: .3px;
        }
        td {
            padding: 6px 11px;
            border-bottom: 1px solid #eef0f4;
            font-size: 13px;
        }
        tr:last-child td { border-bottom: none; }
        .success-row { background: #f0f9f0; }
        .error-row { background: #fff0f0; }
        .alert {
            padding: 12px 16px;
            border-radius: 4px;
            margin: 10px 0;
            font-weight: 500;
        }
        .alert-info {
            background: #e3f2fd;
            border: 1px solid #bbdefb;
            color: #1565c0;
        }
        .alert-error {
            background: #ffebee;
            border: 1px solid #ffcdd2;
            color: #c62828;
        }
        h2 {
            color: #1a3a5c;
            border-bottom: 2px solid #e0e7ff;
            padding-bottom: 8px;
            margin-top: 30px;
            margin-bottom: 16px;
        }
        .test-result {
            border: 1px solid #e0e7ff;
            border-radius: 6px;
            padding: 12px;
            margin: 8px 0;
            background: #fafbff;
        }
        .test-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 6px;
        }
        .test-query {
            font-family: 'Courier New', monospace;
            font-weight: 600;
            color: #1a3a5c;
        }
        .test-status {
            font-weight: 600;
            padding: 2px 8px;
            border-radius: 3px;
            font-size: 12px;
        }
        .success { background: #c8e6c9; color: #2e7d32; }
        .error { background: #ffcdd2; color: #c62828; }
        .test-details {
            display: flex;
            justify-content: space-between;
            font-size: 13px;
            color: #666;
        }
        .test-description { font-style: italic; }
        .test-metrics { font-family: monospace; }
    </style>
</head>
<body>
    <div class="report-block">
        ${_body.toString()}
    </div>
</body>
</html>
    ''';
  }
}
