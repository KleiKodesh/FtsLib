#!/usr/bin/env bash
# Compiles the FtsLib Dart entry point to a native AoT executable.
# Usage: ./compile_aot.sh [entry_point.dart] [output_name]
# Defaults: entry point = bin/fts_lib.dart, output = bin/fts_lib
#
# AoT (dart compile exe) is meaningfully faster than JIT for CPU-bound work
# such as segment writes, merges, and posting list intersection.
# See: https://dev.to/maximsaplin/efficient-dart-part-2-going-competitive-307c

ENTRY="${1:-bin/fts_lib.dart}"
OUTPUT="${2:-bin/fts_lib}"

echo "[AoT] Compiling $ENTRY → $OUTPUT ..."
dart compile exe "$ENTRY" -o "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "[AoT] Done. Run with: $OUTPUT"
else
    echo "[AoT] Compilation failed."
    exit 1
fi
