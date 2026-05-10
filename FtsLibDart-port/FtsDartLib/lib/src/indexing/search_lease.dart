/// Holds a read lock on [SegmentStore]'s search/merge exclusion lock
/// for the lifetime of one search.
///
/// In Dart (single-threaded isolate model) there is no ReaderWriterLockSlim.
/// Instead, SearchLease carries a callback that the SegmentStore registers
/// to be notified when the lease is disposed, so it can unblock any pending
/// merge that was waiting for all active readers to finish.
///
/// Obtain via [SegmentStore.acquireSearchLease].
/// Dispose as soon as the corresponding IndexReader is disposed.
class SearchLease {
  final void Function() _onDispose;
  bool _disposed = false;

  SearchLease(this._onDispose);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onDispose();
  }
}
