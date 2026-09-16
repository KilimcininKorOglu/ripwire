#!/usr/bin/env bash
# githardencheck.sh — gate for the git-config trust boundary (harvest round 2026-09-09, the markitdown
# "state the privilege model of every shell-out" lesson, measured against this tree's own git calls).
#
# ripwire runs READ-ONLY git inside the analysed checkout (`status --porcelain` for the +dirty stamp,
# `ls-files`, `log`, `diff --numstat`, `archive`, `rev-parse` — 82 calls across a 13-verb sweep, logged
# through a PATH shim). Git honours the checkout's OWN .git/config, and one key there turns a read-only
# call into arbitrary code: a HOOK-form `core.fsmonitor` (any value that is not a boolean) is a command
# git runs on every status/diff/ls-files. Measured before the fix: a fixture hook fired THREE times per
# `--situ` and once per default map. A cloned repo never carries that config (git clone does not copy
# .git/config), but a tarball-delivered tree, a copied worktree, or a shared checkout does, and ripwire
# runs unattended inside agent loops over directories nobody inspected.
#
# The fix is ONE site: at process start, if any crawl root configures a hook-form fsmonitor, the process
# appends `core.fsmonitor=false` to git's GIT_CONFIG_COUNT/KEY/VALUE environment override (so every git
# child inherits it) and says so on stderr (git_harden=fsmonitor-hook) and in --doctor. A BOOLEAN
# core.fsmonitor — git's builtin daemon, a real speedup on 100k-file trees — is deliberately left alone:
# the override is applied only to the form that executes code. The probe (`git config --get`) runs no hook
# (measured inert).
#
# Arms:
#   (A) presence: the fixture's hook FIRES under plain `git status` — proves the fixture is live; if git
#       ignores hook-form fsmonitor here the gate cannot conclude and exits 2 rather than pass vacuously.
#   (B) `ripwire <fx> --situ` leaves the hook unfired (RED before the fix: 3 firings).
#   (C) the disclosure: stderr carries git_harden=fsmonitor-hook; stdout does NOT (no leak into the XML).
#   (D) `--doctor` emits <c n="git-config-trust" ok="1" fsmonitor="hook" neutralised="1"/>.
#   (E) mutation control — a COPY of the fixture with core.fsmonitor=false (boolean): the mutation is
#       asserted to have TAKEN, the identical extraction is re-run, and it must DIFFER (no git_harden= line,
#       fsmonitor="off" neutralised="0") — the override must not touch the boolean form.
#   (F) env preservation, through a PATH shim that logs what the git CHILD saw: a caller's own
#       GIT_CONFIG_COUNT=1 entry survives (COUNT becomes 2, ours is appended, theirs stays at index 0); on
#       the boolean copy COUNT stays 1.
#   (H) the cheap pre-scan is sound: a hook reached only through `[include] path=` is still neutralised.
#   (I) a linked worktree (`.git` is a file naming a gitdir; the config lives in the commondir) is still probed.
#   (J) the git-backed verbs across root shapes and entry points. Each shape first proves plain git fires the
#       hook THERE (presence), then runs the git-backed verbs (map, --situ, --quality-delta, --hotspots,
#       --rank-by=churn, --doctor) and requires zero firings: (a) the repo root, (b) a subdirectory root,
#       (c) a linked-worktree subdirectory root, (d) GIT_DIR/GIT_WORK_TREE set with a subdirectory root, (e) an
#       MCP stdio server started with NO root whose client names the tree per request, (f) --plan-lint=FILE
#       where FILE lives in the hook-configured checkout and the crawl root is elsewhere. Green on the fix,
#       and each presence control is what stops the arm passing vacuously.
#   (K) through a PATH shim: every git child ripwire starts carries --no-optional-locks and
#       core.fsmonitor=false on its command line — except the one `config --get core.fsmonitor` probe, which
#       must read the configured value the flag would mask.
#   (L) structural: no executed git command in src/ is spelled outside rw::gitCmd(); two display-only
#       spellings and the probe are an allowlist whose every row must still match (a stale row fails), and a
#       mutation control injects one bare spelling into a COPY of src/ and requires the same scan to find it.
#   (M) the DISCLOSURE follows the governing repository, not root/.git: the --situ runs of (J) at a subdirectory,
#       a linked-worktree subdirectory and under GIT_DIR each carry git_harden=fsmonitor-hook on stderr
#       (githarden.h asks git which gitdir/commondir governs the root).
#   (G) determinism: two `--situ` stdouts are byte-identical.
#
# Usage: RIPWIRE_BIN=build/ripwire bash test/githardencheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
REALGIT="$( command -v git )"
[ -n "$REALGIT" ] || { echo "git not on PATH — this gate needs it"; exit 2; }
echo "githardencheck: BIN=$BIN git=$( "$REALGIT" --version )"

TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$XDG_CACHE_HOME"   # never the user's cache, never the checkout

# ── the fixture: one commit, one .c file, a HOOK-form core.fsmonitor that leaves a mark when run ────────
FX="$TMP/fx"; mkdir -p "$FX"
cat > "$TMP/hook.sh" <<EOF
#!/bin/bash
echo "\$*" >> "$TMP/MARK"
printf '/\\0'
EOF
chmod +x "$TMP/hook.sh"
( cd "$FX" && "$REALGIT" init -q && printf 'int add( int a, int b ) { return a + b; }\nint main() { return add( 1, 2 ); }\n' > a.c \
    && mkdir sub && printf 'int sub( int a, int b ) { return a - b; }\n' > sub/b.c \
    && printf '# Plan\n\n## Step one\nTouch `sub/b.c`.\n' > steps.md \
    && "$REALGIT" add -A && "$REALGIT" -c user.name=g -c user.email=g@g commit -qm init \
    && "$REALGIT" config core.fsmonitor "$TMP/hook.sh" ) || { echo "fixture build failed"; exit 2; }

fired(){ [ -f "$TMP/MARK" ] && wc -l < "$TMP/MARK" | tr -d ' ' || echo 0; }

# ── (A) presence: plain git fires the hook ────────────────────────────────────────────────────────────
rm -f "$TMP/MARK"; "$REALGIT" -c core.quotepath=false -C "$FX" status --porcelain >/dev/null 2>&1
if [ "$( fired )" -ge 1 ]; then
    ok "(A) presence: hook-form core.fsmonitor fires under plain git status ($( fired ) call) — the fixture is live"
else
    echo "  SKIP  (A) this git does not run a hook-form core.fsmonitor here — the gate cannot conclude (exit 2)"; exit 2
fi

# ── (B)+(C) ripwire --situ: hook silent, disclosure on stderr only ─────────────────────────────────────
rm -f "$TMP/MARK"
"$BIN" "$FX" --situ > "$TMP/situ.out" 2> "$TMP/situ.err"
[ "$( fired )" -eq 0 ] \
    && ok "(B) ripwire --situ does not run the checkout's hook-form fsmonitor (0 firings)" \
    || no "(B) ripwire --situ ran the checkout's hook-form fsmonitor $( fired ) time(s): $( head -3 "$TMP/MARK" | tr '\n' ';' )"
grep -q 'git_harden=fsmonitor-hook' "$TMP/situ.err" \
    && ok "(C) stderr discloses the neutralisation (git_harden=fsmonitor-hook): $( grep -m1 'git_harden=' "$TMP/situ.err" )" \
    || no "(C) stderr carries no git_harden=fsmonitor-hook line: $( head -c 300 "$TMP/situ.err" )"
grep -q 'git_harden=' "$TMP/situ.out" \
    && no "(C) the disclosure leaked into stdout (the XML must not carry a stderr note)" \
    || ok "(C) stdout carries no git_harden= (disclosure stays on stderr)"

# ── (D) --doctor row ────────────────────────────────────────────────────────────────────────────────────
DOC="$( "$BIN" "$FX" --doctor 2>/dev/null )"
DOCROW="$( printf '%s' "$DOC" | grep -oE '<c n="git-config-trust"[^>]*/>' )"
{ printf '%s' "$DOCROW" | grep -q 'ok="1"' && printf '%s' "$DOCROW" | grep -q 'fsmonitor="hook"' && printf '%s' "$DOCROW" | grep -q 'neutralised="1"'; } \
    && ok "(D) --doctor row: $DOCROW" \
    || no "(D) --doctor lacks <c n=\"git-config-trust\" ok=\"1\" fsmonitor=\"hook\" neutralised=\"1\"/>: got '${DOCROW:-<absent>}'"

