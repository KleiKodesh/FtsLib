# tokenization/

HTML text tokenization for indexing and search.

## Overview

Converts HTML content into searchable word tokens while:
- Stripping HTML tags
- Handling Hebrew/Aramaic RTL text
- Preserving word boundaries
- Tracking positions for snippet alignment

## Files

| File | Purpose |
|---|---|
| `html_word_scanner.dart` | `HtmlWordScanner` — scans words from HTML |
| `token_stream.dart` | `TokenStream` — provides token iterator |
| `tokenizer.dart` | `Tokenizer` — main API for tokenization |

## HtmlWordScanner

Low-level HTML word scanner that:
1. Parses HTML character by character
2. Skips tags and attributes
3. Extracts text content
4. Identifies word boundaries
5. Handles HTML entities (`&nbsp;`, `&lt;`, etc.)

## TokenStream

Iterator-style access to tokens with:
- Current token access
- Advance to next token
- Position tracking (for snippet alignment)

## Tokenizer

High-level API:

```dart
final tokens = Tokenizer.tokenize(htmlContent);
for (final token in tokens) {
    print(token.word);     // The word text
    print(token.position); // Position in document
}
```

## HTML Block Tags

`HtmlBlockTags` defines which HTML elements should be treated as word separators (paragraphs, divs, tables, etc.). This ensures content across block boundaries isn't concatenated during search.
