import 'dart:io';
import 'package:path/path.dart' as p;

/// Base class that holds the index path and common path helpers.
class IndexDirectory {
  final String indexPath;

  /// Sorted varint-delta file that records logically deleted doc IDs.
  /// Absent when no deletions have been made.
  String get deletesFile => p.join(indexPath, 'deletes.bin');

  IndexDirectory(String indexPath)
      : indexPath = indexPath.isNotEmpty ? indexPath : p.join(Directory.current.path, 'fts-index') {
    final dir = Directory(this.indexPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }
}
