import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() async {
  print('Testing SQLite integration...');

  // Initialize FFI
  sqfliteFfiInit();

  // Test 1: Async SQLite with sqflite_common_ffi
  print('\n1. Testing async SQLite (sqflite_common_ffi)...');
  try {
    final db = await databaseFactoryFfi.openDatabase(
      'test_async.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db
              .execute('CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)');
        },
      ),
    );

    await db.insert('test', {'name': 'Test Entry'});
    final results = await db.query('test');
    print('   ✓ Async test successful: ${results.length} records');

    await db.close();
  } catch (e) {
    print('   ✗ Async test failed: $e');
  }

  // Test 2: Sync SQLite with sqlite3 package
  print('\n2. Testing sync SQLite (sqlite3 package)...');
  try {
    final db = sqlite3.sqlite3.open('test_sync.db');
    db.execute(
        'CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, name TEXT)');
    db.execute('INSERT INTO test (name) VALUES (?)', ['Sync Test Entry']);

    final result = db.select('SELECT * FROM test');
    print('   ✓ Sync test successful: ${result.length} records');

    db.dispose();
  } catch (e) {
    print('   ✗ Sync test failed: $e');
  }

  // Test 3: Test PRAGMA settings like in ZayitDb
  print('\n3. Testing PRAGMA settings...');
  try {
    final db = await databaseFactoryFfi.openDatabase('test_pragma.db');
    await db.execute('PRAGMA journal_mode=WAL; '
        'PRAGMA cache_size=-65536; '
        'PRAGMA temp_store=MEMORY; '
        'PRAGMA mmap_size=268435456;');
    print('   ✓ PRAGMA settings applied successfully');
    await db.close();
  } catch (e) {
    print('   ✗ PRAGMA test failed: $e');
  }

  // Cleanup test files
  try {
    File('test_async.db').deleteSync();
    File('test_sync.db').deleteSync();
    File('test_pragma.db').deleteSync();
    print('\n✓ Test files cleaned up');
  } catch (e) {
    print('\nWarning: Could not clean up test files: $e');
  }

  print('\nSQLite integration test completed!');
}
