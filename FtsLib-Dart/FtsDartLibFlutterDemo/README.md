# FtsLibFlutterDemo

Flutter demo app for the FtsLib Hebrew full-text search library.
Mirrors the C# WPF demo (`FtsLibDemo`) feature-for-feature.

## Features

- Pick a seforim SQLite `.db` file and build a full-text index
- Search with live streaming results
- Wildcard (`*`, `?`), fuzzy (`~`), and OR (`|`) query syntax
- Max word distance filter
- Ordered / unordered word matching
- Highlighted snippets with `<mark>` tags rendered as bold text
- Elapsed time + ETA during indexing
- Persistent last-used DB path (SharedPreferences)
- RTL layout throughout
- Syntax help bottom sheet

## Status

| Layer | Status |
|---|---|
| UI (all screens, widgets) | ✅ Complete |
| Settings persistence | ✅ Complete |
| IndexService / SearchService wiring to FtsLib | ⚠️ Stubbed — real calls are TODO comments |
| FtsLib Dart library | ⚠️ Partially translated — SegmentWriter, SegmentReader, FuzzyExpander still need translating from binary C# files |

The UI is fully exercisable with the stub data. Once the remaining FtsLib
files are translated, replace the `_stubBuild` / `_stubSearch` methods in
`lib/services/index_service.dart` with real `SeforimIndex` calls.

## Running

Requires Flutter SDK ≥ 3.10.

```
cd FtsLibFlutterDemo
flutter pub get
flutter run -d windows
```

## Wiring up the real library

In `lib/services/index_service.dart`, replace the stub methods:

```dart
// Build — replace _stubBuild with:
final index = SeforimIndex(indexPath, dbPath);
await index.buildIndex(
  onProgress: (n) => onProgress(n, totalLines),
  isCancelled: isCancelled,
);

// Search — replace _stubSearch with:
for (final result in _index!.search(query, ct: ...)) {
  final snippet = _index!.generateSnippet(result);
  if (!snippet.isMatch || snippet.wordDistance > maxWordDistance) continue;
  yield SearchResultItem(lineId: result.lineId, bookTitle: result.bookTitle, snippet: snippet.html);
}
```
