import 'dart:io';

/// Thrown when [IndexWriteLock] cannot acquire the exclusive write lock on an
/// index directory because another process is already writing to that directory.
class IndexWriteLockException implements Exception {
  final String indexPath;
  IndexWriteLockException(this.indexPath);

  @override
  String toString() =>
      'IndexWriteLockException: Another process is already writing to the index directory: $indexPath';
}

/// Exclusive write lock for an index directory, backed by an OS file lock.
///
/// Opens [write.lock] inside the index directory with exclusive access.
/// The OS holds the lock for the lifetime of the [RandomAccessFile] — it is
/// released automatically on [dispose] or if the process crashes, so no stale
/// lock files can block a subsequent run.
///
/// Throws [IndexWriteLockException] immediately if the lock is already held.
class IndexWriteLock {
  static const String _lockFileName = 'write.lock';

  RandomAccessFile? _lockFile;

  IndexWriteLock(String indexPath) {
    final dir = Directory(indexPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final lockFilePath =
        '$indexPath${Platform.pathSeparator}$_lockFileName';

    try {
      // Open with exclusive lock — throws if already locked.
      _lockFile = File(lockFilePath).openSync(mode: FileMode.writeOnlyAppend);
      _lockFile!.lockSync(FileLock.exclusive);
    } on FileSystemException {
      throw IndexWriteLockException(indexPath);
    }
  }

  void dispose() {
    try {
      _lockFile?.unlockSync();
      _lockFile?.closeSync();
    } catch (_) {
      // best-effort — lock is released when the file is GC'd anyway
    }
    _lockFile = null;
  }
}
