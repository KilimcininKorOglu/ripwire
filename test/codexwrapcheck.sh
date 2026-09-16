#!/usr/bin/env bash
# codexwrapcheck.sh — Codex setup stays CLI-first and restricts optional MCP to audit/health verbs.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "codexwrapcheck: no binary at $BIN — build first"; exit 2; }
"$BIN" wrap codex --force >"$TMP/out" 2>"$TMP/err"

# CLI-FIRST, asserted as the header has always claimed. Until 2026-09-08 this line asserted the
# first actionable line was "[mcp_servers.ripwire]" -- the MCP table -- which contradicted this
# gate's own title. It passed only because the codex recipe emitted no CLI line at all, so the TOML
# stanza was the only actionable line there was: a proxy that had quietly stopped measuring the
# thing it named. The recipe now leads with the CLI, so the assertion says so.
first_command="$( grep -v '^#' "$TMP/out" | sed '/^[[:space:]]*$/d' | head -1 )"
case "$first_command" in
    *" . --for="*) ;;
    *) echo "codexwrapcheck: first actionable line is not the CLI invocation: $first_command"; exit 1 ;;
esac
grep -v '^#' "$TMP/out" | grep -q '^\[mcp_servers\.ripwire\]$' || {
    echo "codexwrapcheck: the TOML alternative is gone -- it is still Codex's documented MCP form"
    exit 1
}
grep -q '^\[mcp_servers\.ripwire\]$' "$TMP/out" || { echo "codexwrapcheck: TOML fallback missing"; exit 1; }
grep -q '^enabled_tools = \["analyze", "quality_delta", "flags", "doc_drift"\]$' "$TMP/out" \
    || { echo "codexwrapcheck: MCP is not restricted to audit/health verbs"; exit 1; }
grep -q '^default_tools_approval_mode = "approve"$' "$TMP/out" \
    || { echo "codexwrapcheck: audit-only MCP approval mode missing"; exit 1; }
grep -q '^bash skills/install\.sh --codex' "$TMP/out" || { echo "codexwrapcheck: canonical skill install missing"; exit 1; }
grep -q '^bash skills/install\.sh --codex --hook' "$TMP/out" || { echo "codexwrapcheck: Codex hook install missing"; exit 1; }
# A skills tree the pre-recipe scan cannot descend. wrapScanSkillDir is noexcept, and its range-for advanced a
# recursive_directory_iterator with the THROWING operator++: a ./skills tree nested past the path-name limit
# ended `ripwire wrap` in std::terminate (SIGABRT, exit 134) before any recipe. The walk now advances with
# increment(ec), says on stderr that the scan stopped early, and still emits the recipe.
DEEPROOT="$TMP/deepskills"; mkdir -p "$DEEPROOT/skills"
python3 - "$DEEPROOT/skills" <<'PYDEEP'
import os, sys
os.chdir(sys.argv[1])
for i in range(12):
    name = "d%02d" % i + "x" * 96
    os.mkdir(name)
    os.chdir(name)
open("SKILL.md", "w").write("hello\n")
PYDEEP
( cd "$DEEPROOT" && "$BIN" wrap codex --force ) >"$TMP/deep.out" 2>"$TMP/deep.err"; rc_deep=$?
[ "$rc_deep" -eq 0 ] || { echo "codexwrapcheck: a ./skills tree past the path-name limit exits $rc_deep (134 = the throw inside noexcept): $( tail -1 "$TMP/deep.err" )"; exit 1; }
grep -q 'skill scan of ./skills stopped early' "$TMP/deep.err" \
    || { echo "codexwrapcheck: the early-stopped skill scan was not disclosed: $( head -c 300 "$TMP/deep.err" )"; exit 1; }
grep -q '^\[mcp_servers\.ripwire\]$' "$TMP/deep.out" || { echo "codexwrapcheck: no recipe after the early-stopped scan"; exit 1; }
echo "codexwrapcheck: ALL PASS"
