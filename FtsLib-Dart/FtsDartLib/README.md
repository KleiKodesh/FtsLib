# FtsDartLib

Core Dart library for Hebrew/Aramaic full-text search.

## Overview

A Dart port of the C# FtsLib engine. Designed for AOT compilation to native code for maximum performance in Flutter desktop apps.

## Architecture

The library follows the same LSM-tree architecture as the C# version:

1. **Indexing** — Write-ahead log → in-memory RAM index → segment files → background merging
2. **Search** — Query parsing → term expansion → posting list intersection → result streaming
3. **Snippets** — Proximity scoring → HTML highlighting with `<mark>` tags

## Folder Layout

```
lib/
├── fts_lib.dart           ← Public exports
└── src/
    ├── indexing/          ← Index building & segment management
    ├── search/            ← Query parsing & execution
    ├── seforim_db/        ← High-level API (SeforimIndex)
    ├── snippets/          ─ Snippet generation
    └── tokenization/      ← HTML word scanning
```

## Key Files

| File | Purpose |
|---|---|
| `seforim_db/seforim_index.dart` | Main entry point — `SeforimIndex` class |
| `indexing/index_writer.dart` | Build index from SQLite DB |
| `indexing/segment_store.dart` | Segment file management |
| `search/index_reader.dart` | Read posting lists from segments |
| `search/query_parser.dart` | Parse query syntax |
| `search/posting_intersector.dart` | AND intersection of posting lists |
| `snippets/snippet_builder.dart` | Generate highlighted snippets |

## Compilation

### JIT (development)
```bash
dart run
```

### AOT (production)
```bash
# Windows
compile_aot.bat

# Linux/macOS  
./compile_aot.sh
```

The AOT binary can be bundled with Flutter apps for native-speed search.

## Dependencies

```yaml
dependencies:
  sqlite3: ^2.0.0    ← For DB access ( FFI )
  path: ^1.8.0       ← Path manipulation
```

See `pubspec.yaml` for full dependency list.

## Status

This is a work-in-progress translation from C#. Check `FtsDartLibFlutterDemo/README.md` for the current translation status of each module.
