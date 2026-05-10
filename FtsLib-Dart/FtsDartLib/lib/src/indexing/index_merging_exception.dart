/// Thrown by [SegmentStore.getLiveSegmentPaths] when a merge is currently in
/// progress and the caller requested a non-blocking snapshot.
/// The caller should surface this to the user as a temporary unavailability
/// rather than retrying silently.
class IndexMergingException implements Exception {
  @override
  String toString() =>
      'IndexMergingException: Index is currently merging segments — please try again in a moment.';
}
