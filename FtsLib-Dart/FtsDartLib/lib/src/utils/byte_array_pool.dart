import 'dart:typed_data';

/// High-performance byte array pool to reduce memory allocations.
/// Mirrors C# ArrayPool<byte>.Shared for optimal performance.
class ByteArrayPool {
  static final Map<int, List<Uint8List>> _pools = {};
  static const int _maxPoolSize = 50; // Limit pool size to prevent memory bloat

  /// Rent a byte array of at least the specified size.
  static Uint8List rent(int size) {
    final pool = _pools[size];
    if (pool != null && pool.isNotEmpty) {
      return pool.removeLast();
    }
    return Uint8List(size);
  }

  /// Return a byte array to the pool for reuse.
  static void return_(Uint8List array) {
    final size = array.length;
    final pool = _pools[size] ??= <Uint8List>[];
    if (pool.length < _maxPoolSize) {
      pool.add(array);
    }
  }

  /// Clear all pools (useful for testing or memory cleanup).
  static void clear() {
    _pools.clear();
  }
}

/// Optimized buffer management for merge operations.
class MergeBuffer {
  Uint8List _buffer;
  int _position = 0;

  MergeBuffer(int initialSize) : _buffer = Uint8List(initialSize);

  /// Ensure capacity for the required size.
  void ensureCapacity(int required) {
    if (required <= _buffer.length) return;
    
    // Double size until sufficient
    int newSize = _buffer.length;
    while (newSize < required) newSize *= 2;
    
    final newBuffer = Uint8List(newSize);
    newBuffer.setRange(0, _buffer.length, _buffer);
    _buffer = newBuffer;
  }

  /// Write data to buffer and advance position.
  void writeBytes(List<int> data, int length) {
    ensureCapacity(_position + length);
    _buffer.setRange(_position, _position + length, data);
    _position += length;
  }

  /// Write a single byte and advance position.
  void writeByte(int byte) {
    ensureCapacity(_position + 1);
    _buffer[_position++] = byte;
  }

  /// Get current buffer and reset position.
  Uint8List getAndReset() {
    final result = _buffer;
    _position = 0;
    return result;
  }

  /// Get current position.
  int get position => _position;

  /// Get buffer length.
  int get length => _buffer.length;

  /// Get view of buffer data up to current position.
  Uint8List get view => Uint8List.view(_buffer.buffer, 0, _position);
}
