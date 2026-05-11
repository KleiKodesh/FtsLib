# snippets/

Snippet generation with search term highlighting.

## Overview

Generates highlighted text excerpts showing search results in context. Finds the tightest window containing all query terms and wraps matches in `<mark>` tags.

## Files

| File | Purpose |
|---|---|
| `snippet_builder.dart` | `SnippetBuilder` — main snippet generation logic |
| `snippet_result.dart` | `SnippetResult` — result data class |

## Algorithm

1. **Tokenize** the line content
2. **Locate** all occurrences of each search term
3. **Find** the tightest window containing at least one occurrence of each term
4. **Extend** window with context (neighboring words)
5. **Render** with `<mark>` tags around matched terms
6. **Score** by character span and word distance

## Usage

```dart
// From SearchResult (preferred)
final snippet = index.generateSnippet(result);

// From lineId + query (fallback)
final snippet = index.generateSnippet(lineId, "שלום תורה");

if (snippet.isMatch) {
    print(snippet.html);
    print('Score: ${snippet.score}');
}
```

## Scoring

- **Score** — Character span of the tightest matching window (lower is better)
- **WordDistance** — Number of tokens between leftmost and rightmost matches

These scores help rank results by proximity of terms.

## HTML Output

Example output:
```html
...השלום <mark>בית</mark> של <mark>תורה</mark>...
```

The `<mark>` elements can be styled in your app:
```css
mark {
    background-color: yellow;
    font-weight: bold;
}
```

## False Positives

`isMatch` may be `false` when:
- The index contained the term but the document doesn't (rare, due to index updates)
- All terms were removed by HTML tag stripping

Always check `isMatch` before displaying a snippet.
