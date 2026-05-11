# seforim_db/

Public API facade for the seforim full-text search.

## Overview

This module provides the high-level API that applications use. It combines:
- **Indexing** — Building the search index from SQLite
- **Search** — Query execution
- **Snippets** — Highlighted result generation
- **Database Access** — Reading content from Zayit SQLite DB

## Files

| File | Purpose |
|---|---|
| `seforim_index.dart` | Main API — `SeforimIndex` class |
| `search_result.dart` | Result type — `SearchResult` |
| `snippet_result.dart` | Snippet type — `SnippetResult` |
| `search_pipeline.dart` | Search orchestration |
| `indexing_pipeline.dart` | Index building orchestration |
| `snippet_pipeline.dart` | Snippet generation orchestration |
| `zayit_db.dart` | SQLite database access layer |

## Public API

### SeforimIndex

```dart
final index = SeforimIndex(indexPath, dbPath);

// Build
await index.buildIndex(onProgress: (n) => ...);

// Search
for (final result in index.search("שלום תורה")) {
    print('${result.bookTitle}: ${result.content}');
}

// Snippet
final snippet = index.generateSnippet(result);
if (snippet.isMatch) {
    print(snippet.html); // Highlighted with <mark> tags
}
```

### SearchResult

| Property | Type | Description |
|---|---|---|
| `lineId` | `int` | Line ID in the database |
| `bookTitle` | `String` | Book the line belongs to |
| `content` | `String` | Raw HTML content |
| `matchedGroups` | `List<List<String>>` | Expanded term groups per query token |

### SnippetResult

| Property | Type | Description |
|---|---|---|
| `html` | `String` | Highlighted HTML with `<mark>` tags |
| `score` | `int` | Character span of tightest window (smaller = better) |
| `wordDistance` | `int` | Token count between leftmost/rightmost matches |
| `isMatch` | `bool` | False = index false positive |

## Database Schema (Zayit)

The `ZayitDb` class expects a SQLite database with:
- `Lines` table: `LineId`, `BookId`, `HtmlContent`, `SortOrder`
- `Books` table: `BookId`, `BookTitle`, `ShortName`

See `zayit_db.dart` for query details.
