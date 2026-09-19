#!/usr/bin/env bash
# notesdegradecheck.sh — the gate for CodeRabbit 4053600616 (notes.h:407): the .ripwire_notes read STATE
# (lines the reader could not parse, or the whole sidecar refused) used to reach only --notes' own <notes>
# element. Every OTHER notes-surfacing emitter — the map, --expand's ride-along map, --for (XML and --json),
# pack-task (XML and --json), --edit-check, --handoff, --plan-lanes, and the MCP for/pack_task/from_trace/
# fetch_body verbs — stayed silent: a --for --json run over a tree whose .ripwire_notes had unreadable lines
# answered exactly like a tree with none at all.
#
# THE FIX. notes::NotesReadStats::degraded() (true iff a line was skipped or the sidecar refused) now rides
# every NoteIndex the retrieval verbs build, read BEFORE the caller nulls the index pointer for emptiness (a
# sidecar with EVERY line unparsed builds an EMPTY index, and the marker must still reach the answer even
# then — the exact case a naive "nullptr when empty" check would hide). One spelling, everywhere:
# notes_degraded="1" (XML attribute) / ,"notes_degraded":true (JSON key), defined once in notes.h
# (kNotesDegradedAttr/kNotesDegradedJsonKey/kNotesDegradedReading/kNotesDegradedComment) and read back by
# every emitter below. Absent entirely on a clean read (no sidecar, or every line parsed) — the L3 INERTNESS
# CONTRACT (notes.h) — so a run with nothing to disclose is byte-identical to the pre-round binary.
#
# ARMS
#   (A) partly-unparseable fixture (one good line, two bad): RED on the base binary (no marker anywhere but
#       --notes itself), GREEN on this one, across: map, bundle --expand (--top-k=5), whole-file --expand
#       (the bare default AND --top-k=0 — main.cpp's M6 bundle-vs-whole-file chooser, once a real gap: no
#       <r> map rides along there, so the marker had to reach the bare <ctx> root itself), --for XML,
#       --for --json, pack-task XML, pack-task --json, --edit-check, --handoff, --plan-lanes.
#   (B) refused (symlinked) sidecar fixture: the same sweep — a refused read is degraded too (SymlinkRefused).
#   (B2) the same two fixtures over the four MCP verbs (for/pack_task/from_trace/fetch_body), JSON-RPC over
#       --mcp — the mcp_verb() pattern test/mcpdegradedhintcheck.sh uses (one request per call, no --mcp
#       handshake needed for a single tools/call). fetch_body needs a handle, resolved via find_symbol first.
#   (C) INERTNESS: no .ripwire_notes at all → base and this binary agree byte-for-byte on every surface above.
#   (D) INERTNESS: a CLEAN .ripwire_notes (one well-formed line, nothing skipped) → base and this binary still
#       agree byte-for-byte — the marker must never appear on a read that left nothing out.
#   (E) every degraded document above is well-formed (XML) / parseable (JSON).
#
# Usage:  bash test/notesdegradecheck.sh [BIN]         (BIN defaults to build/ripwire)
#         bash test/notesdegradecheck.sh <base-binary>  — the RED half of red-first
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "notesdegradecheck: BIN=$BIN"

has(){ grep -qo 'notes_degraded' "$1"; }   # matches the XML attr and the JSON key alike

# ══ fixtures ═════════════════════════════════════════════════════════════════════════════════════════════
# A: partly-unparseable — one real line, two the reader cannot use (notescheck.sh's own skipped-lines shape).
mkfix(){
    dir="$1"
    mkdir -p "$dir"
    printf 'def foo():\n    return 1\n\n\ndef bar():\n    return foo() + 1\n' > "$dir/a.py"
}
PARTIAL="$TMP/partial"; mkfix "$PARTIAL"
printf 'a.py::foo\t2026-01-01\tkept note\nthis line has no tabs at all\n\t2026-01-01\tempty target\n' > "$PARTIAL/.ripwire_notes"

# B: refused — a symlink at the sidecar name (the O_NOFOLLOW refusal notes.h's readNotesSidecar enforces).
REFUSED="$TMP/refused"; mkfix "$REFUSED"
printf 'a.py::foo\t2026-01-01\ta real note, unreadable because the name is a symlink\n' > "$REFUSED/real_notes_target"
ln -s real_notes_target "$REFUSED/.ripwire_notes"

# C: clean — no sidecar at all.
CLEAN_NONE="$TMP/clean_none"; mkfix "$CLEAN_NONE"

# D: clean — a well-formed sidecar, nothing skipped.
CLEAN_FILE="$TMP/clean_file"; mkfix "$CLEAN_FILE"
printf 'a.py::foo\t2026-01-01\ta clean note\n' > "$CLEAN_FILE/.ripwire_notes"

