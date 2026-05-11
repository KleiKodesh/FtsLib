# services/

Business logic and state management services.

## Files

| File | Purpose |
|---|---|
| `index_service.dart` | Index building and search operations |
| `settings_service.dart` | User preferences persistence |

## IndexService

Coordinates between UI and FtsLib:

### Methods

| Method | Purpose |
|---|---|
| `buildIndex(dbPath, indexPath, onProgress, isCancelled)` | Build full-text index with progress callbacks |
| `search(query, maxWordDistance, ordered, onResult)` | Execute search and yield results |
| `loadExistingIndex(indexPath)` | Open existing index without building |
| `cancelBuild()` | Cancel in-progress index build |

### Current Implementation

⚠️ **Uses stub data** — Real FtsLib calls are commented out with `TODO` markers.

To enable real implementation:
```dart
// Replace _stubBuild with:
final index = SeforimIndex(indexPath, dbPath);
await index.buildIndex(onProgress: onProgress, isCancelled: isCancelled);

// Replace _stubSearch with:
for (final result in _index!.search(query)) {
    final snippet = _index!.generateSnippet(result);
    if (!snippet.isMatch || snippet.wordDistance > maxWordDistance) continue;
    yield result;
}
```

## SettingsService

Persist user preferences using `SharedPreferences`:

| Preference | Key | Type |
|---|---|---|
| Last DB path | `lastDbPath` | `String?` |

### Methods

- `loadLastDbPath()` — Load saved path
- `saveLastDbPath(path)` — Save path for next session
