#!/usr/bin/env bash
# ci-windows-evict-smoke.sh — the windows CI job's proof that the cache-eviction sweep really evicts (#326's sibling).
#
# The sweep (src/quality.h evictOldCacheFamily, once per process from saveCache via sweepStaleCacheBlobsOnce) used to
# walk cacheDirLadder()'s un-rebased "/tmp/ripwire-<uid>" with std::filesystem::directory_iterator — on Windows the
# CURRENT DRIVE's "\tmp\ripwire-<uid>", which does not exist — so its error_code path returned early and it evicted
# nothing, ever, while the real cache (the rebased directory os::mkdir created) grew without bound. cacheDirLadder()
# now resolves its spelling once, at the source. This script proves it end to end on a real binary:
#   1. learn the REAL cache directory from --doctor's cache-dir row (its dir=, itself #326's fix);
#   2. seed that directory with fake ripwire-*.bin blobs dated 2020 — past the 30-day age cap, the cheapest sure
#      trigger (no byte budget to fill, no count cap to reach);
#   3. force a cache WRITE with a cold crawl of a fresh copy of the fixture (saveCache runs only when a file changed,
#      and the sweep runs only from saveCache);
#   4. assert the seeded blobs are gone. On the pre-fix code all five survive and the last check fails loudly.
# Runs under Git Bash on the windows-latest runner (the job's default shell) and, unchanged, on POSIX — where the
# rebase is an identity, so it proves the script's own logic, not the Windows defect. Counting is a glob loop, never
# `ls | wc`: a matchless `ls` is the GREEN outcome here and must not read as a failure.
# Usage:  bash scripts/ci-windows-evict-smoke.sh ./build/ripwire.exe      (from the repo root; TMPDIR/XDG_CACHE_HOME
#         are unset here to reproduce the filed condition, cacheDirLadder()'s third tier)
set -u
BIN="${1:?usage: ci-windows-evict-smoke.sh <ripwire binary>}"
unset TMPDIR XDG_CACHE_HOME

# --doctor exits 1 when ANY row is not ok; the shared helper records that code instead of obeying it and fails, loudly,
# only when the cache-dir row itself is missing or not ok="1" — so `row` below is a present, healthy row.
row="$( bash "$( dirname "$0" )/ci-windows-doctor-row.sh" "$BIN" doctor-evict.xml )" || exit 1
cachedir="$( printf '%s' "$row" | sed -n 's/.* dir="\([^"]*\)".*/\1/p' )"
if [ -z "$cachedir" ] || [ ! -d "$cachedir" ]; then
    echo "ci: --doctor's cache-dir row names no directory that exists here: dir=\"$cachedir\"" >&2; exit 1
fi

seeds(){ n=0; for f in "$cachedir"/ripwire-ciseed*-lean.bin; do if [ -e "$f" ]; then n=$(( n + 1 )); fi; done; echo "$n"; }
for i in 1 2 3 4 5; do
    printf 'stale seeded blob %s' "$i" > "$cachedir/ripwire-ciseed0000000$i-lean.bin" \
        || { echo "ci: cannot write a seed blob into $cachedir" >&2; exit 1; }
done
touch -t 202001010000 "$cachedir"/ripwire-ciseed*-lean.bin || { echo "ci: cannot date the seed blobs" >&2; exit 1; }
before="$( seeds )"
[ "$before" -eq 5 ] || { echo "ci: seeded 5 stale blobs into $cachedir but $before are visible there" >&2; exit 1; }

rm -rf evict-fixture && cp -r test/fixture evict-fixture || { echo "ci: cannot stage a fresh fixture copy" >&2; exit 1; }
"$BIN" evict-fixture > evict-run.xml || { echo "ci: the cache-writing crawl itself failed" >&2; exit 1; }
after="$( seeds )"
echo "stale seeded blobs: before=$before after=$after (dir=$cachedir)"
[ "$after" -eq 0 ] \
    || { echo "ci: the eviction sweep left $after of $before stale seeded blobs in $cachedir — it is not scanning the directory the cache really uses" >&2; exit 1; }
rm -rf evict-fixture doctor-evict.xml evict-run.xml
echo "ci-windows-evict-smoke: PASS — the sweep evicted every stale seeded blob from the directory the cache really uses"
