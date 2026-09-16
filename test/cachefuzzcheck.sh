#!/usr/bin/env bash
# cachefuzzcheck.sh — standing loadCache / readQSnapBlob fuzz harness (-era open item).
#
# Contract under test: NO hostile/corrupt/truncated cache blob can crash, hang, over-read, or poison
# output. loadCache (src/ingest.cpp, --cache=FILE v8 blob) and the qsnap reader (readQSnapBlob +
# deserializeSnapshot, src/quality.h, --quality-delta's HEAD-Snapshot sidecar) must both DEGRADE to a
# clean cold parse / clean recompute on any malformed input — never a wrong answer, never a crash.
#
# Route: this drives the PUBLIC ingest() entry point via the CLI (--cache=FILE with a doctored file on
# disk) rather than calling loadCache directly from a standalone driver — the more honest end-to-end
# fuzz (the real attack surface is "an agent/CI hands ripwire a cache file it doesn't fully trust"),
# and it means this harness needed NO changes to src/ingest.h / src/ingest.cpp / src/quality.h.
#
# ── Part 1: v15 ingest-cache blob (loadCache) — DETERMINISTIC structured mutation table ────────────
# Blob layout (native-endian, no padding — mirrors ingest_cache.h saveCache/openCacheFrame/loadCache):
#   HEADER, 25 B:
#     [0:4)   u32 magic "CTPK"        [4:8)   u32 version (kCacheVersion)
#     [8:12)  u32 parserVer           [12]    u8  kArtifactArch (endian|pointerWidth<<1)
#     [13:21) u64 blobWriteNs         [21:25) u32 entryCount
#   RECORDS, [25, tableOffset), ascending pathHash:
#     u32 pathLen, pathBytes, u64 contentHash, u64 sizeBytes, u64 mtimeNs, u64 ctimeNs,
#     4x u32 FileHealth, [rich: u32 dictCount + dict], u32 defCount, [def records], ...
#   OFFSET TABLE, entryCount x 32 B at tableOffset:
#     u64 pathHash, u64 recOffset, u64 contentHash, u32 recLength, u32 recSum
#   TRAILER, last 24 B: u64 tableOffset, u32 entryCount, u32 reserved, u64 tableSum
#   tableSum covers HEADER || TABLE; each recSum covers exactly its own record.
# A python helper (mirroring that byte-exact layout) generates ~26 named byte-level mutations from one
# good baseline blob; bash then layers 5 more filesystem-shape mutations (dir/perm/symlink//dev/null)
# on top. Each mutation is applied via a FIXED table, not a random seed (determinism rule): re-running
# this script produces the exact same mutated bytes every time.
#
# WHY THE HELPER REBUILDS THE FRAME. A mutation that leaves a STALE frame stops at the very first
# guard, and every deeper guard it was written for then passes for the wrong reason — the "green while
# inert" failure CONTRIBUTING §2 names. So `with_recomputed_trailer` recomputes every record's recSum
# from the mutated bytes and rewrites a consistent trailer, which is what lets a huge def count, an
# absurd string length or a garbage record body actually REACH readFileRecord. The mutations that are
# deliberately about the frame itself (arch_byte_flip_stale, checksum_mismatch_deep_bitflip_stale,
# trailer_bytes_corrupted, table_offset_past_eof, trailer_entry_count_inflated) leave it stale on
# purpose, and each names which layer it is aimed at.
#
# Each mutation is run under the DEV binary and must: exit 0, and produce output BYTE-IDENTICAL to a
# `--no-cache` cold parse (the POISON check — a malformed cache must never silently change the answer,
# only ever cost the speed win). stderr must be bounded (no infinite alert spew). The full table is then
# re-run once under the ASan binary (asserting no sanitizer report fired).
#
# ── Part 2: qsnap blob (readQSnapBlob / deserializeSnapshot) — smaller mutation table ──────────────
# qsnapcachecheck.sh already gates ONE corrupt-blob case (magic replaced by garbage). This part extends
# coverage (truncation at every field boundary, scheme/sha mismatch, huge counts, checksum-valid
# garbage payload, filesystem-shape cases) without duplicating that existing check. Ground truth is a
# `--quality-delta --no-cache`-equivalent run with the qsnap blob deleted; every mutation must degrade
# to the SAME byte-identical output.
#
# ── Part 2's huge-count arms, and why they run under a bounded allocator ──────────────────────────────
# A checksum-valid qsnap blob whose vector count reads 0xFFFFFFFF used to reach `reserve` straight from the
# blob: 32 GiB for a u64 vector. Linux (no overcommit for that size) threw std::bad_alloc, which nothing on
# the CLI path catches — SIGABRT (134) on every run until the blob was evicted, reproduced on Ubuntu. The
# macOS allocator overcommits the reservation and never touches it, so a plain macOS run of the same blob
# exits 0 against the defect. The arms therefore run the huge-count mutations under a BOUND that turns the
# reservation into the failure a small host would see: `ulimit -v` for a plain Linux binary, and ASan's
# max_allocation_size_mb for an instrumented binary on any platform (the ASan sweep below carries it for
# every mutation). A plain macOS binary has no such bound, and the arm says so rather than passing blind.
# The layout offsets (magic 4, scheme 4, cacheVer 4, parserVer 4, sha 8, then the ten field counts from
# byte 24) are the ones deserializeSnapshot reads; the map-count and sha arms used to write at 16 and 8,
# which a guard ahead of the one they were written for rejected first.
#
# ── Part 3: qchurn blob (deserializeRawCommitStream) — the same huge-count rows for the churn memo ────────
#
# Usage:
#   bash test/cachefuzzcheck.sh
#   RIPWIRE_BIN=build/ripwire RIPWIRE_ASAN_BIN=asan/ripwire bash test/cachefuzzcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; ALL PASS on success. Does not edit
# regression.sh (regression.sh wires this in itself, once, if git status was clean when this was built).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
ASAN_BIN="${RIPWIRE_ASAN_BIN:-$ROOT/asan/ripwire}"
[ "${ASAN_BIN#/}" = "$ASAN_BIN" ] && ASAN_BIN="$ROOT/$ASAN_BIN"
FIXTURE="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
note(){ printf '  NOTE  %s\n' "$*"; }
skip(){ printf '  SKIP  %s\n' "$*"; }   # an ABSENT PRECONDITION with a named reason — never a silent pass

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIXTURE" ] || { echo "no fixture at $FIXTURE"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