# ── (E) mutation control: the BOOLEAN form must be left alone ───────────────────────────────────────────
FB="$TMP/fb"; cp -R "$FX" "$FB"; "$REALGIT" -C "$FB" config core.fsmonitor false
[ "$( "$REALGIT" -C "$FB" config --get core.fsmonitor )" = "false" ] \
    && ok "(E) mutation took: the copy's core.fsmonitor reads 'false'" \
    || { no "(E) mutation did NOT take — control void"; }
"$BIN" "$FB" --situ > "$TMP/situb.out" 2> "$TMP/situb.err"
DOCB="$( "$BIN" "$FB" --doctor 2>/dev/null | grep -oE '<c n="git-config-trust"[^>]*/>' )"
grep -q 'git_harden=' "$TMP/situb.err" \
    && no "(E) the boolean form was ALSO neutralised — the override must be scoped to the hook form: $( grep -m1 git_harden= "$TMP/situb.err" )" \
    || ok "(E) boolean core.fsmonitor=false: no git_harden= line (untouched)"
{ printf '%s' "$DOCB" | grep -q 'fsmonitor="off"' && printf '%s' "$DOCB" | grep -q 'neutralised="0"'; } \
    && ok "(E) --doctor on the boolean copy: $DOCB" \
    || no "(E) --doctor on the boolean copy should say fsmonitor=\"off\" neutralised=\"0\": got '${DOCB:-<absent>}'"
[ "$DOCROW" != "$DOCB" ] \
    && ok "(E) the two extractions differ (hook vs boolean) — the control has contrast" \
    || no "(E) identical doctor rows for the hook and boolean fixtures — the arm cannot see the difference"

# ── (F) env preservation, observed from the git CHILD through a PATH shim ────────────────────────────────
mkdir -p "$TMP/shim"
cat > "$TMP/shim/git" <<EOF
#!/bin/bash
printf 'COUNT=%s K0=%s V0=%s K1=%s V1=%s\\n' "\${GIT_CONFIG_COUNT:-}" "\${GIT_CONFIG_KEY_0:-}" "\${GIT_CONFIG_VALUE_0:-}" "\${GIT_CONFIG_KEY_1:-}" "\${GIT_CONFIG_VALUE_1:-}" >> "$TMP/shim.log"
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/shim/git"
rm -f "$TMP/shim.log"
PATH="$TMP/shim:$PATH" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=gateprobe "$BIN" "$FX" --situ >/dev/null 2>&1
SEEN="$( sort -u "$TMP/shim.log" 2>/dev/null | head -3 | tr '\n' ';' )"
grep -q '^COUNT=2 K0=user.name V0=gateprobe K1=core.fsmonitor V1=false$' "$TMP/shim.log" 2>/dev/null \
    && ok "(F) the git child saw the caller's entry at index 0 and ours appended at index 1 (COUNT=2)" \
    || no "(F) the git child's override block is wrong — expected COUNT=2 K0=user.name V0=gateprobe K1=core.fsmonitor V1=false, saw: ${SEEN:-<nothing logged>}"
rm -f "$TMP/shim.log"
PATH="$TMP/shim:$PATH" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=gateprobe "$BIN" "$FB" --situ >/dev/null 2>&1
grep -q '^COUNT=1 K0=user.name V0=gateprobe K1= V1=$' "$TMP/shim.log" 2>/dev/null \
    && ok "(F) on the boolean copy the caller's block is passed through untouched (COUNT=1)" \
    || no "(F) the boolean copy's git child saw a changed block: $( sort -u "$TMP/shim.log" 2>/dev/null | head -3 | tr '\n' ';' )"

