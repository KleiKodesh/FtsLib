import 'dart:io';
import 'package:fts_lib/fts_lib.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('Testing basic FtsLib Dart functionality...');

  // Initialize FFI
  sqfliteFfiInit();

  // Test 1: Basic ZayitDb functionality
  print('\n1. Testing ZayitDb...');
  try {
    final zayitDb = ZayitDb(null); // Uses default path resolution
    await zayitDb.open();

    if (zayitDb.isOpen) {
      print('   ✓ ZayitDb opened successfully');
      final lineCount = await zayitDb.countLines();
      print('   ✓ Database contains $lineCount lines');
    } else {
      print('   ⚠ ZayitDb could not open - database file may not exist');
    }

    zayitDb.dispose();
  } catch (e) {
    print('   ✗ ZayitDb test failed: $e');
  }

  // Test 2: Basic RAM index functionality
  print('\n2. Testing RAM index...');
  try {
    final ramIndex = RamIndex();

    // Add some test documents
    ramIndex.add('test', 1);
    ramIndex.add('document', 1);
    ramIndex.add('hebrew', 2);
    ramIndex.add('text', 2);

    print('   ✓ RAM index created with ${ramIndex.count} terms');
    print('   ✓ Term "test" appears ${ramIndex.getCount('test')} times');
    print('   ✓ Term "hebrew" appears ${ramIndex.getCount('hebrew')} times');
  } catch (e) {
    print('   ✗ RAM index test failed: $e');
  }

  // Test 3: Index directory operations
  print('\n3. Testing index directory...');
  try {
    // Check if directory exists (create if needed)
    final dir = Directory('./test_index');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      print('   ✓ Created test index directory');
    } else {
      print('   ✓ Test index directory exists');
    }

    // Test IndexWriter (extends IndexDirectory, takes string path)
    IndexWriter('./test_index');
    print('   ✓ IndexWriter created');

    // Test IndexReader if index files exist
    final datFile = File('./test_index/segment_0.dat');
    final dbFile = File('./test_index/segment_0.db');
    if (await datFile.exists() && await dbFile.exists()) {
      await IndexReader.openFromDir('./test_index');
      print('   ✓ IndexReader created (index files found)');
    } else {
      print('   ⚠ IndexReader not tested (no index files found)');
    }
  } catch (e) {
    print('   ✗ Index directory test failed: $e');
  }

  // Cleanup
  try {
    final dir = Directory('./test_index');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      print('\n✓ Test directory cleaned up');
    }
  } catch (e) {
    print('\nWarning: Could not clean up test directory: $e');
  }

  print('\nBasic FtsLib Dart test completed!');
}