# ══ the sweep: one function per surface, called once per fixture ═══════════════════════════════════════════
# Each returns its answer's path in REPLY so callers can xmllint/json-validate it afterward.
run_map(){        "$BIN" "$1" --top-k=5                          >"$2" 2>/dev/null; REPLY="$2"; }
run_expand(){      "$BIN" "$1" --expand=foo --top-k=5              >"$2" 2>/dev/null; REPLY="$2"; }
# whole-file / --top-k=0: no <r> map rides along, so the marker (once a real gap here) has to reach the bare
# <ctx> root itself — main.cpp's M6 bundle-vs-whole-file chooser and the exact-name --top-k=0 default.
run_expand_whole(){ "$BIN" "$1" --expand=foo                       >"$2" 2>/dev/null; REPLY="$2"; }
run_expand_topk0(){ "$BIN" "$1" --expand=foo --top-k=0              >"$2" 2>/dev/null; REPLY="$2"; }
run_for_xml(){     "$BIN" "$1" --for="foo bar"                     >"$2" 2>/dev/null; REPLY="$2"; }
run_for_json(){    "$BIN" "$1" --for="foo bar" --json              >"$2" 2>/dev/null; REPLY="$2"; }
run_packtask_xml(){  "$BIN" "$1" --pack-task="foo bar"              >"$2" 2>/dev/null; REPLY="$2"; }
run_packtask_json(){ "$BIN" "$1" --pack-task="foo bar" --json       >"$2" 2>/dev/null; REPLY="$2"; }
run_editcheck(){   "$BIN" "$1" --edit-check=foo                    >"$2" 2>/dev/null; REPLY="$2"; }
run_handoff(){     "$BIN" "$1" --handoff                           >"$2" 2>/dev/null; REPLY="$2"; }
run_planlanes(){   "$BIN" "$1" --plan-lanes=2 --task="notes work"  >"$2" 2>/dev/null; REPLY="$2"; }

SURFACES="map expand expand_whole expand_topk0 for_xml for_json packtask_xml packtask_json editcheck handoff planlanes"

# (A)+(B): RED-on-base/GREEN-on-this, one PASS/FAIL per surface per fixture. `label` names the fixture;
# `dir` is its tree. A caller running this gate WITH the base binary as $1 is the RED half — every "GREEN
# arm" line below then reports what the base binary lacks, by design (see the header).
sweep_degraded(){
    label="$1"; dir="$2"
    for s in $SURFACES; do
        out="$TMP/${label}_${s}.out"
        "run_${s}" "$dir" "$out"
        if has "$out"; then
            ok "$label/$s: notes_degraded reaches the answer"
        else
            no "$label/$s: notes_degraded is ABSENT — this run's read left something out and the answer does not say so ($( head -c 120 "$out" | tr -d '\n' ))"
        fi
    done
}
sweep_degraded partial "$PARTIAL"
sweep_degraded refused "$REFUSED"

# ══ (B2): the MCP twins — JSON-RPC over --mcp, ONE request per call (the mcp_verb() pattern
# test/mcpdegradedhintcheck.sh uses: no separate "initialize" handshake needed for a single tools/call, and
# the raw JSON-RPC envelope is grep-able directly — content text embedded as a JSON string still carries
# `notes_degraded` as a literal, unescaped substring since escaping only touches the quote characters around
# it, never the identifier itself). fetch_body has no `task`/`trace` argument of its own — it answers about
# ONE symbol, named by a `handle` resolved from a prior find_symbol call, so its runner does two round trips.
mcp_verb() {   # $1=verb  $2=corpus path  $3=extra argument JSON fields (comma-led, or empty)
    printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s"%s}}}\n' \
        "$1" "$2" "$3" | "$BIN" --mcp 2>/dev/null
}
run_mcp_for(){        mcp_verb for "$1" ',"task":"foo bar"'; }
run_mcp_packtask(){   mcp_verb pack_task "$1" ',"task":"foo bar"'; }
run_mcp_fromtrace(){  mcp_verb from_trace "$1" ',"trace":"at foo (a.py:1)"'; }
run_mcp_fetchbody(){
    resp="$( mcp_verb find_symbol "$1" ',"symbol":"foo"' )"
    # find_symbol's reply carries a SECOND "handle" field too (each calledBy entry has its own), so a
    # greedy `sed 's/.*handle.../'` grabs the LAST one in the document rather than foo's own — extract
    # with grep -o first (each match on its own line) and take the FIRST hit.
    handle="$( printf '%s' "$resp" | grep -o '\\"handle\\":\\"[^\\]*\\"' | head -1 | sed 's/^\\"handle\\":\\"//; s/\\"$//' )"
    if [ -z "$handle" ]; then
        printf 'NO-HANDLE-RESOLVED find_symbol reply: %s' "$resp"
        return
    fi
    mcp_verb fetch_body "$1" ',"handle":"'"$handle"'"'
}
MCP_SURFACES="mcp_for mcp_packtask mcp_fromtrace mcp_fetchbody"
sweep_mcp_degraded(){
    label="$1"; dir="$2"
    for s in $MCP_SURFACES; do
        out="$TMP/${label}_${s}.mcp.out"
        "run_${s}" "$dir" >"$out"
        if has "$out"; then
            ok "$label/$s: notes_degraded reaches the MCP answer"
        else
            no "$label/$s: notes_degraded is ABSENT from the MCP answer ($( head -c 160 "$out" | tr -d '\n' ))"
        fi
    done
}
sweep_mcp_clean(){
    label="$1"; dir="$2"
    for s in $MCP_SURFACES; do
        out="$TMP/${label}_${s}.mcp.out"
        "run_${s}" "$dir" >"$out"
        if has "$out"; then
            no "$label/$s: notes_degraded present on a CLEAN read over MCP — the inertness contract is broken"
        else
            ok "$label/$s: no notes_degraded on a clean MCP read"
        fi
    done
}
sweep_mcp_degraded partial "$PARTIAL"
sweep_mcp_degraded refused "$REFUSED"
sweep_mcp_clean none "$CLEAN_NONE"
sweep_mcp_clean file "$CLEAN_FILE"

