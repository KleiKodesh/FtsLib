# lib/

Dart library source code.

## Files

- **`fts_lib.dart`** — Public API exports. Import this to use the library.

- **`src/`** — Implementation details (private, not exported directly).

## Usage

```dart
import 'package:fts_dart_lib/fts_lib.dart';

final index = SeforimIndex(indexPath, dbPath);
await index.buildIndex();
```

## Structure

```
lib/
├── fts_lib.dart
└── src/
    ├── indexing/     ← Segment-based index construction
    ├── search/       ← Query execution engine  
    ├── seforim_db/   ← Public API facade
    ├── snippets/     ← Snippet generation
    └── tokenization/ ← HTML text tokenization
```

Each `src/` subdirectory contains a `README.md` with module-specific documentation.
