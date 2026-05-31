# indexing/

Index construction and segment management.

## Overview

This module handles building the full-text index from an SQLite database. It uses an LSM-tree architecture:

1. **Write-Ahead Log (WAL)** — Crash-safe in-memory buffer
2. **RAM Index** — In-memory hash map for fast indexing
3. **Segment Files** — Immutable on-disk index files
4. **Background Merging** — Combines small segments into larger ones

## Files

| File | Purpose |
|---|---|
| `index_writer.dart` | Main API — `IndexWriter` class for building indexes |
| `segment_store.dart` | `SegmentStore` — manages segment file lifecycle |
| `segment_writer.dart` | Writes posting lists to segment files (delta+varint encoding) |
| `segment_reader.dart` | Reads posting lists from segments |
| `segment_merger.dart` | Merges multiple segments into one (background compaction) |
| `segment_live_state.dart` | Tracks segment metadata and merge state |
| `segment_handle.dart` | Reference-counted segment access |
| `segment_wal.dart` | Write-ahead log for crash recovery |
| `ram_index.dart` | In-memory index buffer |
| `ram_index_entry.dart` | Entry in the RAM index |
| `delete_set.dart` | Tracks deleted documents for segment merging |
| `index_directory.dart` | Directory layout utilities |
| `index_write_lock.dart` | Prevents concurrent index writes |
| `search_lease.dart` | Allows searches during index modification |

## Exceptions

- `CorruptIndexException` — Segment data corruption detected
- `IndexMergingException` — Error during segment merge

## Key Concepts

**Segment:** An immutable index file containing term→postings mappings for a subset of documents.

**Posting List:** A sorted list of document IDs containing a specific term, stored as delta-encoded varints for compression.

**Merge Policy:** Small segments are merged into larger ones in the background to maintain query performance and control file count.

## Usage

```dart
final store = SegmentStore(indexPath);
final writer = IndexWriter(store, db);
writer.buildIndex(onProgress: (n) => print('$n lines'));
```