# ── (H) the cheap tier must not open a hole: a hook reached only through [include] ──────────────────────
# The startup probe reads the LOCAL config files for the bytes "fsmonitor"/"include" before paying for a git
# subprocess. A hostile config that hides the key behind an include must still be caught.
FH="$TMP/fh"; cp -R "$FX" "$FH"
printf '[core]\n\tfsmonitor = %s\n' "$TMP/hook.sh" > "$TMP/hidden.inc"
( cd "$FH" && "$REALGIT" config --unset core.fsmonitor && "$REALGIT" config include.path "$TMP/hidden.inc" )
grep -qi fsmonitor "$FH/.git/config" \
    && no "(H) the fixture still spells fsmonitor in .git/config — the include arm is not testing the include" \
    || ok "(H) mutation took: .git/config no longer spells fsmonitor; the key lives only behind include.path"
rm -f "$TMP/MARK"; "$REALGIT" -C "$FH" status --porcelain >/dev/null 2>&1
if [ "$( fired )" -ge 1 ]; then ok "(H) presence: git itself follows the include (hook fired $( fired ))"; else no "(H) git did not follow the include — the arm cannot conclude"; fi
rm -f "$TMP/MARK"; "$BIN" "$FH" --situ >/dev/null 2> "$TMP/situh.err"
[ "$( fired )" -eq 0 ] && grep -q 'git_harden=fsmonitor-hook' "$TMP/situh.err" \
    && ok "(H) a hook reached only through [include] is still neutralised and disclosed" \
    || no "(H) include-hidden hook: fired=$( fired ), disclosure=$( grep -c git_harden= "$TMP/situh.err" )"

# ── (I) a linked worktree: .git is a FILE naming a gitdir whose commondir holds the config ────────────────
"$REALGIT" -C "$FX" worktree add -q "$TMP/wt" -b gatewt >/dev/null 2>&1 || no "(I) could not create a linked worktree"
if [ -f "$TMP/wt/.git" ]; then ok "(I) the worktree's .git is a file ($( head -c 40 "$TMP/wt/.git" | tr -d '\n' )…)"; else no "(I) expected $TMP/wt/.git to be a gitdir: FILE"; fi
rm -f "$TMP/MARK"; "$REALGIT" -C "$TMP/wt" status --porcelain >/dev/null 2>&1
if [ "$( fired )" -ge 1 ]; then ok "(I) presence: the shared config's hook fires in the worktree ($( fired ))"; else no "(I) the hook did not fire in the worktree — the arm cannot conclude"; fi
rm -f "$TMP/MARK"; "$BIN" "$TMP/wt" --situ >/dev/null 2> "$TMP/situi.err"
[ "$( fired )" -eq 0 ] && grep -q 'git_harden=fsmonitor-hook' "$TMP/situi.err" \
    && ok "(I) the worktree root is neutralised and disclosed (gitdir/commondir resolved)" \
    || no "(I) worktree root: fired=$( fired ), disclosure=$( grep -c git_harden= "$TMP/situi.err" )"
"$REALGIT" -C "$FX" worktree remove --force "$TMP/wt" >/dev/null 2>&1 || true

# ── (J) every directory git runs in ─────────────────────────────────────────────────────────────────────
# nofire TAG CMD…: run one ripwire invocation (any env prefix via `env`), stdout/stderr to $TMP/j-TAG.*,
# and require the hook NOT to have fired during it.
nofire(){
    jtag="$1"; shift
    rm -f "$TMP/MARK"
    "$@" > "$TMP/j-$jtag.out" 2> "$TMP/j-$jtag.err"
    jn="$( fired )"
    [ "$jn" -eq 0 ] \
        && ok "(J) $jtag: the hook did not run (0 firings)" \
        || no "(J) $jtag: the hook ran $jn time(s): $( head -2 "$TMP/MARK" | tr '\n' ';' )"
    return 0
}
# presence TAG CMD…: plain git (no policy flags) in the same place MUST fire, or the shape proves nothing.
presence(){
    ptag="$1"; shift
    rm -f "$TMP/MARK"
    "$@" >/dev/null 2>&1
    [ "$( fired )" -ge 1 ] \
        && ok "(J) $ptag presence: plain git fires the hook here ($( fired ))" \
        || no "(J) $ptag presence: plain git did NOT fire the hook here — this shape cannot conclude"
    return 0
}
verbsweep(){
    vshape="$1"; shift   # remaining args: an optional `env K=V …` prefix, ending with the root
    nofire "$vshape-map"          "$@"
    nofire "$vshape-situ"         "$@" --situ
    nofire "$vshape-quality-delta" "$@" --quality-delta
    nofire "$vshape-hotspots"     "$@" --hotspots
    nofire "$vshape-churn"        "$@" --rank-by=churn
    nofire "$vshape-doctor"       "$@" --doctor
}

