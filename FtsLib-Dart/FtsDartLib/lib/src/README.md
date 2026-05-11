# src/

Implementation modules for the FtsLib search engine.

## Modules

| Folder | Purpose | Key Classes |
|---|---|---|
| `indexing/` | Index construction & segment management | `IndexWriter`, `SegmentStore`, `SegmentWriter`, `SegmentMerger` |
| `search/` | Query parsing & execution | `QueryParser`, `IndexReader`, `PostingIntersector`, `FuzzyExpander`, `HebrewWildcardExpander` |
| `seforim_db/` | Public API facade | `SeforimIndex`, `SearchResult`, `SnippetResult`, `ZayitDb` |
| `snippets/` | Snippet generation | `SnippetBuilder`, `SnippetResult` |
| `tokenization/` | HTML text tokenization | `HtmlWordScanner`, `TokenStream`, `Tokenizer` |

## Module Dependencies

```
seforim_db/  →  indexing/, search/, snippets/
search/      →  indexing/ (SegmentReader, term dictionaries)
snippets/    →  search/ (query terms for highlighting)
indexing/    →  tokenization/ (text processing)
```

## Translation Status

Files are translated from C# to Dart on a per-file basis. See individual module READMEs for translation progress.

All files use Dart naming conventions:
- snake_case for file names
- PascalCase for class names
- camelCase for method/variable names
