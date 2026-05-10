import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

/// Forward-only reader for a sorted segment file.
/// Reads one term at a time in ascending term order.
///
/// Segment record format (per term):
///   4 bytes  int    termByteLen
///   N bytes         term (UTF-8)
///   4 bytes  int    chunkByteLen
///   4 bytes  int    docCount
///   4 bytes  uint   lastEncoded
///   4 bytes  int    skipCount
///   skipCount × 12 bytes  skip table (int32 docId, int32 byteOffset, int32 prevEncoded)
///   M bytes         varint posting data
class SegmentReader {
  final RandomAccessFile _fs;

  // Cached file length — read once at open time.
  final int _fileLength;

  String? _currentTerm;
  List<int>? _currentChunk;
  int _currentChunkLen = 0;
  int _currentCount = 0;
  int _currentLastEncoded = 0;
  List<int>? _currentSkip;
  int _currentSkipLen = 0;
  bool _done = false;

  String get currentTerm => _currentTerm!;
  List<int> get currentChunk => _currentChunk!;
  int get currentChunkLen => _currentChunkLen;
  int get currentCount => _currentCount;
  int get currentLastEncoded => _currentLastEncoded;
  List<int>? get currentSkip => _currentSkip;
  int get currentSkipLen => _currentSkipLen;
  bool get done => _done;

  SegmentReader._(this._fs, this._fileLength);

  /// Opens a segment reader synchronously.
  factory SegmentReader(String path) {
    final fs = File(path).openSync(mode: FileMode.read);
    final length = fs.lengthSync();
    return SegmentReader._(fs, length);
  }

  bool moveNext() {
    if (_done || _fs.positionSync() >= _fileLength) {
      _done = true;
      return false;
    }

    // termByteLen (4 bytes LE)
    final termLenBuf = _readBytes(4);
    final termLen = _readInt32LE(termLenBuf, 0);
    if (termLen < 0 || termLen > 4096) {
      throw FormatException(
          'Corrupt segment: invalid termLen $termLen at offset ${_fs.positionSync() - 4}');
    }

    // term bytes
    final termBytes = _readBytes(termLen);

    // chunkByteLen
    final chunkLenBuf = _readBytes(4);
    final chunkLen = _readInt32LE(chunkLenBuf, 0);
    if (chunkLen < 0 || chunkLen > 64 * 1024 * 1024) {
      throw FormatException(
          'Corrupt segment: invalid chunkLen $chunkLen at offset ${_fs.positionSync() - 4}');
    }

    // docCount
    final countBuf = _readBytes(4);
    final count = _readInt32LE(countBuf, 0);

    // lastEncoded (uint32)
    final lastEncBuf = _readBytes(4);
    final lastEncoded = _readUint32LE(lastEncBuf, 0);

    // skipCount
    final skipCountBuf = _readBytes(4);
    final skipCount = _readInt32LE(skipCountBuf, 0);
    final skipLen = skipCount * 3;

    // skip table
    List<int>? skip;
    if (skipCount > 0) {
      final skipBuf = _readBytes(skipLen * 4);
      skip = List<int>.filled(skipLen, 0);
      for (int i = 0; i < skipLen; i++) {
        skip[i] = _readInt32LE(skipBuf, i * 4);
      }
    }

    // posting data
    final chunk = _readBytes(chunkLen);

    _currentTerm = utf8.decode(termBytes);
    _currentChunk = chunk;
    _currentChunkLen = chunkLen;
    _currentCount = count;
    _currentLastEncoded = lastEncoded;
    _currentSkip = skip;
    _currentSkipLen = skipLen;

    return true;
  }

  void dispose() {
    _fs.closeSync();
  }

  // ── Helpers ──────────────────────────────────────────────────

  List<int> _readBytes(int count) {
    final buf = _fs.readSync(count);
    if (buf.length < count) {
      throw FormatException(
          'Corrupt segment: unexpected end of file (wanted $count bytes, got ${buf.length})');
    }
    return buf;
  }

  static int _readInt32LE(List<int> buf, int offset) {
    final u = buf[offset] |
        (buf[offset + 1] << 8) |
        (buf[offset + 2] << 16) |
        (buf[offset + 3] << 24);
    // Sign-extend from 32 bits
    return u >= 0x80000000 ? u - 0x100000000 : u;
  }

  static int _readUint32LE(List<int> buf, int offset) {
    return (buf[offset] |
            (buf[offset + 1] << 8) |
            (buf[offset + 2] << 16) |
            (buf[offset + 3] << 24)) &
        0xFFFFFFFF;
  }
}
