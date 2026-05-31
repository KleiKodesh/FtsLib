# FtsLib-Dart

Dart/Flutter implementation of the FtsLib Hebrew full-text search library.

## Structure

```
FtsLib-Dart/
├── FtsDartLib/              ← Core Dart library
│   ├── lib/                 ← Library source code
│   │   ├── fts_lib.dart     ← Public API export
│   │   └── src/             ← Implementation
│   │       ├── indexing/    ← Index building (segments, WAL, merging)
│   │       ├── search/      ← Query execution (parsing, iterators, bitmaps)
│   │       ├── seforim_db/  ← Public API (SeforimIndex)
│   │       ├── snippets/    ← Snippet generation & highlighting
│   │       └── tokenization/← HTML tokenization
│   ├── bin/                 ← CLI entry point
│   ├── compile_aot.bat      ← Windows AOT compile script
│   ├── compile_aot.sh       ← Linux/macOS AOT compile script
│   └── pubspec.yaml         ← Package manifest
│
└── FtsDartLibFlutterDemo/   ← Flutter demo application
    ├── lib/
    │   ├── screens/         ← UI screens
    │   ├── services/        ← Index/Search services
    │   ├── widgets/         ← Reusable UI components
    │   └── main.dart        ← App entry point
    ├── windows/             ← Windows desktop support
    ├── pubspec.yaml
    └── README.md            ← Detailed demo documentation
```

## Status

| Layer | Status |
|---|---|
| Core data structures (SegmentStore, IndexWriter) | ✅ Complete |
| Query parsing & bitmap operations | ✅ Complete |
| Hebrew wildcard/fuzzy expanders | ⚠️ Partial |
| FtsDartLib full translation | ⚠️ In progress |
| Flutter demo UI | ✅ Complete |

## Building

### Library
```bash
cd FtsDartLib
dart pub get

# Run tests
dart test

# AOT compile (Windows)
compile_aot.bat

# AOT compile (Linux/macOS)
./compile_aot.sh
```

### Flutter Demo
```bash
cd FtsDartLibFlutterDemo
flutter pub get
flutter run -d windows
```

## Public API

See `FtsDartLibFlutterDemo/README.md` for usage examples once the library is fully translated.

## Translation Notes

This is a line-by-line translation of the C# implementation. File names are converted to snake_case:
- `IndexWriter.cs` → `index_writer.dart`
- `SegmentStore.cs` → `segment_store.dart`

Core algorithms remain identical to ensure cross-platform consistency.