presence "a-root"   "$REALGIT" -C "$FX" status --porcelain
verbsweep "a-root"  "$BIN" "$FX"

presence "b-subdir"  "$REALGIT" -C "$FX/sub" status --porcelain
verbsweep "b-subdir" "$BIN" "$FX/sub"

"$REALGIT" -C "$FX" worktree add -q "$TMP/wtj" -b gatewtj >/dev/null 2>&1 || no "(J) could not create the linked worktree for shape (c)"
if [ -f "$TMP/wtj/.git" ] && [ -d "$TMP/wtj/sub" ]; then ok "(J) c-worktree-subdir: $TMP/wtj/.git is a gitdir file and sub/ is checked out"; else no "(J) c-worktree-subdir: the worktree fixture is not the shape it claims"; fi
presence "c-worktree-subdir"  "$REALGIT" -C "$TMP/wtj/sub" status --porcelain
verbsweep "c-worktree-subdir" "$BIN" "$TMP/wtj/sub"

presence "d-git-dir"  env GIT_DIR="$FX/.git" GIT_WORK_TREE="$FX" "$REALGIT" -C "$FX/sub" status --porcelain
verbsweep "d-git-dir" env GIT_DIR="$FX/.git" GIT_WORK_TREE="$FX" "$BIN" "$FX/sub"

# (e) an MCP server started with no root; the client names the hook-configured tree in the request itself.
mcpsession(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"githardencheck","version":"1"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"%s"}}}\n' "$1"
}
mcpsession "$FX" > "$TMP/j-mcp.in"
nofire "e-mcp-request-path" sh -c '"$1" --mcp < "$2"' _ "$BIN" "$TMP/j-mcp.in"
grep -q '"id":2,"result"' "$TMP/j-e-mcp-request-path.out" \
    && ok "(J) e-mcp-request-path presence: the request was answered (id 2 result), so its git calls ran" \
    || no "(J) e-mcp-request-path: no id 2 result — the arm cannot conclude: $( head -c 300 "$TMP/j-e-mcp-request-path.out" )"

# (f) --plan-lint=FILE: git resolves FILE's own repository, which is not the crawl root.
mkdir -p "$TMP/elsewhere" && printf 'int e;\n' > "$TMP/elsewhere/e.c"
nofire "f-plan-lint-file" "$BIN" "$TMP/elsewhere" --plan-lint="$FX/steps.md"
grep -q 'plan-lint' "$TMP/j-f-plan-lint-file.out" \
    && ok "(J) f-plan-lint-file presence: plan-lint answered for the file (its git probe ran)" \
    || no "(J) f-plan-lint-file: no plan-lint output — the arm cannot conclude: $( head -c 300 "$TMP/j-f-plan-lint-file.err" )"
"$REALGIT" -C "$FX" worktree remove --force "$TMP/wtj" >/dev/null 2>&1 || true

# ── (M) the disclosure follows the governing repository ───────────────────────────────────────────────────
for mshape in b-subdir c-worktree-subdir d-git-dir; do
    grep -q 'git_harden=fsmonitor-hook' "$TMP/j-$mshape-situ.err" 2>/dev/null \
        && ok "(M) $mshape: stderr discloses the hook form (git_harden=fsmonitor-hook)" \
        || no "(M) $mshape: no git_harden=fsmonitor-hook disclosure on stderr: $( head -c 200 "$TMP/j-$mshape-situ.err" 2>/dev/null )"
done

# ── (K) every git child's command line carries the policy, observed from the child ───────────────────────
mkdir -p "$TMP/shimk"
cat > "$TMP/shimk/git" <<EOF
#!/bin/bash
printf '%s\\n' "\$*" >> "$TMP/shimk.log"
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/shimk/git"
rm -f "$TMP/shimk.log"
for kargs in "" "--situ" "--quality-delta" "--hotspots" "--doctor"; do
    # shellcheck disable=SC2086
    PATH="$TMP/shimk:$PATH" "$BIN" "$FX/sub" $kargs >/dev/null 2>&1
