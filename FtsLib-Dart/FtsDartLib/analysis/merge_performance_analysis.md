# Merge Performance Analysis: C# vs Dart

## Key Performance Differences Identified

### 1. **Memory Management & Buffer Operations**

**C# (Fast):**
```csharp
// Uses native byte arrays and Buffer.BlockCopy
byte[] mergeBuffer = new byte[256];
Buffer.BlockCopy(chunk, 0, buf, pos, chunkLen);  // Native memory copy
```

**Dart (Slow):**
```dart
// Uses List<int> and setRange for byte operations
var mergeBuffer = List<int>.filled(256, 0, growable: true);
buf.setRange(pos, pos + chunkLen, chunk);  // Higher-level operation
```

**Impact:** `Buffer.BlockCopy` is a highly optimized native memory copy, while Dart's `setRange` involves more overhead.

### 2. **File I/O Operations**

**C# (Fast):**
```csharp
// Large buffer size and optimized FileStream
using (var outFs = new FileStream(outPath, FileMode.Create,
                                  FileAccess.Write, FileShare.None,
                                  bufferSize: 4 * 1024 * 1024))
using (var bw = new BinaryWriter(outFs, Encoding.UTF8, leaveOpen: false))
```

**Dart (Slow):**
```dart
// Smaller default buffer and synchronous operations
final sink = File(outPath).openSync(mode: FileMode.writeOnly);
sink.writeFromSync(_int32LE(termByteLen));  // Individual small writes
```

**Impact:** C# uses a 4MB buffer with optimized BinaryWriter, while Dart does many small individual writes.

### 3. **Array Pooling & Memory Allocation**

**C# (Fast):**
```csharp
// Uses ArrayPool to reuse byte arrays
byte[] termBytes = ArrayPool<byte>.Shared.Rent(termByteLen);
Encoding.UTF8.GetBytes(minTerm, 0, minTerm.Length, termBytes, 0);
ArrayPool<byte>.Shared.Return(termBytes);
```

**Dart (Slow):**
```dart
// Creates new arrays each time
final termBytes = utf8.encode(minTerm);  // New allocation every term
```

**Impact:** C# reuses memory from a pool, while Dart allocates new memory for each term.

### 4. **String Encoding**

**C# (Fast):**
```csharp
// Pre-calculated byte count with pooled array
int termByteLen = Encoding.UTF8.GetByteCount(minTerm);
byte[] termBytes = ArrayPool<byte>.Shared.Rent(termByteLen);
Encoding.UTF8.GetBytes(minTerm, 0, minTerm.Length, termBytes, 0);
```

**Dart (Slow):**
```dart
// Creates new byte array each time
final termBytes = utf8.encode(minTerm);
```

**Impact:** C# avoids allocation overhead through pooling.

### 5. **Skip Table Management**

**C# (Fast):**
```csharp
// Efficient array resizing
if (skipTable == null) skipTable = new int[12];
else if (skipLen + 3 > skipTable.Length)
    Array.Resize(ref skipTable, skipTable.Length * 2);
```

**Dart (Slow):**
```dart
// Creates new array and copies elements manually
if (skipLen + 3 > skipTable.length) {
  final newSkip = List<int>.filled(skipTable.length * 2, 0, growable: true);
  for (int i = 0; i < skipLen; i++) newSkip[i] = skipTable[i];
  skipTable = newSkip;
}
```

**Impact:** C# `Array.Resize` is more efficient than manual copying.

### 6. **Data Structure Differences**

**C# (Fast):**
- Uses `byte[]` for binary data
- `Buffer.BlockCopy` for fast memory operations
- Native `FileStream` with large buffers
- `ArrayPool<T>` for memory reuse

**Dart (Slow):**
- Uses `List<int>` for binary data (less efficient)
- `setRange()` operations (higher overhead)
- Smaller file I/O buffers
- No built-in array pooling

## Performance Optimization Recommendations for Dart

### 1. **Use TypedData for Binary Operations**
```dart
// Instead of List<int>
final mergeBuffer = Uint8List(256);
// Use setRange on Uint8List for better performance
```

### 2. **Implement Array Pooling**
```dart
class ByteArrayPool {
  static final Map<int, Queue<Uint8List>> _pools = {};
  
  static Uint8List rent(int size) {
    final pool = _pools[size] ??= Queue<Uint8List>();
    return pool.isNotEmpty ? pool.removeFirst() : Uint8List(size);
  }
  
  static void return(Uint8List array) {
    _pools[array.length]?.add(array);
  }
}
```

### 3. **Optimize File I/O**
```dart
// Use larger buffer size
final sink = File(outPath).openSync(mode: FileMode.writeOnly);
// Batch writes instead of individual small writes
final writeBuffer = Uint8List(1024 * 1024); // 1MB buffer
```

### 4. **Reduce Memory Allocations**
```dart
// Reuse buffers instead of creating new ones
class MergeContext {
  final Uint8List mergeBuffer = Uint8List(256);
  final Uint8List tempBuffer = Uint8List(64);
  final List<int> skipTable = [];
}
```

### 5. **Use Native Extensions for Critical Paths**
Consider using Dart FFI for performance-critical operations like:
- Memory copying
- File I/O
- String encoding

## Estimated Performance Impact

Based on the analysis, the main bottlenecks in Dart are:

1. **Memory Operations**: 2-3x slower due to List<int> vs byte[]
2. **File I/O**: 2-4x slower due to small buffers and individual writes
3. **Memory Allocation**: 3-5x slower due to lack of pooling
4. **String Operations**: 2-3x slower due to repeated allocations

**Overall estimated performance difference: 5-10x slower for Dart**

## Implementation Priority

1. **High Impact, Low Effort**: Switch to Uint8List, increase file buffer size
2. **High Impact, Medium Effort**: Implement array pooling
3. **Medium Impact, High Effort**: FFI for critical operations
4. **Low Impact, Low Effort**: Optimize skip table management