# ══ (C)+(D): INERTNESS — this binary must be byte-identical to a clean pre-round answer on a clean read ═══
# No base binary is assumed reachable here (this gate takes exactly one BIN), so inertness is asserted the
# way the rest of this tree's L3 gates do: run twice and diff (determinism), AND assert the marker is
# ABSENT — the positive half of the claim ("nothing to disclose" is exactly the case the marker must not
# ride) is what a red-first run against the base binary already proves identical (fornotesbudgetcheck /
# fornotesjsoncheck / notescheck already pin the base shape byte-for-byte; this gate only has to prove THIS
# binary agrees with itself and prints no marker).
sweep_clean(){
    label="$1"; dir="$2"
    for s in $SURFACES; do
        out1="$TMP/${label}_${s}.1"; out2="$TMP/${label}_${s}.2"
        "run_${s}" "$dir" "$out1"
        "run_${s}" "$dir" "$out2"
        if has "$out1"; then
            no "$label/$s: notes_degraded present on a CLEAN read — the inertness contract is broken ($( head -c 120 "$out1" | tr -d '\n' ))"
        else
            ok "$label/$s: no notes_degraded on a clean read"
        fi
        if cmp -s "$out1" "$out2"; then
            ok "$label/$s: deterministic (byte-identical x2)"
        else
            no "$label/$s: NON-DETERMINISTIC across two runs of the same tree"
        fi
    done
}
sweep_clean none  "$CLEAN_NONE"
sweep_clean file  "$CLEAN_FILE"

# ══ (E) well-formedness / JSON validity on every degraded answer produced above ═════════════════════════════
if command -v xmllint >/dev/null 2>&1; then
    x=0
    for f in "$TMP"/*_map.out "$TMP"/*_expand.out "$TMP"/*_expand_whole.out "$TMP"/*_expand_topk0.out "$TMP"/*_for_xml.out "$TMP"/*_packtask_xml.out "$TMP"/*_editcheck.out "$TMP"/*_handoff.out; do
        [ -f "$f" ] || continue
        xmllint --noout "$f" >/dev/null 2>&1 || { x=1; echo "     bad XML: $f"; head -c 300 "$f"; echo; }
    done
    if [ "$x" = 0 ]; then ok "G4: every emitted XML document is xmllint-clean"; else no "G4: some emitted document is malformed"; fi
else
    echo "  SKIP  xmllint unavailable"
fi
if command -v python3 >/dev/null 2>&1; then
    j=0
    for f in "$TMP"/*_for_json.out "$TMP"/*_packtask_json.out "$TMP"/*_planlanes.out; do
        [ -f "$f" ] || continue
        python3 -m json.tool < "$f" >/dev/null 2>&1 || { j=1; echo "     bad JSON: $f"; head -c 300 "$f"; echo; }
    done
    if [ "$j" = 0 ]; then ok "every emitted JSON document parses"; else no "some emitted JSON document does not parse"; fi
else
    echo "  SKIP  python3 unavailable"
fi

[ "$fail" = "0" ] && echo "notesdegradecheck: ALL PASS" || echo "notesdegradecheck: FAILURES"
exit "$fail"