done
KTOTAL="$( wc -l < "$TMP/shimk.log" 2>/dev/null | tr -d ' ' )"; KTOTAL="${KTOTAL:-0}"
KPROBE="$( grep -c ' config --get core.fsmonitor$' "$TMP/shimk.log" 2>/dev/null )"
KBAD="$( grep -v ' config --get core.fsmonitor$' "$TMP/shimk.log" 2>/dev/null | grep -vc '^--no-optional-locks -c core.fsmonitor=false' )"
[ "$KTOTAL" -ge 10 ] \
    && ok "(K) presence: the shim logged $KTOTAL git child invocations across five verbs" \
    || no "(K) presence: only ${KTOTAL} git child invocations logged — the arm cannot conclude"
[ "$KBAD" -eq 0 ] \
    && ok "(K) every git child ($(( KTOTAL - KPROBE )) policy-bearing + $KPROBE config probe) carried --no-optional-locks -c core.fsmonitor=false" \
    || no "(K) $KBAD git child invocation(s) lacked the policy prefix: $( grep -v ' config --get core.fsmonitor$' "$TMP/shimk.log" | grep -v '^--no-optional-locks -c core.fsmonitor=false' | head -3 | tr '\n' ';' )"

# ── (L) structural: no executed git command spelled outside rw::gitCmd() ─────────────────────────────────
# bare_git_sites DIR: every line under DIR/src that spells a git command literal ("git -c", "git -C", "git --"),
# minus gitcmd.h and the allowlist below. Prints file:line:text, one per offender.
LALLOW_PROBE='" config --get core.fsmonitor 2>/dev/null'   # githarden.h — must read the value the flag would mask
LALLOW_HINT='nextFlag( "", root ) + " diff --exit-code --"' # editplan.h — a next= hint shown to the user, never run
bare_git_sites(){
    grep -rnE '"git (-c|-C|--)' "$1/src" 2>/dev/null | grep -v '/src/gitcmd.h:' | grep -vF "$LALLOW_PROBE" | grep -vF "$LALLOW_HINT"
}
for lrow in "$LALLOW_PROBE" "$LALLOW_HINT"; do
    grep -rqF "$lrow" "$ROOT/src" \
        && ok "(L) allowlist row still matches a real line: $lrow" \
        || no "(L) STALE allowlist row (matches nothing in src/): $lrow"
done
LOFF="$( bare_git_sites "$ROOT" )"
[ -z "$LOFF" ] \
    && ok "(L) no executed git command in src/ is spelled outside rw::gitCmd()" \
    || no "(L) git command(s) spelled outside rw::gitCmd(): $( printf '%s' "$LOFF" | head -3 | tr '\n' ';' )"
mkdir -p "$TMP/lmut" && cp -R "$ROOT/src" "$TMP/lmut/src"
printf '\ninline std::string gitGateMutation( const std::string& r ) { return popenTrimmed( "git -C " + r + " status" ); }\n' >> "$TMP/lmut/src/gitmine.h"
grep -q 'gitGateMutation' "$TMP/lmut/src/gitmine.h" \
    && ok "(L) mutation took: a bare git spelling was appended to a COPY of src/gitmine.h" \
    || no "(L) mutation did NOT take — control void"
[ "$( bare_git_sites "$TMP/lmut" | grep -c 'gitGateMutation' )" -eq 1 ] \
    && ok "(L) mutation control: the same scan finds the injected bare spelling" \
    || no "(L) mutation control: the scan did not find the injected bare spelling — the arm cannot fail"

# ── (G) determinism ─────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FX" --situ > "$TMP/situ2.out" 2>/dev/null
cmp -s "$TMP/situ.out" "$TMP/situ2.out" \
    && ok "(G) two --situ runs on the hook fixture are byte-identical" \
    || no "(G) two --situ runs differ: $( diff "$TMP/situ.out" "$TMP/situ2.out" | head -3 | tr '\n' ';' )"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
