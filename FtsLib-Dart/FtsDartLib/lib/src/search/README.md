# search/

Query parsing and search execution.

## Overview

This module handles the full search pipeline:

1. **Query Parsing** — Convert query string into structured operations
2. **Term Expansion** — Expand wildcards/fuzzy terms to literal terms
3. **Posting Retrieval** — Load document lists for each term
4. **Intersection** — Find documents matching all AND terms
5. **Result Streaming** — Yield results lazily for memory efficiency

## Files

| File | Purpose |
|---|---|
| `query_parser.dart` | Parse query syntax (AND, OR, wildcards, fuzzy) |
| `index_reader.dart` | `IndexReader` — read term dictionaries and posting lists |
| `posting_intersector.dart` | Fast AND intersection of multiple posting lists |
| `posting_iterator.dart` | Iterator over a single posting list |
| `posting_stream.dart` | Buffered posting list reading |
| `concat_iterator.dart` | Concatenate iterators (for OR expansion) |
| `union_iterator.dart` | Merge-sorted union of iterators |
| `filtering_iterator.dart` | Filter iterator with predicate |
| `proximity_window.dart` | Track term proximity for snippet scoring |
| `roaring_bitmap.dart` | Compressed bitmap for document sets |
| `roaring_bitmap_iterator.dart` | Iterator over roaring bitmap |
| `hebrew_wildcard_expander.dart` | Expand Hebrew wildcard patterns |
| `fuzzy_expander.dart` | Levenshtein-based fuzzy expansion |
| `ketiv_expander.dart` | Hebrew ketiv/qere variant expansion |
| `levenshtein.dart` | Levenshtein distance calculation |
| `var_int.dart` | Variable-length integer encoding/decoding |

## Query Syntax Support

| Syntax | Handler |
|---|---|
| `word` | Literal term |
| `word*` | `HebrewWildcardExpander` |
| `wor?d` | `HebrewWildcardExpander` (optional char) |
| `word~` / `word~2` | `FuzzyExpander` |
| `a \| b` | `ConcatIterator` + `UnionIterator` |

## Key Classes

**`IndexReader`** — Main entry point for search:
```dart
final reader = IndexReader(store);
final postings = reader.getPostings(term);
```

**`PostingIntersector`** — Efficient AND intersection using skip lists.

**`QueryParser`** — Produces a tree of `QueryToken` objects for execution.

## Bitmap Operations

`RoaringBitmap` provides compressed storage of document ID sets for:
- Cached wildcard expansions
- Intermediate result sets
- Fast set operations (union, intersection)
