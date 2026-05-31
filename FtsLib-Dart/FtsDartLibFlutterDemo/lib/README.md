# lib/

Flutter demo application source code.

## Structure

```
lib/
├── main.dart           ← App entry point
├── screens/            ← Full-screen UI pages
├── services/           ← Business logic layer
└── widgets/            ← Reusable UI components
```

## Architecture

Follows a service-based architecture:

- **`IndexService`** — Handles index building, progress tracking, cancellation
- **`SettingsService`** — Persists user preferences (last DB path)

UI layers:
- **Screens** — Main screen with search and indexing UI
- **Widgets** — Reusable components (result cards, help sheets)

## Entry Point

`main.dart` initializes:
1. Services (IndexService, SettingsService)
2. MainScreen with dependency injection

## RTL Support

The entire UI is RTL (Right-to-Left) for Hebrew text:
```dart
directionality: TextDirection.rtl,
```

## Stubs vs Real Implementation

Currently uses stub data. To wire up real FtsLib:

In `services/index_service.dart`, replace `_stubBuild` and `_stubSearch` with actual `SeforimIndex` calls (see `README.md` in parent folder for details).
