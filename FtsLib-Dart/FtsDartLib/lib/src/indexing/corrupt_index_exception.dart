/// Thrown when a segment file is corrupt and cannot be recovered.
/// The caller should delete the entire index directory and trigger a clean rebuild.
class CorruptIndexException implements Exception {
  final String message;
  final Object? innerException;

  CorruptIndexException(this.message, [this.innerException]);

  @override
  String toString() => 'CorruptIndexException: $message';
}
