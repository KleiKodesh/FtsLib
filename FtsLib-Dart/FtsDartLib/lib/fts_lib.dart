/// FtsLib — Dart port of the C# full-text search library.
///
/// Public API surface:
library fts_lib;

// SeforimDb (top-level public API)
export 'src/seforim_db/seforim_index.dart';
export 'src/seforim_db/search_result.dart';
export 'src/seforim_db/snippet_result.dart';

// Exceptions
export 'src/indexing/corrupt_index_exception.dart';
export 'src/indexing/index_merging_exception.dart';
export 'src/indexing/index_write_lock.dart' show IndexWriteLockException;
