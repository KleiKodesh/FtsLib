# widgets/

Reusable UI components.

## Files

| File | Purpose |
|---|---|
| `result_card.dart` | Search result card with highlighted snippet |
| `syntax_help_sheet.dart` | Bottom sheet with query syntax reference |

## ResultCard

Displays a single search result:

### Layout
```
┌─────────────────────────────┐
│  Book Title (bold)          │
│  ─────────────────────      │
│  Snippet with <mark> tags   │
│  rendered as bold text      │
└─────────────────────────────┘
```

### Features
- RTL text direction for Hebrew
- `<mark>` elements styled as bold
- Card elevation for visual separation
- Responsive width

### Usage
```dart
ResultCard(
  bookTitle: result.bookTitle,
  snippetHtml: result.snippetHtml,
)
```

## SyntaxHelpSheet

Modal bottom sheet explaining query syntax:

### Sections
1. **Basic search** — Literal terms, AND by default
2. **Wildcards** — `*` for prefix/infix/suffix
3. **Optional characters** — `?` makes preceding char optional
4. **Fuzzy** — `~` for edit distance 1-3
5. **OR operator** — `|` for alternatives
6. **Examples** — Real-world Hebrew search examples

### Features
- Scrollable content
- Dismiss on tap outside
- Close button in header
- RTL layout throughout

### Usage
```dart
showModalBottomSheet(
  context: context,
  builder: (_) => const SyntaxHelpSheet(),
);
```
