# FST vs SQLite Performance Metrics

Generated: 2026-05-26 23:35:32

## Test Methodology

### What Was Tested

- **Exact Match**: Direct key lookup (e.g., searching for "abc")
- **Starts With**: Pattern matching for words beginning with a prefix (e.g., "ab*")
- **Ends With**: Pattern matching for words ending with a suffix (e.g., "*bc")
- **Contains**: Substring matching for words containing a pattern (e.g., "*ab*")
- **Fuzzy Search**: Levenshtein distance matching with maximum 1 edit distance

### How Tests Were Conducted

**Test Data**:
- 4 SQLite database files from the SqliteIndex folder
- Each database contains a word table with varying entry counts
- Test queries: 100 random words selected from each database

**FST Index Construction**:
- Forward FST built from sorted database entries
- Reverse FST built for efficient suffix/ends-with queries
- Both indices loaded into memory before benchmarking

**Benchmark Methodology**:
- Exact Match: 1000 iterations of random key lookups
- Starts With: 100 iterations using 10 distinct patterns
- Ends With: 100 iterations using 10 distinct patterns
- Contains: 100 iterations using 10 distinct patterns
- Fuzzy Search: 50 iterations with Levenshtein distance ≤ 1
- Each test includes warm-up iteration before timing

**SQLite Queries**:
- Exact Match: SELECT COUNT(*) WHERE word = @word
- Starts With: SELECT word FROM table WHERE word LIKE @pattern%
- Ends With: SELECT word FROM table WHERE word LIKE %@pattern
- Contains: SELECT word FROM table WHERE word LIKE %@pattern%
- Fuzzy Search: Full table scan with Levenshtein distance calculation
- Note: All queries return complete result sets (no LIMIT clauses)

**FST Queries**:
- Exact Match: Direct arc traversal O(m) where m = key length
- Starts With: Arc traversal + descendant enumeration O(m + k) where k = results
- Ends With: Reverse FST traversal + descendant enumeration O(m + k)
- Contains: FST traversal with substring matching O(n) where n = FST nodes
- Fuzzy Search: Levenshtein DFA traversal with pruning


## Performance Summary by Database

### seg_0_31

| Query Type | FST Time | SQLite Time | Winner | Speedup |
|---|---|---|---|---|
| Exact Match | 2ms | 97ms | FST | 48.50x |
| Starts With | 170ms | 3463ms | FST | 20.37x |
| Ends With | 245ms | 3452ms | FST | 14.09x |
| Contains | 20451ms | 3322ms | SQLite | 0.16x |
| Fuzzy Search | 61ms | N/A | FST | N/A |

### seg_1_25

| Query Type | FST Time | SQLite Time | Winner | Speedup |
|---|---|---|---|---|
| Exact Match | 0ms | 66ms | FST | >1000x |
| Starts With | 0ms | 5902ms | FST | >1000x |
| Ends With | 0ms | 7745ms | FST | >1000x |
| Contains | 55711ms | 7370ms | SQLite | 0.13x |
| Fuzzy Search | 122ms | N/A | FST | N/A |

### seg_1_30

| Query Type | FST Time | SQLite Time | Winner | Speedup |
|---|---|---|---|---|
| Exact Match | 1ms | 80ms | FST | 80.00x |
| Starts With | 5ms | 4737ms | FST | 947.40x |
| Ends With | 1ms | 5813ms | FST | 5813.00x |
| Contains | 44378ms | 7173ms | SQLite | 0.16x |
| Fuzzy Search | 84ms | N/A | FST | N/A |

### seg_2_20

| Query Type | FST Time | SQLite Time | Winner | Speedup |
|---|---|---|---|---|
| Exact Match | 0ms | 64ms | FST | >1000x |
| Starts With | 11ms | 10854ms | FST | 986.73x |
| Ends With | 23ms | 13754ms | FST | 598.00x |
| Contains | 96223ms | 18567ms | SQLite | 0.19x |
| Fuzzy Search | 147ms | N/A | FST | N/A |

## Technical Metrics

### FST Build Times

| Database | Entries | Forward FST Build | Reverse FST Build | Total Build Time |
|---|---|---|---|---|
| seg_0_31 | 291,609 | 0ms | 0ms | 0ms |
| seg_1_25 | 715,347 | 1330ms | 1764ms | 3094ms |
| seg_1_30 | 569,299 | 983ms | 1309ms | 2292ms |
| seg_2_20 | 1,123,803 | 2270ms | 3106ms | 5376ms |

### File Sizes and Compression

| Database | Entries | SQLite Size | FST Size | Reverse FST Size | Compression | FST/SQLite Ratio |
|---|---|---|---|---|---|---|
| seg_0_31 | 291,609 | 15.50 MB | 1.21 MB | 2.67 MB | 92.2% | 0.08x |
| seg_1_25 | 715,347 | 38.62 MB | 3.08 MB | 6.62 MB | 92.0% | 0.08x |
| seg_1_30 | 569,299 | 30.62 MB | 2.43 MB | 5.24 MB | 92.1% | 0.08x |
| seg_2_20 | 1,123,803 | 61.19 MB | 4.84 MB | 10.56 MB | 92.1% | 0.08x |

## Aggregate Statistics

- **Total Entries**: 2,700,058
- **Total SQLite Size**: 145.94 MB
- **Total FST Size**: 11.56 MB
- **Total Reverse FST Size**: 25.09 MB
- **Average Compression**: 92.1%
- **Average Speedup (Exact Match)**: 64.25x

### FST Build Time Summary

- **Total Forward FST Build Time**: 4583ms
- **Total Reverse FST Build Time**: 6179ms
- **Total FST Build Time**: 10762ms
- **Average Build Time per Database**: 2690ms