echo "cachefuzzcheck: BIN=$BIN  ASAN_BIN=$ASAN_BIN  FIXTURE=$FIXTURE  TMP=$TMP"

# stderr sanity bound: a degrade path emits at most a small, fixed number of alert lines — never
# unbounded spew (e.g. one alert per corrupt record in a loop).
STDERR_LINE_CAP=200
STDERR_BYTE_CAP=20000
stderr_sane(){
    local f="$1" lines bytes
    lines="$( wc -l < "$f" | tr -d ' ' )"
    bytes="$( wc -c < "$f" | tr -d ' ' )"
    [ "$lines" -le "$STDERR_LINE_CAP" ] && [ "$bytes" -le "$STDERR_BYTE_CAP" ]
}

# The allocation bound the huge-count arms run under (header): which one `$1`'s build can take, or empty.
bound_mode_of(){
    if LC_ALL=C grep -q -a '__asan_init' "$1" 2>/dev/null; then echo asan
    elif [ "$( uname -s )" = "Linux" ]; then echo ulimit
    fi
}
# Run "$@" under bound mode $1. An address-space limit that cannot be set exits 97, so the caller reports a
# skip instead of a pass that ran unbounded.
bounded(){
    local mode="$1"; shift
    case "$mode" in
        asan)   ASAN_OPTIONS="${ASAN_OPTIONS:+$ASAN_OPTIONS:}max_allocation_size_mb=1024" "$@" ;;
        ulimit) ( ulimit -v 8388608 2>/dev/null || exit 97; "$@" ) ;;
        *)      "$@" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# PART 1 — v8 ingest-cache blob (loadCache)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

# ground truth: a pure cold parse, cache-independent.
"$BIN" "$FIXTURE" --no-cache --no-stable >"$TMP/truth.xml" 2>/dev/null
[ -s "$TMP/truth.xml" ] || { echo "cold parse of fixture produced no output — cannot proceed"; exit 2; }

# a good, warm v8 cache blob — the mutation baseline.
GOOD="$TMP/good.cache"
"$BIN" "$FIXTURE" --cache="$GOOD" --no-stable >"$TMP/good_out.xml" 2>/dev/null
[ -s "$GOOD" ] || { echo "failed to build a baseline cache blob"; exit 2; }
diff -q "$TMP/truth.xml" "$TMP/good_out.xml" >/dev/null \
    && ok "sanity: cold build of the good cache produces the same output as --no-cache" \
    || { echo "baseline cache build already diverges from cold — cannot trust the harness"; exit 2; }

MUTDIR="$TMP/mutations"; mkdir -p "$MUTDIR"

# ── the byte-level mutation table (python — mirrors loadCache's exact layout; deterministic, no RNG
#    seed used for anything that affects correctness-relevant bytes; the one "garbage payload" mutation
#    uses a FIXED xorshift-style deterministic byte pattern, not a random seed) ─────────────────────────
python3 - "$GOOD" "$MUTDIR" <<'PYEOF'
import struct, sys

good_path, outdir = sys.argv[1], sys.argv[2]
with open(good_path, "rb") as f:
    good = bytearray(f.read())

def blob_checksum(data: bytes) -> int:
    # mirrors ingest.cpp blobChecksum(): 8-lane FNV-1a64 permutation over 8-byte strides.
    P = 1099511628211
    M = (1 << 64) - 1
    lane = [1469598103934665603, 1099511628211, 0x100000001b3, 0x9e3779b97f4a7c15,
            0xc2b2ae3d27d4eb4f, 0x165667b19e3779f9, 0xff51afd7ed558ccd, 0xc4ceb9fe1a85ec53]
    n = len(data); i = 0
    while i + 8 <= n:
        for k in range(8):
            lane[k] = ((lane[k] ^ data[i + k]) * P) & M
        i += 8
    k = 0
    while i < n:
        lane[k] = ((lane[k] ^ data[i]) * P) & M
        i += 1; k += 1
    h = 1469598103934665603
    for k in range(8):
        h = ((h ^ lane[k]) * P) & M
    return h

HDR      = 25   # header bytes: magic4 + ver4 + parserVer4 + arch1 + blobWriteNs8 + entryCount4
TRAILER  = 24   # trailer bytes: tableOffset8 + entryCount4 + reserved4 + tableSum8
ENTRY    = 32   # offset-table row: pathHash8 + recOffset8 + contentHash8 + recLength4 + recSum4

TABLE_OFF, TABLE_N = struct.unpack_from("<QI", good, len(good) - TRAILER)[0:2]
payload_len = len(good) - TRAILER   # everything before the trailer: records + offset table

def with_recomputed_trailer(payload: bytearray) -> bytes:
    """`payload` is records+table (everything before the trailer). Recompute every record's recSum from
    payload's CURRENT bytes and append a fresh, self-consistent v15 trailer — so a mutation reaches the
    guard it is aimed at instead of being stopped by a stale frame (see the WHY note in the header)."""
    b = bytearray(payload)
    for i in range(TABLE_N):
        off = TABLE_OFF + i * ENTRY
        if off + ENTRY > len(b):
            break
        rec_off = struct.unpack_from("<Q", b, off + 8)[0]
        rec_len = struct.unpack_from("<I", b, off + 24)[0]
        if rec_off + rec_len <= TABLE_OFF and rec_off + rec_len <= len(b):
            struct.pack_into("<I", b, off + 28, blob_checksum(bytes(b[rec_off:rec_off + rec_len])) & 0xFFFFFFFF)
    tbl = bytes(b[:HDR]) + bytes(b[TABLE_OFF:TABLE_OFF + TABLE_N * ENTRY])
    return bytes(b) + struct.pack("<QIIQ", TABLE_OFF, TABLE_N, 0, blob_checksum(tbl))

