#!/usr/bin/env bash
# ci-windows-doctor-row.sh — run `ripwire --doctor` over test/fixture and print its cache-dir row, on stdout, WITHOUT
# letting --doctor's own exit code decide the step (#326's Windows smoke step, and its eviction sibling).
#
# --doctor exits 1 whenever ANY row is not ok — a binary-path or other environment row included, none of which the
# cache-dir assertion cares about. A CI step under the job's default `bash -eo pipefail` that ran it bare therefore
# aborted on that exit, before its own cache-dir check ever ran, with nothing on the log to say which row did it.
# This records the code instead of obeying it, and fails — loudly, with that code and the report — only when the
# cache-dir row itself is missing or not ok="1". A missing `blobs=`/`dir=` is the caller's own assertion.
# Usage (from the repo root):  row="$( bash scripts/ci-windows-doctor-row.sh ./build/ripwire.exe doctor.xml )"
set -u
BIN="${1:?usage: ci-windows-doctor-row.sh <ripwire binary> <doctor output file>}"
OUT="${2:?usage: ci-windows-doctor-row.sh <ripwire binary> <doctor output file>}"

rc=0
"$BIN" test/fixture --doctor > "$OUT" || rc=$?
row="$( grep -o '<c n="cache-dir"[^>]*>' "$OUT" || true )"
echo "--doctor rc=$rc; cache-dir row: ${row:-<none>}" >&2
case "$row" in
    '')
        echo "ci: no cache-dir row in --doctor output at all (--doctor rc=$rc); the report was:" >&2
        cat "$OUT" >&2; exit 1 ;;
    *'ok="1"'*)
        printf '%s\n' "$row" ;;
    *)
        echo "ci: #326 regressed — cache-dir row is not ok=\"1\" (--doctor rc=$rc): $row" >&2; exit 1 ;;
esac
