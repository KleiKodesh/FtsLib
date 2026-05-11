# screens/

Full-screen UI pages.

## Files

| File | Purpose |
|---|---|
| `main_screen.dart` | Primary screen with search, results, and indexing UI |

## MainScreen

The single-screen app design includes:

### Search Section
- Query text field with RTL support
- Syntax help button
- Max word distance slider
- Order/unordered toggle
- Search button with loading state

### Results Section  
- Scrollable result list
- Result cards with highlighted snippets
- Book title and snippet display
- Empty state when no results

### Indexing Section
- DB file picker
- Index path display
- Build index button
- Progress bar with ETA
- Cancel button

### Help Sheet
- Bottom sheet explaining query syntax
- Examples for wildcards, fuzzy, OR
- Dismissible

## State Management

`MainScreen` uses Flutter's built-in `setState` for simplicity. For larger apps, consider:
- `Provider`
- `Riverpod`
- `Bloc`

## RTL Layout

All text fields and lists use `TextDirection.rtl` for proper Hebrew text handling.
