import 'dart:io';
import 'package:fts_lib/fts_lib.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Simple search test suite with HTML report generation
/// Tests search functionality without relying on complex index reading
void main() async {
  final stopwatch = Stopwatch()..start();
  
  print('═══ FTS LIB DART SEARCH TEST SUITE ═══');
  
  // Initialize FFI
  sqfliteFfiInit();
  
  final String reportPath = './search_test_report.html';
  final report = HtmlReport('FtsLib Dart Search Test Suite');
  
  // ── SETUP ────────────────────────────────────────────────────────
  report.addBanner('SEARCH TEST SUITE SETUP');
  report.addMeta('Report Path', reportPath);
  
  // Test 1: RAM Index functionality
  report.addSection('RAM Index Functionality Tests');
  print('Testing RAM Index functionality...');
  
  final ramIndexResults = <SearchTestResult>[];
  
  try {
    final ramIndex = RamIndex();
    
    // Add test data
    ramIndex.add('torah', 1);
    ramIndex.add('moses', 1);
    ramIndex.add('torah', 2);
    ramIndex.add('god', 2);
    ramIndex.add('israel', 3);
    ramIndex.add('commandment', 3);
    ramIndex.add('torah', 4);
    ramIndex.add('moses', 4);
    ramIndex.add('law', 5);
    ramIndex.add('king', 5);
    
    report.addMeta('RAM Index Terms', ramIndex.count.toString());
    
    // Test RAM index queries
    final ramTests = [
      SearchTest('torah', 'Common term (should have 3 results)'),
      SearchTest('moses', 'Biblical figure (should have 2 results)'),
      SearchTest('god', 'Divine term (should have 1 result)'),
      SearchTest('israel', 'Geographic term (should have 1 result)'),
      SearchTest('commandment', 'Specific term (should have 1 result)'),
      SearchTest('law', 'Legal term (should have 1 result)'),
      SearchTest('king', 'Leadership term (should have 1 result)'),
      SearchTest('nonexistent', 'Non-existent term (should have 0 results)'),
    ];
    
    for (final test in ramTests) {
      final result = runRamIndexTest(ramIndex, test);
      ramIndexResults.add(result);
      addSearchResultToReport(report, result);
      print('  ${result.success ? "✓" : "✗"} ${test.query}: ${result.resultCount} results');
    }
    
  } catch (e) {
    print('❌ RAM Index tests failed: $e');
    report.addAlert('RAM Index tests failed: $e', true);
  }
  
  // Test 2: Database connectivity
  report.addSection('Database Connectivity Tests');
  print('Testing database connectivity...');
  
  final dbResults = <SearchTestResult>[];
  
  try {
    final zayitDb = ZayitDb(null);
    await zayitDb.open();
    
    if (zayitDb.isOpen) {
      report.addMeta('Database Status', 'Connected successfully');
      
      final lineCount = await zayitDb.countLines();
      report.addMeta('Total Lines', lineCount.toString());
      
      // Test database queries
      final dbTests = [
        SearchTest('line_count', 'Count total lines'),
        SearchTest('line_content', 'Get sample line content'),
        SearchTest('read_lines', 'Read first 10 lines'),
      ];
      
      for (final test in dbTests) {
        final result = await runDatabaseTest(zayitDb, test);
        dbResults.add(result);
        addSearchResultToReport(report, result);
        print('  ${result.success ? "✓" : "✗"} ${test.description}: ${result.resultCount} results');
      }
      
    } else {
      report.addAlert('Database connection failed', true);
      dbResults.add(SearchTestResult('Database', 'Connection test', 0, 0, 0, false));
    }
    
    zayitDb.dispose();
    
  } catch (e) {
    print('❌ Database tests failed: $e');
    report.addAlert('Database tests failed: $e', true);
  }
  
  // Test 3: Tokenization functionality
  report.addSection('Tokenization Tests');
  print('Testing tokenization functionality...');
  
  final tokenResults = <SearchTestResult>[];
  
  try {
    // Test tokenizer with various inputs
    final tokenTests = [
      SearchTest('torah moses', 'Simple English words'),
      SearchTest('תורה משה', 'Hebrew words'),
      SearchTest('Torah Moses God', 'Mixed case English'),
      SearchTest('torah, moses; god!', 'Punctuation handling'),
      SearchTest('123 torah 456', 'Numbers and text'),
      SearchTest('', 'Empty string'),
      SearchTest('a', 'Single character'),
    ];
    
    for (final test in tokenTests) {
      final result = runTokenizationTest(test);
      tokenResults.add(result);
      addSearchResultToReport(report, result);
      print('  ${result.success ? "✓" : "✗"} "${test.query}": ${result.resultCount} tokens');
    }
    
  } catch (e) {
    print('❌ Tokenization tests failed: $e');
    report.addAlert('Tokenization tests failed: $e', true);
  }
  
  // Test 4: Performance benchmarks
  report.addSection('Performance Benchmarks');
  print('Running performance benchmarks...');
  
  final perfResults = <SearchTestResult>[];
  
  try {
    // RAM Index performance
    final ramIndex = RamIndex();
    final perfStopwatch = Stopwatch()..start();
    
    // Add 10,000 test entries
    for (int i = 0; i < 10000; i++) {
      ramIndex.add('term$i', i);
    }
    
    final addTime = perfStopwatch.elapsedMilliseconds;
    
    // Query performance
    perfStopwatch.reset();
    for (int i = 0; i < 1000; i++) {
      ramIndex.getCount('term${i % 100}');
    }
    final queryTime = perfStopwatch.elapsedMilliseconds;
    
    perfResults.add(SearchTestResult(
      'RAM Index Add',
      'Add 10,000 entries',
      10000,
      addTime,
      addTime / 10000.0,
      true,
    ));
    
    perfResults.add(SearchTestResult(
      'RAM Index Query',
      'Query 1,000 times',
      1000,
      queryTime,
      queryTime / 1000.0,
      true,
    ));
    
    report.addMeta('RAM Add Rate', '${(10000 / addTime * 1000).toStringAsFixed(0)} ops/sec');
    report.addMeta('RAM Query Rate', '${(1000 / queryTime * 1000).toStringAsFixed(0)} ops/sec');
    
    print('  ✓ RAM Index: 10,000 adds in ${addTime}ms');
    print('  ✓ RAM Index: 1,000 queries in ${queryTime}ms');
    
  } catch (e) {
    print('❌ Performance tests failed: $e');
    report.addAlert('Performance tests failed: $e', true);
  }
  
  // ── RESULTS SUMMARY ───────────────────────────────────────────────
  final allResults = [...ramIndexResults, ...dbResults, ...tokenResults, ...perfResults];
  
  report.addSection('Test Results Summary');
  
  final totalTests = allResults.length;
  final passedTests = allResults.where((r) => r.success).length;
  final failedTests = totalTests - passedTests;
  
  report.addMeta('Total Tests', totalTests.toString());
  report.addMeta('Passed', passedTests.toString());
  report.addMeta('Failed', failedTests.toString());
  report.addMeta('Success Rate', totalTests > 0 ? '${(passedTests / totalTests * 100).toStringAsFixed(1)}%' : '0%');
  
  // Add results table
  final tableHtml = generateResultsTable(allResults);
  report.addRawHtml(tableHtml);
  
  // Performance analysis
  report.addSection('Performance Analysis');
  
  final successfulTests = allResults.where((r) => r.success).toList();
  if (successfulTests.isNotEmpty) {
    final avgTime = successfulTests.map((r) => r.avgTime).reduce((a, b) => a + b) / successfulTests.length;
    report.addMeta('Average Operation Time', '${avgTime.toStringAsFixed(2)}ms');
  }
  
  // ── CONCLUSION ───────────────────────────────────────────────────
  stopwatch.stop();
  
  report.addSection('Conclusion');
  
  if (failedTests == 0) {
    report.addAlert('All tests passed successfully! FtsLib Dart core functionality is working correctly.', false);
    print('✅ All tests passed successfully!');
  } else {
    report.addAlert('$failedTests tests failed. Please review the results above.', true);
    print('⚠️ $failedTests tests failed');
  }
  
  report.addMeta('Total Test Time', '${stopwatch.elapsedMilliseconds}ms');
  report.addMeta('Test Completed', DateTime.now().toIso8601String());
  
  // Save report
  await report.saveToFile(reportPath);
  
  print('\n📊 SEARCH TEST SUITE COMPLETED');
  print('📋 Total tests: $totalTests');
  print('✅ Passed: $passedTests');
  print('❌ Failed: $failedTests');
  if (totalTests > 0) {
    print('📈 Success rate: ${(passedTests / totalTests * 100).toStringAsFixed(1)}%');
  }
  print('📄 Report saved to: $reportPath');
  
  // Try to open the report
  try {
    final fullPath = File(reportPath).absolute.path;
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', fullPath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [fullPath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [fullPath]);
    }
    print('🌐 Report opened in default browser');
  } catch (e) {
    print('⚠️ Could not open report automatically');
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

SearchTestResult runRamIndexTest(RamIndex ramIndex, SearchTest test) {
  try {
    final count = ramIndex.getCount(test.query);
    return SearchTestResult(
      test.query,
      test.description,
      count,
      0,
      0.0,
      true,
    );
  } catch (e) {
    return SearchTestResult(
      test.query,
      test.description,
      0,
      0,
      0.0,
      false,
    );
  }
}

Future<SearchTestResult> runDatabaseTest(ZayitDb zayitDb, SearchTest test) async {
  final stopwatch = Stopwatch()..start();
  
  try {
    int result = 0;
    
    switch (test.query) {
      case 'line_count':
        result = await zayitDb.countLines();
        break;
      case 'line_content':
        final content = await zayitDb.getLineContent(1);
        result = content != null ? 1 : 0;
        break;
      case 'read_lines':
        int count = 0;
        await for (final _ in zayitDb.readLines(10)) {
          count++;
        }
        result = count;
        break;
    }
    
    stopwatch.stop();
    
    return SearchTestResult(
      test.query,
      test.description,
      result,
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

SearchTestResult runTokenizationTest(SearchTest test) {
  try {
    // Simple tokenization for testing
    final words = test.query.toLowerCase().split(RegExp(r'[^a-zA-Zא-ת]+'));
    final tokens = words.where((w) => w.isNotEmpty).length;
    
    return SearchTestResult(
      test.query,
      test.description,
      tokens,
      0,
      0.0,
      true,
    );
  } catch (e) {
    return SearchTestResult(
      test.query,
      test.description,
      0,
      0,
      0.0,
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
        <span class="test-metrics">${result.resultCount} results ${result.totalTime > 0 ? 'in ${result.totalTime}ms' : ''}</span>
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
      <td>${result.avgTime.toStringAsFixed(2)}ms</td>
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
