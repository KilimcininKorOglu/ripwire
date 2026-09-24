# scripts/llvmmajor.sh — sourced, not run. One definition of "which LLVM major is this tool", shared by
# test/formatgatecheck.sh (clang-format) and scripts/tidycheck.sh (clang-tidy), so the two pins read versions alike.
# llvm_major BIN  ->  prints BIN's major version ("22"), or nothing when BIN is empty, missing, or prints no version.
llvm_major(){ [ -n "${1:-}" ] && command -v "$1" >/dev/null 2>&1 && "$1" --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9]*\).*/\1/p' | head -1; }
