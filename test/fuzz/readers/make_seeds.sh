#!/usr/bin/env bash
# make_seeds.sh — regenerate test/fuzz/readers/seeds/ from the REAL writers, so every reader starts from valid input.
#
#   bash test/fuzz/readers/make_seeds.sh [BIN]      (BIN: a ripwire binary built from this tree; default build/ripwire)
#
# Every binary seed is a blob a ripwire run wrote into a scratch cache directory, reshaped to what its harness takes:
# checksummed families lose their header and trailing digest (the harness rebuilds both), ingest records are cut out
# of a real cache blob along its offset table, and a one-byte reader selector is prepended where a harness serves
# several readers. Text seeds are the repository's own fixtures and a few hand-written protocol frames. Seed files have
# no extension, so the live-tree gates never parse them as source. Re-run after a cache format change and commit the
# result; a harness replaying seeds of a stale format still runs them, it just starts further from valid.
set -uo pipefail
ROOT="$( cd "$( dirname "$0" )/../../.." && pwd )"
BIN="${1:-$ROOT/build/ripwire}"
case "$BIN" in /*) ;; *) BIN="$ROOT/$BIN" ;; esac
[ -x "$BIN" ] || { echo "make_seeds.sh: no ripwire binary at $BIN"; exit 2; }
OUT="$ROOT/test/fuzz/readers/seeds"
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
export TMPDIR="$WORK/cache"; mkdir -p "$TMPDIR"
export GIT_AUTHOR_NAME=fuzz GIT_AUTHOR_EMAIL=fuzz@example.invalid GIT_COMMITTER_NAME=fuzz GIT_COMMITTER_EMAIL=fuzz@example.invalid
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

# ── a small git repository with history and a removed name; the ingest, quality and sidecar blobs are written BEFORE
#    the large file is added, so no seed carries its 900 records — it exists only for the span-tier memo's floor ─────
REPO="$WORK/repo"; mkdir -p "$REPO"
cp -R "$ROOT/test/fixture/." "$REPO/"
cp "$ROOT/test/docfix/notebook.ipynb" "$ROOT/test/docfix/page.html" "$ROOT/test/docfix/data.csv" "$REPO/"
( cd "$REPO" && git init -q && git add -A && git commit -q -m one \
  && printf 'int removedLater( int x ) { return x; }\n' > gone.cpp && git add -A && git commit -q -m two \
  && git rm -q gone.cpp && git commit -q -m three && printf '// touched\n' >> geometry.cpp && git commit -q -am four )
( cd "$REPO" && "$BIN" . --cache="$WORK/lean.cache" >/dev/null 2>&1 || true
  "$BIN" . --for="geometry area" >/dev/null 2>&1 || true
  "$BIN" . --quality-baseline >/dev/null 2>&1 || true
  "$BIN" . --quality-delta >/dev/null 2>&1 || true
  "$BIN" . --hotspots >/dev/null 2>&1 || true
  "$BIN" . --doc-drift --with-history >/dev/null 2>&1 || true
  "$BIN" . --note-add="geometry.cpp: the fixture's main file" >/dev/null 2>&1 || true
  "$BIN" . --note-add="app.py: a second note with a sha" >/dev/null 2>&1 || true )
python3 - "$REPO/big.cpp" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    f.write("// big.cpp: a file past the span-tier memo floor (32 KiB)\n")
    for i in range(450):
        f.write('/* block %d */ int fn%d( int x ) { const char* s = "memo %d"; return x + %d; } // line %d\n' % (i, i, i, i, i))
PY
( cd "$REPO" && "$BIN" . --grep=memo >/dev/null 2>&1 || true )

rm -rf "$OUT"; mkdir -p "$OUT"
python3 - "$ROOT" "$WORK" "$OUT" <<'PY'
import glob, os, struct, sys
ROOT, WORK, OUT = sys.argv[1:4]
made = {}

def seed(reader, name, data):
    d = os.path.join(OUT, reader); os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, name), "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode())
    made[reader] = made.get(reader, 0) + 1

