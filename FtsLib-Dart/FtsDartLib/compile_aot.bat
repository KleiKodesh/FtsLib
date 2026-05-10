@echo off
REM Compiles the FtsLib Dart entry point to a native AoT executable.
REM Usage: compile_aot.bat [entry_point.dart] [output_name]
REM Defaults: entry point = bin\fts_lib.dart, output = bin\fts_lib.exe
REM
REM AoT (dart compile exe) is meaningfully faster than JIT for CPU-bound work
REM such as segment writes, merges, and posting list intersection.
REM See: https://dev.to/maximsaplin/efficient-dart-part-2-going-competitive-307c

set ENTRY=%1
set OUTPUT=%2

if "%ENTRY%"=="" set ENTRY=bin\fts_lib.dart
if "%OUTPUT%"=="" set OUTPUT=bin\fts_lib.exe

echo [AoT] Compiling %ENTRY% → %OUTPUT% ...
dart compile exe %ENTRY% -o %OUTPUT%

if %ERRORLEVEL%==0 (
    echo [AoT] Done. Run with: %OUTPUT%
) else (
    echo [AoT] Compilation failed.
    exit /b 1
)
