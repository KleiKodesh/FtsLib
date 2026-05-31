import 'package:flutter_test/flutter_test.dart';
import 'package:fts_lib_flutter_demo/services/index_service.dart';

/// Integration test for Flutter demo app with real FtsLib functionality
void main() {
  group('Flutter Demo Integration Tests', () {
    late IndexService indexService;

    setUp(() {
      indexService = IndexService();
    });

    tearDown(() async {
      await indexService.close();
    });

    test('IndexService path helpers work correctly', () {
      final dbPath = 'C:\\test\\seforim.db';
      final indexPath = indexService.getIndexPath(dbPath);
      
      expect(indexPath, equals('C:\\test\\seforim-fts-index'));
    });

    test('IndexService initial state is correct', () {
      expect(indexService.isReady, isFalse);
      expect(indexService.openDbPath, isEmpty);
    });

    test('SearchResultItem creates correctly', () {
      final result = SearchResultItem(
        lineId: 123,
        bookTitle: 'בראשית',
        snippet: 'This is a <mark>test</mark> snippet',
      );

      expect(result.lineId, equals(123));
      expect(result.bookTitle, equals('בראשית'));
      expect(result.snippet, contains('<mark>test</mark>'));
      expect(result.plainSnippet, equals('This is a test snippet'));
      expect(result.plainSnippet, isNot(contains('<mark>')));
    });

    test('SearchResultItem handles HTML entities', () {
      final result = SearchResultItem(
        lineId: 456,
        bookTitle: 'שמות',
        snippet: 'Text with &amp; &gt; &lt; &quot; entities',
      );

      expect(result.plainSnippet, equals('Text with & > < " entities'));
    });
  });
}