def fnv1a64(b):
    h = 14695981039346656037
    for c in b:
        h = ((h ^ c) * 1099511628211) & ((1 << 64) - 1)
    return h

def family(tag):
    return sorted(glob.glob(os.path.join(WORK, "cache", "**", "ripwire-%s-*" % tag), recursive=True))

def need(cond, what):
    if not cond:
        raise SystemExit("make_seeds.sh: " + what)

def read(p):
    with open(p, "rb") as f:
        return f.read()

# checksummed families: [header][body][fnv1a64 of everything before]
for tag, reader, hdr in (("qsnap", "qsnap", 24), ("qchurn", "qchurn", 16), ("qhist", "oracle", 8)):
    blobs = family(tag)
    need(blobs, "no ripwire-%s-* blob was written — the seed would be empty" % tag)
    for i, p in enumerate(blobs[:4]):
        b = read(p)
        need(len(b) >= hdr + 8 and struct.unpack("<Q", b[-8:])[0] == fnv1a64(b[:-8]), "%s: %s is not the [header][body][fnv64] shape" % (tag, p))
        seed(reader, "real%d" % i, b[hdr:-8])

# ingest cache: whole blobs for the frame harness, each record cut along the offset table for the record harness
blobs = [os.path.join(WORK, "lean.cache")] + family("mcp") + sorted(glob.glob(os.path.join(WORK, "cache", "**", "ripwire-*-rich.bin"), recursive=True))
blobs = [p for p in blobs if os.path.exists(p)]
need(any(p.endswith("-rich.bin") for p in blobs), "no rich ingest blob was written")
for i, p in enumerate(blobs[:3]):
    b = read(p)
    rich = p.endswith("-rich.bin")
    seed("ingestframe", "real%d" % i, bytes([1 if rich else 0]) + b)
    table, n = struct.unpack_from("<QI", b, len(b) - 24)
    for k in range(min(n, 6)):
        off, length = struct.unpack_from("<Q", b, table + k * 32 + 8)[0], struct.unpack_from("<I", b, table + k * 32 + 24)[0]
        seed("ingestrecord", "real%d_%d" % (i, k), bytes([1 if rich else 0]) + b[off:off + length])

# span-tier memo: [magic][version][size][mtime][ctime][pathLen][path] then the body the harness takes
memos = family("stier")
need(memos, "no ripwire-stier-* memo was written (big.cpp must pass the 32 KiB floor)")
for i, p in enumerate(memos[:2]):
    b = read(p)
    pathLen = struct.unpack_from("<I", b, 32)[0]
    seed("stiermemo", "real%d" % i, b[36 + pathLen:])

repo = os.path.join(WORK, "repo")
for name in (".ripwire_notes", ".ripwire_quality_baseline"):
    need(os.path.exists(os.path.join(repo, name)), "no %s was written" % name)
seed("sidecars", "notes", b"\x00" + read(os.path.join(repo, ".ripwire_notes")))
acks = read(os.path.join(ROOT, ".ripwire_quality_acks")).split(b"\n")
seed("sidecars", "acks", b"\x01" + b"\n".join(acks[:2] + [l for l in acks if l.startswith(b"ack ")][:12]) + b"\n")   # the committed ledger's own header and rows
seed("sidecars", "baseline", b"\x02" + read(os.path.join(repo, ".ripwire_quality_baseline")))
seed("sidecars", "config", b"\x03" + b"register_macros = DEFINE_THING, REGISTER_TEST\n")
seed("sidecars", "arch", b"\x04" + read(os.path.join(ROOT, "test/archfix/rules.txt")))

# text readers: the repository's own fixtures and protocol frames
for i, rel in enumerate(("test/scipfix/index.scip", "test/scipjoinfix/index.scip")):
    seed("scip", "fixture%d" % i, read(os.path.join(ROOT, rel)))
seed("resolvecfg", "tsconfig", b"\x00" + read(os.path.join(ROOT, "test/multirootfix/cli/tsconfig.json")))
seed("resolvecfg", "gomod", b"\x01" + read(os.path.join(ROOT, "test/multirootfix/cli/go.mod")))
for p in sorted(glob.glob(os.path.join(ROOT, "test/lintrulesfix/**/*.yml"), recursive=True))[:4]:
    seed("lintrules", os.path.basename(p).replace(".", "_"), read(p))