# ── locate the fixed-offset fields in the FIRST record (records start immediately after the header;
#    v15 writes them in ascending pathHash order, so record[0] is simply the lowest-hashing file) ────
path_len  = struct.unpack_from("<I", good, HDR)[0]
path_off  = HDR + 4
hash_off  = path_off + path_len
size_off  = hash_off + 8
mtime_off = size_off + 8
ctime_off = mtime_off + 8
nd_off    = ctime_off + 8 + 20   # past ctimeNs and the five FileHealth u32s (v20 added macroBlanked): the LEAN def-record count

mutations = {}

# -- truncation at various boundaries --
mutations["truncate_empty_within_header"]      = lambda b: bytes(b[:2])
mutations["truncate_before_arch_byte"]          = lambda b: bytes(b[:12])
mutations["truncate_before_filecount"]          = lambda b: bytes(b[:21])
mutations["truncate_mid_first_record"]          = lambda b: bytes(b[:size_off + 3])
mutations["truncate_trailer_partial"]           = lambda b: bytes(b[:-4])
mutations["truncate_one_byte_before_trailer"]   = lambda b: bytes(b[:payload_len - 1])

# -- header field corruption, checksum RECOMPUTED (isolates the deeper guard being tested) --
def mut_zero_magic(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, 0, 0); return with_recomputed_trailer(p)
mutations["zero_magic_recomputed_checksum"] = mut_zero_magic

def mut_flip_magic_bit(b):
    p = bytearray(b[:payload_len]); p[0] ^= 0x01; return with_recomputed_trailer(p)
mutations["flip_magic_bit_recomputed_checksum"] = mut_flip_magic_bit

def mut_version_inc(b):
    p = bytearray(b[:payload_len]); v = struct.unpack_from("<I", p, 4)[0]; struct.pack_into("<I", p, 4, v + 1); return with_recomputed_trailer(p)
mutations["version_increment_recomputed_checksum"] = mut_version_inc

def mut_version_dec(b):
    p = bytearray(b[:payload_len]); v = struct.unpack_from("<I", p, 4)[0]; struct.pack_into("<I", p, 4, v - 1); return with_recomputed_trailer(p)
mutations["version_decrement_recomputed_checksum"] = mut_version_dec

def mut_version_zero(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, 4, 0); return with_recomputed_trailer(p)
mutations["version_zero_recomputed_checksum"] = mut_version_zero

def mut_arch_flip_fixed(b):
    p = bytearray(b[:payload_len]); p[12] ^= 0x01; return with_recomputed_trailer(p)
mutations["arch_byte_flip_recomputed_checksum"] = mut_arch_flip_fixed

def mut_arch_flip_stale(b):
    p = bytearray(b); p[12] ^= 0x01        # the trailer's tableSum covers the header, so it is now stale
    return bytes(p)
mutations["arch_byte_flip_stale_checksum"] = mut_arch_flip_stale

# -- huge / overflow / negative record counts and length fields --
def mut_huge_filecount(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, 21, 0xFFFFFFFE); return with_recomputed_trailer(p)
mutations["huge_file_count_recomputed_checksum"] = mut_huge_filecount

def mut_zero_filecount(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, 21, 0); return with_recomputed_trailer(p)
mutations["zero_file_count_recomputed_checksum"] = mut_zero_filecount

def mut_huge_defcount(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, nd_off, 0xFFFFFFF0); return with_recomputed_trailer(p)
mutations["huge_def_count_recomputed_checksum"] = mut_huge_defcount

