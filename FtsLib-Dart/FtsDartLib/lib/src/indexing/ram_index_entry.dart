import '../search/posting_stream.dart';

/// Per-term in-memory entry: compressed posting stream + skip list.
class RamIndexEntry {
  static const int _skipInterval = 128;

  final PostingStream stream = PostingStream();
  List<int>? skip;
  int skipLen = 0;

  final bool _useSkipList;

  RamIndexEntry({bool useSkipList = true}) : _useSkipList = useSkipList;

  void add(int lineId) {
    int newCount = stream.count + 1;

    if (_useSkipList && newCount > 1 && (newCount - 1) % _skipInterval == 0) {
      skip ??= List<int>.filled(12, 0, growable: true);
      if (skipLen + 3 > skip!.length) {
        final newSkip = List<int>.filled(skip!.length * 2, 0, growable: true);
        for (int i = 0; i < skipLen; i++) newSkip[i] = skip![i];
        skip = newSkip;
      }

      skip![skipLen] = lineId;
      skip![skipLen + 1] = stream.nextByteOffset; // byte offset BEFORE writing
      skip![skipLen + 2] = stream.lastEncoded;    // encoded value of PREVIOUS entry
      skipLen += 3;
    }

    stream.add(lineId);
  }
}