seed("docparse", "ipynb", b"\x00" + read(os.path.join(ROOT, "test/docfix/notebook.ipynb")))
seed("docparse", "html", b"\x01" + read(os.path.join(ROOT, "test/docfix/page.html")))
seed("docparse", "csv", b"\x02" + read(os.path.join(ROOT, "test/docfix/data.csv")))
seed("docparse", "markdown", b"\x03" + read(os.path.join(ROOT, "docs/README.md")))
for p in sorted(glob.glob(os.path.join(ROOT, "skills/*/SKILL.md")))[:3]:
    seed("skillscan", os.path.basename(os.path.dirname(p)), read(p))
seed("tracein", "asan", "==123==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x602000000011\n"
     "    #0 0x100003f5c in rw::readDef(rw::ByteR&) src/ingest_cache.h:1691:5\n    #1 0x100004a10 in main src/main.cpp:3491:12\n")
seed("tracein", "python", "Traceback (most recent call last):\n  File \"app.py\", line 12, in <module>\n    main()\n"
     "  File \"app.py\", line 8, in main\n    raise ValueError(\"x\")\nValueError: x\n")
seed("tracein", "node", "TypeError: x is not a function\n    at area (/srv/geometry.js:14:9)\n    at Object.<anonymous> (/srv/app.js:3:1)\n")
seed("tracein", "compiler", "src/geometry.cpp:42:17: error: no member named 'radius' in 'Circle'\n")
seed("qscope", "files", "src/quality.h,src/ingest_cache.h")
seed("qscope", "glob", "src/**/*.h")
for name, line in (
    ("initialize", '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"fuzz","version":"1"}}}'),
    ("toolslist", '{"jsonrpc":"2.0","id":"a","method":"tools/list"}'),
    ("for", '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"for","arguments":{"path":".","task":"parse \\"cache\\" \\u00e9","top_k":8}}}'),
    ("batch", '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"batch","arguments":{"path":".","queries":[{"verb":"callers","symbol":"escapeXml"},{"verb":"grep","pattern":"x","limit":5}]}}}'),
    ("connect", '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"connect","arguments":{"paths":["a","b"],"symbols":["f","g"]}}}'),
    ("edit", '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"replace_symbol_body","arguments":{"path":".","symbol":"f","new_body":"{ return 1; }","edits":[{"symbol":"g","new_body":"{}"}]}}}')):
    seed("mcpjson", name, line)
body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
seed("mcphttp", "post", "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\n"
     "MCP-Protocol-Version: 2025-11-25\r\nAuthorization: Bearer abc\r\nContent-Length: %d\r\n\r\n%s" % (len(body), body))
seed("mcphttp", "get", "GET /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: text/event-stream\r\n\r\n")

# regression seeds: the minimized inputs that crashed a reader, kept so every replay re-runs them. Their names start with
# `regress-`; a reader is EXPECTED to refuse them, so run.sh's liveness check (every seed accepted) exempts that prefix.
seed("scip", "regress-overlong-varint", bytes.fromhex("ffffffffffffffffff70"))            # scip.h varint: payload past bit 63 (G1 integer abort)
seed("ingestframe", "regress-table-offset-wrap", bytes.fromhex("2d0000a0ffff3060ffffffffffffffff00000000ffffffffffffffffffffffffffff"))   # openCacheFrame: tableOffset + table + trailer wrapped
readers = open(os.path.join(ROOT, "CMakeLists.txt")).read().split("set(RIPWIRE_FUZZ_READERS", 1)[1].split(")", 1)[0].split()
missing = [r for r in readers if not made.get(r)]
need(not missing, "readers with no seed: " + " ".join(missing))
print("make_seeds.sh: %d seeds for %d readers — %s" % (sum(made.values()), len(made), " ".join("%s=%d" % kv for kv in sorted(made.items()))))
PY