def mut_overflow_size(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<Q", p, size_off, 0xFFFFFFFFFFFFFFFF); return with_recomputed_trailer(p)
mutations["overflow_size_field_recomputed_checksum"] = mut_overflow_size

def mut_negative_size(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<Q", p, size_off, 0x8000000000000000); return with_recomputed_trailer(p)
mutations["negative_size_field_recomputed_checksum"] = mut_negative_size

def mut_maxed_mtime(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<Q", p, mtime_off, 0xFFFFFFFFFFFFFFFF); return with_recomputed_trailer(p)
mutations["maxed_mtime_field_recomputed_checksum"] = mut_maxed_mtime

def mut_string_len_exceeds(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, HDR, 0x7FFFFFFF); return with_recomputed_trailer(p)
mutations["string_length_exceeds_blob_recomputed_checksum"] = mut_string_len_exceeds

def mut_string_len_wraparound(b):
    p = bytearray(b[:payload_len]); struct.pack_into("<I", p, HDR, 0xFFFFFFFF); return with_recomputed_trailer(p)
mutations["string_length_wraparound_recomputed_checksum"] = mut_string_len_wraparound

# -- checksum-valid-but-garbage-payload: corrupt a wide swath of the body with a FIXED (non-random)
#    deterministic byte pattern, then recompute the trailer over the corrupted body. --
def mut_garbage_payload(b):
    # the RECORD region only, with a rebuilt frame: every record digest matches, so each record is
    # actually handed to readFileRecord and every one of its guards is what has to refuse it.
    p = bytearray(b[:payload_len])
    x = 0x2545F4914F6CDD1D & 0xFF
    for i in range(min(HDR + 8, TABLE_OFF), TABLE_OFF):
        x = (x * 1103515245 + 12345) & 0xFF
        p[i] = x
    return with_recomputed_trailer(p)
mutations["checksum_valid_garbage_payload"] = mut_garbage_payload

def mut_garbage_table(b):
    # the OFFSET TABLE, trailer left stale: caught by tableSum, which is the guard that has to hold
    # before any record offset in it is believed.
    p = bytearray(b)
    x = 0x9E3779B9 & 0xFF
    for i in range(TABLE_OFF, TABLE_OFF + TABLE_N * ENTRY):
        x = (x * 1103515245 + 12345) & 0xFF
        p[i] = x
    return bytes(p)
mutations["garbage_offset_table_stale_checksum"] = mut_garbage_table

def mut_table_offset_past_eof(b):
    # the trailer says the table starts past the end of the file: the EXACT-FIT invariant refuses it.
    p = bytearray(b)
    struct.pack_into("<Q", p, len(p) - TRAILER, len(p) + 4096)
    return bytes(p)
mutations["table_offset_past_eof"] = mut_table_offset_past_eof

def mut_trailer_entry_count_inflated(b):
    # trailer entryCount disagrees with the header's AND with the file size — both cross-checks fire.
    p = bytearray(b)
    struct.pack_into("<I", p, len(p) - TRAILER + 8, TABLE_N + 1000)
    return bytes(p)
mutations["trailer_entry_count_inflated"] = mut_trailer_entry_count_inflated

def mut_record_offset_inside_table(b):
    # a table entry whose record range reaches into the table itself — refused by the per-entry bounds
    # check, not by any checksum (the frame is rebuilt so the digests all agree).
    p = bytearray(b[:payload_len])
    struct.pack_into("<Q", p, TABLE_OFF + 8, TABLE_OFF)
    struct.pack_into("<I", p, TABLE_OFF + 24, 64)
    return with_recomputed_trailer(p)
mutations["record_range_overlaps_table"] = mut_record_offset_inside_table

# -- checksum mismatch only: a single deep bit flip, checksum left STALE (the shallowest guard alone) --
def mut_deep_bitflip_stale(b):
    # inside record[0], leaving BOTH digests stale: the table is untouched so tableSum still verifies,
    # and the flip must be caught by that record's own recSum instead (the per-record guard).
    p = bytearray(b)
    p[min(HDR + 20, TABLE_OFF - 1)] ^= 0xFF
    return bytes(p)
mutations["checksum_mismatch_deep_bitflip_stale"] = mut_deep_bitflip_stale

# -- trailer itself corrupted, payload untouched (hits tableSum directly) --
def mut_trailer_corrupted(b):
    p = bytearray(b)
    p[-1] ^= 0xFF
    return bytes(p)
mutations["trailer_bytes_corrupted"] = mut_trailer_corrupted

# -- empty file --
mutations["empty_file"] = lambda b: b""

names = []
for name, fn in mutations.items():
    data = fn(good)
    path = outdir + "/" + name + ".cache"
    with open(path, "wb") as f:
        f.write(data)
    names.append(name)

print("\n".join(sorted(names)))
PYEOF

MUT_NAMES=( $( ls "$MUTDIR" | sed 's/\.cache$//' | sort ) )
echo
echo "=== Part 1: v8 ingest-cache mutation table (${#MUT_NAMES[@]} byte-level + filesystem-shape cases) — DEV build ==="

run_one_dev(){
    local name="$1" cachefile="$2"
    local out="$TMP/dev_${name}.xml" err="$TMP/dev_${name}.err"
    "$BIN" "$FIXTURE" --cache="$cachefile" --no-stable >"$out" 2>"$err"
    local rc=$?
    if [ "$rc" -ge 128 ]; then
        no "[$name] CRASH — exit $rc (signal $(( rc - 128 )))"
        return
    fi
    if [ "$rc" -ne 0 ]; then
        no "[$name] nonzero exit ($rc) on a cache-only corruption — should degrade to exit 0"
        return
    fi
    if ! diff -q "$TMP/truth.xml" "$out" >/dev/null 2>&1; then
        no "[$name] OUTPUT POISONED by corrupt cache — differs from --no-cache ground truth"
        diff "$TMP/truth.xml" "$out" | head -4
        return
    fi
    if ! stderr_sane "$err"; then
        no "[$name] stderr not bounded ($(wc -l <"$err") lines / $(wc -c <"$err") bytes) — possible spew loop"
        return
    fi
    ok "[$name] exit 0, output byte-identical to cold, stderr bounded"
}

for name in "${MUT_NAMES[@]}"; do
    run_one_dev "$name" "$MUTDIR/$name.cache"
done

# ── filesystem-shape mutations (not byte content — the cache PATH itself is hostile) ────────────────
echo
echo "=== filesystem-shape cache-path mutations — DEV build ==="

# /dev/null-sized: point --cache directly at /dev/null (reads as empty; writes are discarded).
run_one_dev "devnull_cache_path" "/dev/null"

# a DIRECTORY sits at the cache path instead of a file. 2026-09-06 (stranger audit): this used to be "degrade to
# exit 0" — read as corrupt, write refused, a byte-identical map served — the fixed --cache=<nonexistent dir>
# bug's twin. --cache names a FILE; a directory is a usage error and is REFUSED (exit 1) naming the flag, the
# problem and an accepted form, same as the nonexistent-directory refusal beside it in main.cpp.
DIRPATH="$TMP/dir_as_cache"
mkdir -p "$DIRPATH"
"$BIN" "$FIXTURE" --cache="$DIRPATH" --no-stable >"$TMP/dev_dircache.xml" 2>"$TMP/dev_dircache.err"
rc_dir=$?
if [ "$rc_dir" -eq 1 ] && grep -q -- '--cache=.*is a directory' "$TMP/dev_dircache.err" && grep -q 'e\.g\. --cache=' "$TMP/dev_dircache.err"; then
    ok "[directory_at_cache_path] refused: exit 1, names --cache, the problem and an example path"
else
    no "[directory_at_cache_path] expected a refusal (exit 1 naming --cache); got exit $rc_dir, stderr: $(head -c 300 "$TMP/dev_dircache.err")"
fi
if [ ! -s "$TMP/dev_dircache.xml" ]; then
    ok "[directory_at_cache_path] no map served on the refusal"
else
    no "[directory_at_cache_path] a map was served alongside the refusal"
fi

# unreadable permissions on an otherwise-good cache file (skip cleanly if running as root, where
# chmod 000 does not actually block reads).
UNREAD="$TMP/unreadable.cache"
cp "$GOOD" "$UNREAD"
chmod 000 "$UNREAD"
if [ "$( id -u )" = "0" ]; then
    note "[unreadable_cache_permissions] running as root — chmod 000 does not block reads, skipping"
else
    run_one_dev "unreadable_cache_permissions" "$UNREAD"
fi
chmod 644 "$UNREAD"

# symlink to a VALID good cache — must still warm-hit correctly (not a corruption case, a sanity check
# that the harness's file-target mutations don't accidentally break the happy path).
SYMGOOD="$TMP/symlink_to_good.cache"
ln -sf "$GOOD" "$SYMGOOD"
run_one_dev "symlink_to_valid_cache" "$SYMGOOD"

# dangling symlink (target does not exist) — must degrade like a missing file.
SYMDANGLE="$TMP/symlink_dangling.cache"
ln -sf "$TMP/does_not_exist_$$" "$SYMDANGLE"
run_one_dev "symlink_dangling" "$SYMDANGLE"

# ── disclosure (2026-09-06 stranger audit): a Release binary keeps NO DEGRADED_PATH_ALERT, so every reject
#    above used to be byte-identical to a healthy run — a torn blob, an older binary's blob, a full disk: all
#    silent, every run. The map stays byte-identical (arms above); stderr now says what happened, once. The
#    ordinary cold-start miss stays silent, and a good cache says nothing (the controls). ──
echo
echo "=== disclosure: a rejected cache says so on stderr; a good or absent one does not ==="
# fresh mutants: every rejected cache Part 1 ran against was REWRITTEN as a good one by that very run (the
# self-heal this arm is about), so the files under $MUTDIR are healthy by now. Cut two new ones from $GOOD.
DISCDIR="$TMP/disclose"; mkdir -p "$DISCDIR"
# XOR the last byte, as Part 1's mut_trailer_corrupted does — never WRITE a constant: on the one CI leg
# (macos-14 Release, run 34090630725) where that byte already was 0xFF, a constant left the mutant equal to
# the good cache, nothing was rejected, and this arm reported "no disclosure" about a cache that was fine.
python3 - "$GOOD" "$DISCDIR/trailer_bytes_corrupted.cache" <<'PYMUT'
import sys
b = bytearray( open( sys.argv[1], "rb" ).read() )
b[-1] ^= 0xFF
open( sys.argv[2], "wb" ).write( bytes( b ) )
PYMUT
: >"$DISCDIR/empty_file.cache"
for dname in trailer_bytes_corrupted empty_file; do
    "$BIN" "$FIXTURE" --cache="$DISCDIR/$dname.cache" --no-stable >/dev/null 2>"$TMP/disc_$dname.err"
    if grep -q "ripwire: cache .*$dname.cache: [a-z-]* — not used" "$TMP/disc_$dname.err"; then
        ok "[disclose:$dname] stderr names the cache file and the reject reason"
    else
        no "[disclose:$dname] no disclosure on stderr for a rejected cache: $(head -c 200 "$TMP/disc_$dname.err")"
    fi
done
"$BIN" "$FIXTURE" --cache="$GOOD" --no-stable >/dev/null 2>"$TMP/disc_good.err"
if grep -q 'ripwire: cache' "$TMP/disc_good.err"; then
    no "[disclose:control] a GOOD cache produced a cache notice: $(head -c 200 "$TMP/disc_good.err")"
else
    ok "[disclose:control] a good cache is silent"
fi
"$BIN" "$FIXTURE" --cache="$TMP/absent_$$.cache" --no-stable >/dev/null 2>"$TMP/disc_absent.err"
if grep -q 'ripwire: cache' "$TMP/disc_absent.err"; then
    no "[disclose:control] an ABSENT cache (the ordinary cold start) produced a notice: $(head -c 200 "$TMP/disc_absent.err")"
else
    ok "[disclose:control] an absent cache (cold start) is silent"
fi
rm -f "$TMP/absent_$$.cache"
if [ "$( id -u )" = "0" ]; then
    note "[disclose:unwritable] running as root — chmod 500 does not block writes, skipping"
else
    RODIR="$TMP/ro_cache_dir"; mkdir -p "$RODIR"; chmod 500 "$RODIR"
    "$BIN" "$FIXTURE" --cache="$RODIR/c.cache" --no-stable >"$TMP/disc_ro.xml" 2>"$TMP/disc_ro.err"
    rc_ro=$?
    chmod 700 "$RODIR"
    if [ "$rc_ro" -eq 0 ] && grep -q 'ripwire: cache .*cannot write' "$TMP/disc_ro.err" && diff -q "$TMP/truth.xml" "$TMP/disc_ro.xml" >/dev/null 2>&1; then
        ok "[disclose:unwritable] an unwritable cache dir: map served (exit 0, ground truth), stderr says it cannot write"
    else
        no "[disclose:unwritable] expected exit 0 + a 'cannot write' notice; got exit $rc_ro, stderr: $(head -c 200 "$TMP/disc_ro.err")"
    fi
fi

echo
echo "=== Part 1: same mutation table — ASan build ==="
if [ -x "$ASAN_BIN" ]; then
    asan_fail=0
    run_one_asan(){
        local name="$1" cachefile="$2"
        local out="$TMP/asan_${name}.xml" err="$TMP/asan_${name}.err"
        ASAN_OPTIONS="halt_on_error=1:abort_on_error=0" \
        UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
            "$ASAN_BIN" "$FIXTURE" --cache="$cachefile" --no-stable >"$out" 2>"$err"
        local rc=$?
        if grep -qiE 'AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:|heap-buffer-overflow|stack-buffer-overflow|SEGV|ERROR: ' "$err"; then
            no "[asan:$name] SANITIZER REPORT fired"; sed -n '1,15p' "$err"
            asan_fail=1
            return
        fi
        if [ "$rc" -ge 128 ]; then
            no "[asan:$name] CRASH — exit $rc"; asan_fail=1; return
        fi
        ok "[asan:$name] no sanitizer report (exit $rc)"
    }
    for name in "${MUT_NAMES[@]}"; do
        run_one_asan "$name" "$MUTDIR/$name.cache"
    done
    run_one_asan "devnull_cache_path" "/dev/null"
    run_one_asan "directory_at_cache_path" "$DIRPATH"
    run_one_asan "symlink_to_valid_cache" "$SYMGOOD"
    run_one_asan "symlink_dangling" "$SYMDANGLE"
    [ "$asan_fail" -eq 0 ] && ok "ASan sweep: no sanitizer report across the whole mutation table" \
                           || no "ASan sweep: at least one sanitizer report fired (see above)"
else
    # ABSENT PRECONDITION, not a defect. The CI `release` jobs configure ONE build dir (build/) and never
    # -DRIPWIRE_ASAN=ON, so $ASAN_BIN cannot exist there — a hard FAIL made both release legs red for a
    # sanitizer sweep they were never asked to run (PR #1, run 30732976779: "absorb gate
    # (cachefuzzcheck.sh failed)" on macos-14 AND ubuntu-24.04, with this as the only failing line).
    # It stays PRESENCE-GUARDED: hand it an ASan binary and every arm above still runs and still asserts.
    # The sweep itself is not lost — ci.yml's `asan` job runs this gate with RIPWIRE_ASAN_BIN set.
    skip "ASan sweep — no ASan binary supplied at $ASAN_BIN (the ASan sweeps run in CI's asan job; locally: cmake -S . -B asan -DRIPWIRE_ASAN=ON && cmake --build asan -j)"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# PART 2 — qsnap blob (readQSnapBlob / deserializeSnapshot) — extends qsnapcachecheck.sh's coverage,
# does not duplicate its magic-garbage case.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== Part 2: qsnap blob mutation table (--quality-delta) — DEV build ==="

command -v git >/dev/null 2>&1 || { echo "git required for Part 2 — skipping"; }
if command -v git >/dev/null 2>&1; then
QREPO="$TMP/qrepo"; mkdir -p "$QREPO/src"
cat > "$QREPO/src/lib.cpp" <<'EOF'
int helper( int x ) { int s = 0; for( int i = 0; i < x; ++i ) { s += i * 2; } return s; }
int mainThing( int y ) { int t = y; while( t > 1 ) { t = t - 1; } return t; }
EOF
git -C "$QREPO" init -q; git -C "$QREPO" config user.email x@y; git -C "$QREPO" config user.name x
git -C "$QREPO" add -A; git -C "$QREPO" commit -qm init >/dev/null

QXDG="$TMP/qxdg"; mkdir -p "$QXDG"
QCACHEDIR="$QXDG/ripwire"
qrun(){ env -u TMPDIR XDG_CACHE_HOME="$QXDG" "$BIN" "$QREPO" --quality-delta "$@"; }
# Y4: shard-aware lookup — a blob may be flat under $QCACHEDIR or under $QCACHEDIR/<xx>/ (2-hex shard).
qsnapfiles(){ find "$QCACHEDIR" -maxdepth 2 -type f -name 'ripwire-qsnap-*.bin' 2>/dev/null; }

qrun --no-cache >"$TMP/q_truth" 2>/dev/null
QBLOB="$( qsnapfiles | head -1 )"
if [ -z "$QBLOB" ]; then
    no "Part 2: no qsnap blob produced — cannot proceed with qsnap mutation table"
else
    ok "Part 2: baseline qsnap blob produced ($QBLOB)"
    cp "$QBLOB" "$TMP/q_good.bin"

    python3 - "$TMP/q_good.bin" "$MUTDIR" <<'PYEOF'
import struct, sys

good_path, outdir = sys.argv[1], sys.argv[2]
with open(good_path, "rb") as f:
    good = bytearray(f.read())

def fnv1a64(data: bytes) -> int:
    h = 14695981039346656037
    M = (1 << 64) - 1
    for c in data:
        h = ((h ^ c) * 1099511628211) & M
    return h

body_len = len(good) - 8   # trailer = last 8 bytes

def with_recomputed_trailer(body: bytearray) -> bytes:
    return bytes(body) + struct.pack("<Q", fnv1a64(bytes(body)))

muts = {}
muts["qsnap_truncate_before_magic_done"] = lambda b: bytes(b[:2])
muts["qsnap_truncate_before_scheme"]      = lambda b: bytes(b[:4])
muts["qsnap_truncate_before_sha"]         = lambda b: bytes(b[:8])
muts["qsnap_truncate_mid_body"]           = lambda b: bytes(b[: max(20, body_len // 2)])
muts["qsnap_truncate_trailer_partial"]    = lambda b: bytes(b[:-4])
muts["qsnap_empty_file"]                  = lambda b: b""

def mut_wrong_magic(b):
    p = bytearray(b[:body_len]); p[0:4] = b"XXXX"; return with_recomputed_trailer(p)
muts["qsnap_wrong_magic_recomputed_checksum"] = mut_wrong_magic

def mut_wrong_scheme(b):
    p = bytearray(b[:body_len]); v = struct.unpack_from("<I", p, 4)[0]; struct.pack_into("<I", p, 4, v + 1); return with_recomputed_trailer(p)
muts["qsnap_wrong_scheme_recomputed_checksum"] = mut_wrong_scheme

QSNAP_SHA_OFF    = 16   # magic(4) + scheme(4) + cacheVer(4) + parserVer(4)
QSNAP_COUNTS_OFF = 24   # ... + sha(8): the first of the ten field counts (7 maps, then 3 u64 vectors)

def mut_wrong_sha(b):
    p = bytearray(b[:body_len]); struct.pack_into("<Q", p, QSNAP_SHA_OFF, 0xDEADBEEFDEADBEEF & ((1<<64)-1)); return with_recomputed_trailer(p)
muts["qsnap_wrong_sha_recomputed_checksum"] = mut_wrong_sha

def mut_huge_map_count(b):
    p = bytearray(b[:body_len])
    struct.pack_into("<I", p, QSNAP_COUNTS_OFF, 0xFFFFFFF0)   # ccxBySym's count
    return with_recomputed_trailer(p)
muts["qsnap_huge_map_count_recomputed_checksum"] = mut_huge_map_count

# The three VECTOR counts (cloneGroups, dead, publicApi): the maps ahead of them read as empty, and the
# target count claims 0xFFFFFFFF u64 records in a body with none left. Each is its own row so a guard on one
# vector cannot hide a missing guard on another.
def huge_vec_count(field):
    def mut(b):
        p = bytearray(b[:QSNAP_COUNTS_OFF])
        for _ in range(7 + field):
            p += struct.pack("<I", 0)
        p += struct.pack("<I", 0xFFFFFFFF)
        return with_recomputed_trailer(p)
    return mut
for field, name in enumerate(("clonegroups", "dead", "publicapi")):
    muts["qsnap_huge_vec_count_" + name + "_recomputed_checksum"] = huge_vec_count(field)

def mut_garbage_body(b):
    p = bytearray(b[:body_len])
    x = 17
    for i in range(16, body_len):
        x = (x * 1103515245 + 12345) & 0xFF
        p[i] = x
    return with_recomputed_trailer(p)
muts["qsnap_checksum_valid_garbage_payload"] = mut_garbage_body

def mut_deep_bitflip_stale(b):
    p = bytearray(b[:body_len])
    idx = min(24, body_len - 1)
    p[idx] ^= 0xFF
    stored = struct.unpack_from("<Q", b, body_len)[0]
    return bytes(p) + struct.pack("<Q", stored)
muts["qsnap_deep_bitflip_stale_checksum"] = mut_deep_bitflip_stale

def mut_trailer_corrupted(b):
    p = bytearray(b)
    p[-1] ^= 0xFF
    return bytes(p)
muts["qsnap_trailer_bytes_corrupted"] = mut_trailer_corrupted

names = []
for name, fn in muts.items():
    data = fn(good)
    path = outdir + "/" + name + ".bin"
    with open(path, "wb") as f:
        f.write(data)
    names.append(name)
print("\n".join(sorted(names)))
PYEOF

    QMUT_NAMES=( $( ls "$MUTDIR"/qsnap_*.bin 2>/dev/null | xargs -n1 basename | sed 's/\.bin$//' | sort ) )
    for name in "${QMUT_NAMES[@]}"; do
        cp "$MUTDIR/$name.bin" "$QBLOB"
        out="$TMP/q_${name}.out"; err="$TMP/q_${name}.err"
        qrun >"$out" 2>"$err"; rc=$?
        if [ "$rc" -ge 128 ]; then
            no "[$name] CRASH — exit $rc"
        elif ! diff -q "$TMP/q_truth" "$out" >/dev/null 2>&1; then
            no "[$name] OUTPUT POISONED by corrupt qsnap blob — differs from ground truth"
            diff "$TMP/q_truth" "$out" | head -4
        elif ! stderr_sane "$err"; then
            no "[$name] qsnap stderr not bounded — possible spew"
        else
            ok "[$name] exit 0, output byte-identical to ground truth, stderr bounded"
        fi
        cp "$TMP/q_good.bin" "$QBLOB"   # restore for the next mutation
    done

    # The huge VECTOR counts once more, under a bound (see the header): red on a reader that reserves from the
    # count, green on one that measures the count against the bytes left first.
    QHUGE_NAMES=( $( ls "$MUTDIR"/qsnap_huge_vec_count_*.bin 2>/dev/null | xargs -n1 basename | sed 's/\.bin$//' | sort ) )
    [ "${#QHUGE_NAMES[@]}" -eq 3 ] && ok "huge vector-count rows generated (${#QHUGE_NAMES[@]})" \
                                   || no "expected 3 huge vector-count rows, generated ${#QHUGE_NAMES[@]}"
    QBOUND="$( bound_mode_of "$BIN" )"
    [ -n "$QBOUND" ] || note "huge vector counts: no allocation bound for a plain $( uname -s ) binary — its allocator overcommits the reservation, so only the ASan sweep below or a Linux run can turn these rows red"
    if [ -n "$QBOUND" ]; then
        for name in "${QHUGE_NAMES[@]}"; do
            cp "$MUTDIR/$name.bin" "$QBLOB"
            out="$TMP/qb_${name}.out"; err="$TMP/qb_${name}.err"
            bounded "$QBOUND" qrun >"$out" 2>"$err"; rc=$?
            if [ "$rc" -eq 97 ]; then
                skip "[bounded:$QBOUND:$name] the address-space limit could not be set here"
            elif [ "$rc" -ne 0 ] || grep -qiE 'AddressSanitizer|bad_alloc|terminate called' "$err"; then
                no "[bounded:$QBOUND:$name] exit $rc — the count reached an allocation before any byte-count check"; sed -n '1,6p' "$err"
            elif ! diff -q "$TMP/q_truth" "$out" >/dev/null 2>&1; then
                no "[bounded:$QBOUND:$name] OUTPUT POISONED under the bound"
            elif ! grep -q 'HEAD Snapshot cache corrupt' "$err"; then
                no "[bounded:$QBOUND:$name] exit 0 but the blob was not disclosed as corrupt"
            else
                ok "[bounded:$QBOUND:$name] exit 0, byte-identical, disclosed as a corrupt cache"
            fi
            cp "$TMP/q_good.bin" "$QBLOB"
        done
    fi

    # filesystem-shape: directory at the qsnap blob path.
    rm -f "$QBLOB"; mkdir -p "$QBLOB"
    out="$TMP/q_dir.out"; err="$TMP/q_dir.err"
    qrun >"$out" 2>"$err"; rc=$?
    if [ "$rc" -ge 128 ]; then
        no "[qsnap_directory_at_path] CRASH — exit $rc"
    elif ! diff -q "$TMP/q_truth" "$out" >/dev/null 2>&1; then
        no "[qsnap_directory_at_path] OUTPUT POISONED"
        diff "$TMP/q_truth" "$out" | head -4
    else
        ok "[qsnap_directory_at_path] exit 0, output byte-identical to ground truth"
    fi
    rm -rf "$QBLOB"

    if [ -x "$ASAN_BIN" ]; then
        echo
        echo "=== Part 2: qsnap mutation table — ASan build ==="
        asanq_fail=0
        for name in "${QMUT_NAMES[@]}"; do
            cp "$MUTDIR/$name.bin" "$QBLOB" 2>/dev/null || { mkdir -p "$( dirname "$QBLOB" )"; cp "$MUTDIR/$name.bin" "$QBLOB"; }
            err="$TMP/qasan_${name}.err"
            # max_allocation_size_mb: the bound the huge-count rows need to go red on an overcommitting host (header).
            ASAN_OPTIONS="halt_on_error=1:abort_on_error=0:max_allocation_size_mb=1024" env -u TMPDIR XDG_CACHE_HOME="$QXDG" "$ASAN_BIN" "$QREPO" --quality-delta >/dev/null 2>"$err"
            rc=$?
            if grep -qiE 'AddressSanitizer|UndefinedBehaviorSanitizer|runtime error:|heap-buffer-overflow|stack-buffer-overflow|SEGV|ERROR: ' "$err" || [ "$rc" -ge 128 ]; then
                no "[asan:$name] SANITIZER REPORT / crash (exit $rc)"; sed -n '1,10p' "$err"
                asanq_fail=1
            else
                ok "[asan:$name] no sanitizer report (exit $rc)"
            fi
            cp "$TMP/q_good.bin" "$QBLOB"
        done
        if [ "$asanq_fail" -eq 0 ]; then ok "qsnap ASan sweep: no sanitizer report"; else no "qsnap ASan sweep: sanitizer report fired"; fi
    else
        # same absent precondition as Part 1's sweep — but this arm used to vanish in SILENCE, which reads
        # identically to "ran and passed" in a log. Name the reason instead.
        skip "qsnap ASan sweep — no ASan binary supplied at $ASAN_BIN (see Part 1's skip)"
    fi
fi
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# PART 3 — qchurn blob (deserializeRawCommitStream) — the co-change/churn history memo behind --for
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# Same reader family as Part 2 (readQSnapBlob + qsnapGet), a different layout: magic "QCHN"(4), scheme(4),
# fnv(key)(8), then a u32 commit count, and per commit an i64 epoch and a u32 path count ahead of its
# length-prefixed paths. Both counts used to size a reserve before any byte of the records was read: 2^32-1
# commits is ~128 GiB and 2^32-1 paths ~96 GiB, and Linux answered either with an uncaught std::bad_alloc
# (SIGABRT on every --for until the blob was evicted). A rejected blob is a SILENT miss by this memo's contract
# (a stale key is the ordinary case), so the proof that the reader refused it rather than trusting it is that
# the recompute rewrote the blob byte-identical to the good one.
echo
echo "=== Part 3: qchurn blob huge counts (--for) ==="
if command -v git >/dev/null 2>&1 && [ -n "${QREPO:-}" ] && [ -d "$QREPO" ]; then
    crun(){ env -u TMPDIR XDG_CACHE_HOME="$QXDG" "$@" "$QREPO" --for=helper; }
    crun "$BIN" >"$TMP/c_truth" 2>/dev/null                 # cold: walks git log, writes the blob
    CBLOB="$( find "$QCACHEDIR" -maxdepth 2 -type f -name 'ripwire-qchurn-*.bin' 2>/dev/null | head -1 )"
    if [ -z "$CBLOB" ]; then
        no "Part 3: no qchurn blob produced — cannot proceed with the qchurn rows"
    else
        cp "$CBLOB" "$TMP/c_good.bin"
        crun "$BIN" >"$TMP/c_warm" 2>/dev/null
        diff -q "$TMP/c_truth" "$TMP/c_warm" >/dev/null && ok "Part 3: the warm qchurn run is byte-identical to the cold one" \
                                                         || no "Part 3: the warm qchurn run already differs from the cold one — the harness cannot judge a mutation"
        python3 - "$TMP/c_good.bin" "$MUTDIR" <<'PYEOF3'
import struct, sys
good = open(sys.argv[1], "rb").read()
def fnv1a64(data):
    h = 14695981039346656037
    for c in data:
        h = ((h ^ c) * 1099511628211) & ((1 << 64) - 1)
    return h
header = good[:16]   # magic, scheme, fnv(key): the key check must pass for the count to be read at all
rows = {
    "qchurn_huge_commit_count": header + struct.pack("<I", 0xFFFFFFFF),
    "qchurn_huge_path_count":   header + struct.pack("<I", 1) + struct.pack("<q", 0) + struct.pack("<I", 0xFFFFFFFF),
}
for name, body in rows.items():
    open(sys.argv[2] + "/" + name + ".bin", "wb").write(body + struct.pack("<Q", fnv1a64(body)))
PYEOF3
        CBOUND="$( bound_mode_of "$BIN" )"
        [ -n "$CBOUND" ] || note "qchurn huge counts: no allocation bound for a plain $( uname -s ) binary — its allocator overcommits the reservation, so only the ASan leg or a Linux run can turn these rows red"
        judge_qchurn(){   # $1 = row label, $2 = rc, $3 = out, $4 = err
            if [ "$2" -eq 97 ]; then
                skip "[$1] the address-space limit could not be set here"
            elif [ "$2" -ne 0 ] || grep -qiE 'AddressSanitizer|bad_alloc|terminate called' "$4"; then
                no "[$1] exit $2 — a qchurn count reached an allocation before any byte-count check"; sed -n '1,6p' "$4"
            elif ! diff -q "$TMP/c_truth" "$3" >/dev/null 2>&1; then
                no "[$1] OUTPUT POISONED by the corrupt qchurn blob"
            elif ! cmp -s "$TMP/c_good.bin" "$CBLOB"; then
                no "[$1] exit 0, but the blob on disk is not the recomputed one — the reader did not reject it"
            else
                ok "[$1] exit 0, byte-identical, and the recompute rewrote the rejected blob"
            fi
        }
        for name in qchurn_huge_commit_count qchurn_huge_path_count; do
            cp "$MUTDIR/$name.bin" "$CBLOB"
            crun "$BIN" >"$TMP/c_$name.out" 2>"$TMP/c_$name.err"; rc=$?
            judge_qchurn "$name" "$rc" "$TMP/c_$name.out" "$TMP/c_$name.err"
            if [ -n "$CBOUND" ]; then
                cp "$MUTDIR/$name.bin" "$CBLOB"
                bounded "$CBOUND" crun "$BIN" >"$TMP/cb_$name.out" 2>"$TMP/cb_$name.err"; rc=$?
                judge_qchurn "bounded:$CBOUND:$name" "$rc" "$TMP/cb_$name.out" "$TMP/cb_$name.err"
            fi
            if [ -x "$ASAN_BIN" ] && [ "$ASAN_BIN" != "$BIN" ]; then
                cp "$MUTDIR/$name.bin" "$CBLOB"
                bounded asan crun "$ASAN_BIN" >"$TMP/ca_$name.out" 2>"$TMP/ca_$name.err"; rc=$?
                judge_qchurn "asan:$name" "$rc" "$TMP/ca_$name.out" "$TMP/ca_$name.err"
            fi
            cp "$TMP/c_good.bin" "$CBLOB"
        done
    fi
else
    skip "Part 3: needs git and Part 2's scratch repository"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "cachefuzzcheck: ALL PASS"
    exit 0
else
    echo "cachefuzzcheck: SOME CHECKS FAILED"
    exit 1
fi
