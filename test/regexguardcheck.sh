#!/usr/bin/env bash
# regexguardcheck.sh — src/regexguard.h is THE owner of every user-authored regular expression, and this gate
# is what keeps it the only one.
#
# WHY THIS EXISTS. `--regex` was protected: src/search.h screened the pattern structurally (non-portable
# escapes, the nested-quantifier backtracking family) and refused it by name before either standard library's
# engine saw it (test/regexbombcheck.sh). Three other entry points hand a user's pattern to the same engine and
# skipped that screen, and none of them guarded the MATCH either:
#
#     ripwire rx --graph-query='file(all,"(a+)+z")'          rc=134  libc++abi: uncaught std::regex_error
#     ripwire rx --arch=rules   (deny path zz/.* -> (a+)+z)   rc=134  same abort
#     ripwire rx --match='… (#match? @id "(a+)+z")'           rc=0    the throw was swallowed: a row the
#                                                                     predicate never decided is KEPT
#
# (Apple libc++, whose engine throws error_complexity; on libstdc++, which has no budget, the same calls
# backtrack without end.) And `file()` matched the path WITH the checkout directory in front of it, so
# `file(all,"alpha")` selected every symbol in a clone named `repo_alpha` and none in `repo_beta` — an answer
# decided by where the tree was cloned, which --arch fixed for its own rules long ago and --graph-query never
# got.
#
# ARMS
#   (a) SCREEN AT EVERY ENTRY POINT — a catastrophic pattern through --graph-query file(), an --arch path-rule
#       (FROM and TO), a --match #match? predicate, a --lint-rules #match? predicate and --regex is REFUSED:
#       exit 1, bounded time, never a signal death, the pattern and the construct named on stderr. Each entry
#       point also has a POSITIVE CONTROL: an ordinary pattern on the same fixture still answers.
#   (b) MATCH-TIME EXHAUSTION IS DISCLOSED, NEVER SILENT — the screen is a static approximation (overlapping
#       alternation like (a|a)+z is a real bomb it cannot see), so a regex_error thrown DURING a match must
#       refuse the answer by name rather than abort or report a count the engine never finished measuring.
#       (b1) is portable: the non-NDEBUG fault switch RIPWIRE_FAULT_REGEX_MATCH=1 makes every guarded match
#       throw, on every standard library, and each entry point must refuse. The flavour is ASKED of the binary
#       with a sibling fault switch whose alert is independent of this seam (prcontextcheck's idiom), so a
#       Release build reports the arm unobservable instead of passing or failing it for a switch it compiled
#       out. (b2) drives the REAL engine with (a|a)+z where the binary links libc++, whose engine abandons
#       that match; libstdc++ has no budget and would hang, which is the documented gap, not asserted.
#   (c) STATIC — no std::regex construction, match, iterator, result type or <regex> include in src/ outside
#       src/regexguard.h, over source with comments and string literals blanked (so the words in prose do not
#       count). The allowlist carries a reason per row, a stale row FAILS, and the detector is proved on a
#       planted file (fires) and on a planted clean file (silent) before its verdict on the tree is believed.
#   (e) AN --arch TO PATTERN THAT ONLY FAILS AFTER SUBSTITUTION IS REFUSED, NOT INERT — `a{2,\1}` is a well-formed
#       template that passes the screen, and on an edge whose FROM captured "1" it becomes `a{2,1}`, an invalid
#       interval on every standard library. That rule used to be skipped silently for the edge (exit 0, violations
#       unreported); it must refuse by name, quoting the substituted text, with the other edges' rules still judged.
#   (f) THE SKILL SCANNER READS UNTRUSTED FILES, so its constant patterns go through the same boundary: (f1) the
#       linear EXFILTRATE:net-exfil decision agrees line for line with the regex it replaced, over generated lines
#       judged by an independent oracle (python's re, with `.` spelled [^\r\n] as ECMAScript reads it); (f2) a 200,000-byte
#       fenced `curl curl …` line scans in bounded time (the regex was quadratic: >60 s); (f3) an abandoned match
#       fails CLOSED — a CRITICAL SCAN-INCOMPLETE:regex-abandoned finding at exit 2, never a clean exit 0 and never an
#       abort inside wrap's noexcept scan.
#   (g) THE STACK BOUND — std::regex compiles by recursion, and a 20,000-byte literal --regex died with SIGBUS in a
#       512 KiB grep worker. A pattern over kRegexMaxPatternBytes (2,048) or nesting groups deeper than
#       kRegexMaxGroupDepth (64) is refused by name; exactly at each limit it still compiles.
#   (h) AN UNDECIDED #match? SAYS WHY — a capture-typed `(#match? @f @s)` compiles each match's own text, and three
#       different things can stop it: the screen refuses the captured text, the text does not compile, or the engine
#       abandons the match. One counter and one sentence ("the regex engine abandoned the match") used to cover all
#       three. Each cause now has its own run, fixture and wording; the refusal names the FIRST site (lowest file, then
#       byte) with the captured text, is byte-identical run to run, and --lint-rules says the same.
#   (i) --arch DECIDES DENY FIRST — an allow whose pattern the engine cannot finish must not turn a determinable "no
#       deny can forbid this edge" into a refusal; an undecided allow matters only when a deny fires and no allow
#       matches, and a later allow that matches still permits the edge.
#   (d) file() IS ROOT-RELATIVE — two clones of one tree at different directory names, each run with an
#       absolute and a relative root spelling, must give the SAME count for a pattern naming one clone's
#       directory, and an anchored `^src/` must select the src/ symbols (it selected nothing under an
#       absolute root, because the path began with the checkout's own directories).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/regexguardcheck.sh
#         RIPWIRE_BIN=<origin/main binary> bash test/regexguardcheck.sh    # must FAIL: (a) rc=134, (b), (c), (d)
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "regexguardcheck: python3 required for the static arm"; exit 2; }
echo "regexguardcheck: BIN=$BIN"

# A refusal must be BOUNDED — on libstdc++ an unguarded bomb backtracks without end — so every run that could
# reach an engine is wall-clock capped. No timeout(1) on a stock macOS: background run plus a polling wait.
capRun(){                        # capRun <seconds> <outfile> <errfile> <args…> -> echoes the exit status, or TIMEOUT
    local capSeconds="$1" outPath="$2" errPath="$3"; shift 3
    "$BIN" "$@" >"$outPath" 2>"$errPath" &
    local runPid=$! waitedTenths=0 capTenths=$(( capSeconds * 10 ))
    while kill -0 "$runPid" 2>/dev/null; do
        [ "$waitedTenths" -ge "$capTenths" ] && { kill -9 "$runPid" 2>/dev/null; wait "$runPid" 2>/dev/null; echo TIMEOUT; return; }
        sleep 0.1; waitedTenths=$(( waitedTenths + 1 ))
    done
    wait "$runPid"; echo $?
}

# ── the fixture: a directory whose NAME is a long run of 'a' (the backtracking bait lives in the PATH, which is
#    what file() and --arch match), an include edge from zz/ into it, a C++ file whose identifiers a #match?
#    predicate can select and whose string literal (88 'a') a real-engine #match? arm can exhaust on, and a
#    markdown line of 4000 'a' for --regex. Written here so it cannot drift; the rules files sit OUTSIDE it. ────
RUNA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
FIX="$TMP/rxfix"
mkdir -p "$FIX/$RUNA" "$FIX/zz" "$TMP/rules_bomb" "$TMP/rules_ok"
printf 'int aaaa_one() { return 1; }\nint aaaa_two() { return aaaa_one(); }\n' >"$FIX/$RUNA/$RUNA.h"
printf '#include "%s.h"\nint aaaa_three() { return aaaa_two(); }\n' "$RUNA" >"$FIX/$RUNA/$RUNA.c"
printf '#include "../%s/%s.h"\nint zz_caller() { return aaaa_one(); }\n' "$RUNA" "$RUNA" >"$FIX/zz/b.c"
printf '#include "../%s/%s.h"\nint zz_digit() { return aaaa_two(); }\n' "$RUNA" "$RUNA" >"$FIX/zz/d1.c"
printf 'int foo_alpha() { return 0; }\nint foo_beta() { return foo_alpha(); }\nconst char* bait = "%s";\n' "$RUNA$RUNA" >"$FIX/zz/q.cpp"
{ printf '# bait\n'; head -c 4000 /dev/zero | tr '\0' 'a'; printf '\nzz marker line\n'; } >"$FIX/zz/bait.md"
cat >"$TMP/rules_bomb/bomb.yml" <<'YML'
- id: rx-bomb
  language: cpp
  severity: warn
  message: a catastrophic predicate
  query: |
    (function_declarator declarator: (identifier) @fn (#match? @fn "(a+)+z")) @hit
YML
cat >"$TMP/rules_ok/ok.yml" <<'YML'
- id: rx-ok
  language: cpp
  severity: warn
  message: an ordinary predicate
  query: |
    (function_declarator declarator: (identifier) @fn (#match? @fn "^foo_")) @hit
YML
printf 'deny path zz/.* -> (a+)+z\n'         >"$TMP/arch_to_bomb.txt"
printf 'deny path (a+)+z -> .*\n'            >"$TMP/arch_from_bomb.txt"
printf 'deny path zz/.* -> a+/\n'            >"$TMP/arch_ok.txt"
printf 'deny path zz/.* -> (a|a)+z\n'        >"$TMP/arch_alt.txt"
printf '%s\n' 'deny path zz/d(\d)\.c -> a{2,\1}'  >"$TMP/arch_subst.txt"
printf '%s\n' 'deny path zz/(\w+)/.* -> (\1'      >"$TMP/arch_to_unbalanced.txt"
printf '%s\n' 'deny path zz/d(\d)\.c -> a{1,\1}'  >"$TMP/arch_subst_ok.txt"

MATCH_BOMB='(function_declarator declarator: (identifier) @fn (#match? @fn "(a+)+z"))'
MATCH_OK='(function_declarator declarator: (identifier) @fn (#match? @fn "^foo_"))'
MATCH_ALT='((string_literal) @s (#match? @s "(a|a)+z"))'   # the literal holds 88 'a': a capture long enough to exhaust

# ── (a) the screen, at every entry point ──────────────────────────────────────────────────────────────────────
refusedByName(){                 # refusedByName <label> <pattern> <args…>
    local label="$1" pat="$2"; shift 2
    local rc; rc="$( capRun 20 "$TMP/a.out" "$TMP/a.err" "$FIX" --no-cache "$@" )"
    if [ "$rc" = TIMEOUT ]; then
        no "(a) $label: still running after 20 s — the pattern was handed to an engine with no budget"
        return
    fi
    if [ "$rc" -ge 128 ]; then
        no "(a) $label: signal death, exit $rc ($( grep -m1 -o 'terminating.*' "$TMP/a.err" | head -c 120 ))"
        return
    fi
    if [ "$rc" -eq 1 ]; then ok "(a) $label: refused at exit 1"; else no "(a) $label: exit $rc (expected a refusal at exit 1)"; fi
    grep -qF -- "$pat" "$TMP/a.err" && ok "(a) $label: the refusal names the pattern" \
        || no "(a) $label: stderr does not name the pattern: $( head -c 200 "$TMP/a.err" )"
    grep -qi 'backtrack' "$TMP/a.err" && ok "(a) $label: the refusal names the construct (catastrophic backtracking)" \
        || no "(a) $label: stderr does not name the construct: $( head -c 200 "$TMP/a.err" )"
    grep -qE 'count="|hits="|<lint|<arch ' "$TMP/a.out" && no "(a) $label: an answer element was printed beside the refusal" \
        || ok "(a) $label: no answer element on stdout"
}
answers(){                       # answers <label> <expected rc> <stdout ERE that proves an answer> <args…>
    local label="$1" wantRc="$2" proof="$3"; shift 3
    local rc; rc="$( capRun 20 "$TMP/c.out" "$TMP/c.err" "$FIX" --no-cache "$@" )"
    if [ "$rc" = "$wantRc" ] && grep -qE -- "$proof" "$TMP/c.out"; then
        ok "(a) control, $label: an ordinary pattern still answers (exit $rc)"
    else
        no "(a) control, $label: exit $rc, answer proof /$proof/ $( grep -qE -- "$proof" "$TMP/c.out" && echo present || echo ABSENT ): $( head -c 200 "$TMP/c.err" )"
    fi
}

refusedByName "--graph-query file()"      '(a+)+z' --graph-query='file(all,"(a+)+z")'
answers       "--graph-query file()" 0    'count="[1-9]' --graph-query='file(all,"q\.cpp")'
refusedByName "--arch path-rule TO"       '(a+)+z' --arch="$TMP/arch_to_bomb.txt"
refusedByName "--arch path-rule FROM"     '(a+)+z' --arch="$TMP/arch_from_bomb.txt"
answers       "--arch path-rule" 2        'fromLayer="path"' --arch="$TMP/arch_ok.txt"
refusedByName "--match #match?"           '(a+)+z' "--match=$MATCH_BOMB"
answers       "--match #match?" 0         'hits="[1-9]' "--match=$MATCH_OK"
refusedByName "--lint-rules #match?"      '(a+)+z' --lint-rules="$TMP/rules_bomb"
answers       "--lint-rules #match?" 0    'rule="rx-ok"' --lint-rules="$TMP/rules_ok"
refusedByName "--regex (regression)"      '(a+)+z' --regex='(a+)+z'
answers       "--regex" 0                 'hits="[1-9]' --regex='zz marker'

# determinism of a refusal: stderr is a pure function of the pattern
rc1="$( capRun 20 /dev/null "$TMP/d1.err" "$FIX" --no-cache --graph-query='file(all,"(a+)+z")' )"
rc2="$( capRun 20 /dev/null "$TMP/d2.err" "$FIX" --no-cache --graph-query='file(all,"(a+)+z")' )"
if [ "$rc1" = 1 ] && [ "$rc2" = 1 ] && [ -s "$TMP/d1.err" ] && cmp -s "$TMP/d1.err" "$TMP/d2.err"; then ok "(a) the file() refusal is byte-identical run to run"
else no "(a) the file() refusal is not a deterministic refusal (exit $rc1/$rc2, stderr identical: $( cmp -s "$TMP/d1.err" "$TMP/d2.err" && echo yes || echo no ))"; fi

# ── (b1) match-time exhaustion through the fault switch — every standard library, non-NDEBUG flavour ───────────
RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" "$FIX" --top-k=5 --pack-signatures --no-cache >/dev/null 2>"$TMP/probe.err"
if grep -aq 'open_memstream failed' "$TMP/probe.err"; then FAULTS=1; else FAULTS=0; fi

# The whole exhaustion contract, for every entry point, in one helper shared by (b1) and (b2): a bounded exit 1, never
# a signal death; stderr says the engine abandoned the match AND names what the reader must fix — the pattern, or for
# --lint-rules the rule id (the per-evaluation counter is kept per rule group, so the rules are what can be named);
# and no answer element on stdout. Each check is its own row, so a refusal that names nothing cannot pass.
abandonedContract(){             # abandonedContract <arm> <label> <rc> <out> <err> <needle>
    local arm="$1" label="$2" rc="$3" out="$4" err="$5" needle="$6"
    if [ "$rc" = TIMEOUT ] || [ "$rc" -ge 128 ]; then
        no "$arm $label: exit $rc (expected a bounded refusal at exit 1)$( grep -m1 -o 'terminating.*' "$err" | head -c 120 )"
        return
    fi
    if [ "$rc" -eq 1 ]; then ok "$arm $label: an abandoned match refuses at exit 1"
    else no "$arm $label: exit $rc — an abandoned match was answered anyway (silent)"; fi
    if grep -q 'abandoned the match' "$err"; then ok "$arm $label: the refusal says the engine abandoned the match"
    else no "$arm $label: stderr does not disclose the abandoned match: $( head -c 200 "$err" )"; fi
    if grep -qF -- "$needle" "$err"; then ok "$arm $label: the refusal names $needle"
    else no "$arm $label: the refusal does not name $needle: $( head -c 200 "$err" )"; fi
    if grep -qE 'count="|hits="|<lint|<arch |<match ' "$out"; then no "$arm $label: an answer element was printed beside the refusal"
    else ok "$arm $label: no answer element on stdout"; fi
}
exhaustedByName(){               # exhaustedByName <label> <needle> <args…>   (run under RIPWIRE_FAULT_REGEX_MATCH=1)
    local label="$1" needle="$2"; shift 2
    local rc; rc="$( RIPWIRE_FAULT_REGEX_MATCH=1 capRun 20 "$TMP/b.out" "$TMP/b.err" "$FIX" --no-cache "$@" )"
    abandonedContract "(b1)" "$label" "$rc" "$TMP/b.out" "$TMP/b.err" "$needle"
}
if [ "$FAULTS" -eq 1 ]; then
    exhaustedByName "--graph-query file()" 'q\.cpp'    --graph-query='file(all,"q\.cpp")'
    exhaustedByName "--arch path-rule"     'a+/'       --arch="$TMP/arch_ok.txt"
    exhaustedByName "--match #match?"      '^foo_'     "--match=$MATCH_OK"
    exhaustedByName "--lint-rules #match?" 'rx-ok'     --lint-rules="$TMP/rules_ok"
    exhaustedByName "--regex"              'zz marker' --regex='zz marker'
    # the switch is exact "1", like every fault switch in this tree: anything else leaves the answer alone
    RIPWIRE_FAULT_REGEX_MATCH=10 "$BIN" "$FIX" --no-cache --graph-query='file(all,"q\.cpp")' >"$TMP/b10.out" 2>/dev/null
    grep -q 'count="[1-9]' "$TMP/b10.out" && ok "(b1) control: RIPWIRE_FAULT_REGEX_MATCH=10 is not ON (exact \"1\" only)" \
        || no "(b1) control: RIPWIRE_FAULT_REGEX_MATCH=10 changed the answer"
else
    printf '  INFO  (b1) this binary compiles fault switches out (NDEBUG): the injected exhaustion is unobservable BY DESIGN here; the plain-flavour leg proves it\n'
    RIPWIRE_FAULT_REGEX_MATCH=1 "$BIN" "$FIX" --no-cache --graph-query='file(all,"q\.cpp")' >"$TMP/bn.out" 2>/dev/null
    grep -q 'count="[1-9]' "$TMP/bn.out" && ok "(b1) consistency: with the switch compiled out, file() still answers" \
        || no "(b1) consistency: a flavour without fault switches changed its answer under RIPWIRE_FAULT_REGEX_MATCH=1"
fi

# ── (b2) the REAL engine: overlapping alternation passes the structural screen and is abandoned mid-match ──────
LINKS_LIBCXX=0
if command -v otool >/dev/null 2>&1 && otool -L "$BIN" 2>/dev/null | grep -q 'libc++'; then LINKS_LIBCXX=1; fi
if command -v ldd >/dev/null 2>&1 && ldd "$BIN" 2>/dev/null | grep -q 'libc++\.so'; then LINKS_LIBCXX=1; fi
realExhaustion(){                # realExhaustion <label> <args…>   (the needle is the (a|a)+z pattern itself)
    local label="$1"; shift
    local rc; rc="$( capRun 30 "$TMP/r.out" "$TMP/r.err" "$FIX" --no-cache "$@" )"
    abandonedContract "(b2)" "$label" "$rc" "$TMP/r.out" "$TMP/r.err" '(a|a)+z'
}
if [ "$LINKS_LIBCXX" -eq 1 ]; then
    realExhaustion "--graph-query file((a|a)+z)" --graph-query='file(all,"(a|a)+z")'
    realExhaustion "--arch TO (a|a)+z"           --arch="$TMP/arch_alt.txt"
    realExhaustion "--match #match? (a|a)+z"     "--match=$MATCH_ALT"
    realExhaustion "--regex (a|a)+z"             --regex='(a|a)+z'
else
    printf '  INFO  (b2) this binary does not link libc++: libstdc++ has no match budget, so overlapping alternation backtracks\n'
    printf '        without end (the structural screen'"'"'s documented gap); (b1) is the portable proof of the disclosure path\n'
fi

# ── (c) static: the engine is spelled in src/regexguard.h and nowhere else ─────────────────────────────────────
python3 - "$ROOT" "$TMP" <<'PY' >"$TMP/static.txt" 2>&1
import os, re, sys
root, tmp = sys.argv[1], sys.argv[2]
OWNER = "src/regexguard.h"
ALLOW = {
    "src/redact.h":    "the secret-redaction rule table: constant patterns compiled ONCE into a static array on the redaction hot path; never user text",
}
TOKENS = re.compile(r"\bstd::(?:w?regex|basic_regex)\b|\b(?:regex_(?:search|match|replace|iterator|token_iterator|error|constants|traits)|[cs]regex_(?:token_)?iterator|w[cs]?regex_(?:token_)?iterator|[cs]match|w[cs]match|[cs]sub_match|w[cs]sub_match|sub_match|match_results)\b")
INCLUDE = re.compile(r"^[ \t]*#[ \t]*include[ \t]*<regex>", re.M)

def blank(text):
    """Blank comments and string/char literals (raw strings included) to spaces, keeping every offset and newline."""
    out, i, n = list(text), 0, len(text)
    def wipe(a, b):
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i); j = n if j < 0 else j
            wipe(i, j); i = j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); j = n if j < 0 else j + 2
            wipe(i, j); i = j; continue
        m = re.match(r'(?:u8|[uUL])?R"([^()\\ ]{0,16})\(', text[i:])
        if m and (i == 0 or not (text[i - 1].isalnum() or text[i - 1] == "_")):
            close = ")" + m.group(1) + '"'
            j = text.find(close, i + m.end()); j = n if j < 0 else j + len(close)
            wipe(i, j); i = j; continue
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            wipe(i, min(j + 1, n)); i = j + 1; continue
        if c == "'":
            k = i - 1
            while k >= 0 and (text[k].isalnum() or text[k] in "_."):
                k -= 1
            if k + 1 < i and text[k + 1].isdigit():
                i += 1; continue                       # a digit separator: 1'000
            j = i + 1
            while j < n and text[j] != "'":
                j += 2 if text[j] == "\\" else 1
            wipe(i, min(j + 1, n)); i = j + 1; continue
        i += 1
    s = "".join(out)
    assert len(s) == len(text) and all((a == "\n") == (b == "\n") for a, b in zip(s, text)), "blanker moved an offset"
    return s

def hits(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    s = blank(text)
    found = [(s.count("\n", 0, m.start()) + 1, m.group(0)) for m in TOKENS.finditer(s)]
    found += [(s.count("\n", 0, m.start()) + 1, "#include <regex>") for m in INCLUDE.finditer(text) if s[m.start():m.end()].strip()]
    return sorted(found)

# controls first: a detector that cannot fire, or fires on prose, decides nothing
planted = os.path.join(tmp, "planted.h")
with open(planted, "w") as fh:
    fh.write('#include <regex>\nstd::regex re( pat );\nbool b = std::regex_search( s, m, re );\n'
             'for( auto it = std::cregex_iterator( a, z, re ); it != std::cregex_iterator(); ++it ) {}\nstd::smatch caps;\n')
clean = os.path.join(tmp, "clean.h")
with open(clean, "w") as fh:
    fh.write('// std::regex_search( s, re ) in a comment\n/* std::regex r( x ); #include <regex> */\n'
             'const char* a = "std::regex_match( s, re )";\nconst char* b = R"x(std::sregex_iterator)x";\n'
             "int n = 1'000'000; char q = '\"';\nGuardedRegex guarded; RegexCaptures caps;\n")
ph, ch = hits(planted), hits(clean)
print(("PASS" if len(ph) >= 6 else "FAIL") + f"  (c) control: the detector fires on a planted file ({len(ph)} sites)")
print(("PASS" if not ch else "FAIL") + f"  (c) control: the detector is silent on engine words inside comments/strings/raw strings ({len(ch)} sites{': ' + str(ch) if ch else ''})")

scanned, violations, owner_hits, allow_hits = 0, [], 0, {k: 0 for k in ALLOW}
for dp, dn, fn in os.walk(os.path.join(root, "src")):
    dn.sort()
    for f in sorted(fn):
        if not f.endswith((".h", ".hpp", ".cpp", ".inl", ".cc", ".mm")):
            continue
        rel = os.path.relpath(os.path.join(dp, f), root)
        scanned += 1
        h = hits(os.path.join(dp, f))
        if rel == OWNER:
            owner_hits = len(h)
        elif rel in ALLOW:
            allow_hits[rel] = len(h)
        else:
            violations += [f"{rel}:{ln}: {tok}" for ln, tok in h]
print(("PASS" if scanned >= 50 else "FAIL") + f"  (c) population: {scanned} src files scanned")
print(("PASS" if owner_hits > 0 else "FAIL") + f"  (c) the owner {OWNER} exists and spells the engine ({owner_hits} sites)")
for rel, cnt in sorted(allow_hits.items()):
    print(("PASS" if cnt > 0 else "FAIL") + f"  (c) allowlist row is live: {rel} ({cnt} sites) — {ALLOW[rel]}")
if violations:
    print(f"FAIL  (c) std::regex spelled outside {OWNER} and the allowlist ({len(violations)} sites):")
    for v in violations[:40]:
        print(f"FAIL        {v}")
else:
    print(f"PASS  (c) no std::regex construction, match, iterator, result type or <regex> include outside {OWNER} and the allowlist")
PY
if ! grep -q '(c) population' "$TMP/static.txt"; then
    no "(c) the static scanner did not run to its verdict: $( head -c 300 "$TMP/static.txt" )"
fi
while IFS= read -r line; do
    case "$line" in
        PASS*) ok "${line#PASS  }" ;;
        FAIL*) no "${line#FAIL  }" ;;
        *)     no "(c) unexpected scanner output: $line" ;;
    esac
done <"$TMP/static.txt"

# ── (e) an --arch TO pattern refused only AFTER backreference substitution is refused by name ────────────────
# (e0) first, the template no capture can repair — `(\1` is unbalanced whatever lands in \1 — rejects the rules file
# at PARSE, with the line named, instead of being stored and skipped on every edge.
rc="$( capRun 20 "$TMP/e0.out" "$TMP/e0.err" "$FIX" --no-cache --arch="$TMP/arch_to_unbalanced.txt" )"
if [ "$rc" = 1 ] && grep -qF "TO path-regex '(\1' refused" "$TMP/e0.err" && grep -q 'rules file rejected' "$TMP/e0.err"; then
    ok "(e0) a TO template that compiles for no capture rejects the rules file at parse, naming the template"
else
    no "(e0) exit $rc — an unbalanced TO template was not rejected at parse: $( head -c 240 "$TMP/e0.err" )"
fi
rc="$( capRun 20 "$TMP/e.out" "$TMP/e.err" "$FIX" --no-cache --arch="$TMP/arch_subst.txt" )"
if [ "$rc" = 1 ]; then ok "(e) a TO pattern that becomes invalid after substitution refuses at exit 1"
else no "(e) exit $rc — a rule its own substitution broke was not refused (inert rules report exit 0 over edges they never judged)"; fi
if grep -qF "a{2,1}" "$TMP/e.err" && grep -q 'refused' "$TMP/e.err"; then ok "(e) the refusal quotes the substituted pattern a{2,1} and says it is refused"
else no "(e) stderr does not quote the substituted pattern: $( head -c 240 "$TMP/e.err" )"; fi
if grep -q '<arch ' "$TMP/e.out"; then no "(e) an <arch> answer was printed beside the refusal"; else ok "(e) no <arch> answer on stdout"; fi
# control: the same rule shape whose substitution stays valid (a{1,1}) is judged, not refused — the refusal is the
# substituted TEXT's, not the backreference's
rc="$( capRun 20 "$TMP/e2.out" "$TMP/e2.err" "$FIX" --no-cache --arch="$TMP/arch_subst_ok.txt" )"
if [ "$rc" != 1 ] && [ "$rc" != TIMEOUT ] && grep -q '<arch ' "$TMP/e2.out"; then ok "(e) control: a{1,\\1} substitutes to a valid a{1,1} and the rule is judged (exit $rc)"
else no "(e) control: exit $rc — $( head -c 200 "$TMP/e2.err" )"; fi

# ── (h) an undecided capture-typed #match? is reported BY CAUSE, naming the first site and the captured text ─────
CAPQ='((call_expression function: (identifier) @f arguments: (argument_list (string_literal) @s)) (#match? @f @s))'
HS="$TMP/cap_screen"; HC="$TMP/cap_compile"; HA="$TMP/cap_abandon"; mkdir -p "$HS" "$HC" "$HA" "$TMP/rules_cap"
printf 'int g(const char* s);\nint f(void)\n{\n    return g("(a+)+z");\n}\n' >"$HS/a.c"
printf 'int g(const char* s);\nint k(void) { return g("(b+)+z"); }\n' >"$HS/b.c"
printf 'int g(const char* s);\nint h(void) { return g("foo("); }\n' >"$HC/c.c"
printf 'int g(const char* s);\nint x(void) { return g("x"); }\n' >"$HA/x.c"
cat >"$TMP/rules_cap/cap.yml" <<'YML'
- id: rx-capture
  language: c
  severity: warn
  message: a capture-typed predicate
  query: |
    ((call_expression function: (identifier) @f arguments: (argument_list (string_literal) @s)) (#match? @f @s)) @hit
YML
causeArm(){                      # causeArm <label> <corpus> <needle cause> <needle text> <args…>
    local label="$1" corpus="$2" cause="$3" text="$4"; shift 4
    local rc; rc="$( capRun 20 "$TMP/h.out" "$TMP/h.err" "$corpus" --no-cache "$@" )"
    if [ "$rc" = 1 ]; then ok "(h) $label: refused at exit 1"; else no "(h) $label: exit $rc — $( head -c 200 "$TMP/h.err" )"; fi
    if grep -qF -- "$cause" "$TMP/h.err"; then ok "(h) $label: the refusal gives the cause ($cause)"
    else no "(h) $label: the refusal does not give the cause '$cause': $( head -c 260 "$TMP/h.err" )"; fi
    if grep -qF -- "$text" "$TMP/h.err"; then ok "(h) $label: the refusal names the captured text / site ($text)"
    else no "(h) $label: the refusal does not name '$text': $( head -c 260 "$TMP/h.err" )"; fi
    if [ "$cause" != "the regex engine abandoned" ] && grep -q 'abandoned the match' "$TMP/h.err"; then
        no "(h) $label: the refusal blames an abandoned match that never happened"
    else
        ok "(h) $label: no cause is claimed that did not happen"
    fi
    if grep -qE '<match |<lint' "$TMP/h.out"; then no "(h) $label: an answer element was printed beside the refusal"; else ok "(h) $label: no answer element on stdout"; fi
}
causeArm "screen-refused text"   "$HS" "captured text(s) the structural screen refused" "a.c:4, used the captured text '\"(a+)+z\"'" "--match=$CAPQ"
grep -qF '2 captured text(s) the structural screen refused' "$TMP/h.err" \
    && ok "(h) screen-refused text: both files' texts are counted, and the FIRST site named is the lowest file (a.c, not b.c)" \
    || no "(h) screen-refused text: count or first site wrong: $( head -c 260 "$TMP/h.err" )"
cp "$TMP/h.err" "$TMP/h1.err"
capRun 20 /dev/null "$TMP/h1b.err" "$HS" --no-cache "--match=$CAPQ" >/dev/null
if cmp -s "$TMP/h1.err" "$TMP/h1b.err"; then ok "(h) the by-cause refusal is byte-identical run to run"; else no "(h) the by-cause refusal differs run to run"; fi
causeArm "uncompilable text"     "$HC" "captured text(s) that do not compile" "c.c:2, used the captured text '\"foo(\"'" "--match=$CAPQ"
causeArm "--lint-rules, uncompilable text" "$HC" "captured text(s) that do not compile" "rx-capture" --lint-rules="$TMP/rules_cap"
if [ "$FAULTS" -eq 1 ]; then
    rc="$( RIPWIRE_FAULT_REGEX_MATCH=1 capRun 20 "$TMP/h.out" "$TMP/h.err" "$HA" --no-cache "--match=$CAPQ" )"
    if [ "$rc" = 1 ] && grep -qF "match(es) the regex engine abandoned" "$TMP/h.err" && grep -qF "x.c:2, ran the pattern '\"x\"'" "$TMP/h.err" \
       && grep -q 'abandoned the match' "$TMP/h.err" && ! grep -q 'captured text(s)' "$TMP/h.err"; then
        ok "(h) abandoned match: reported as abandoned, naming x.c:2 and the pattern, and no text cause"
    else
        no "(h) abandoned match: exit $rc — $( head -c 260 "$TMP/h.err" )"
    fi
else
    printf '  INFO  (h) fault switches compiled out (NDEBUG): the abandoned cause is proved on the plain-flavour leg\n'
fi

# ── (i) --arch decides deny first: an allow that cannot be finished matters only when a deny fires ─────────────────
printf 'allow path zz/.* -> (a|a)+z\ndeny path nomatch/.* -> .*\n' >"$TMP/arch_allow_nodeny.txt"
rc="$( capRun 20 "$TMP/i.out" "$TMP/i.err" "$FIX" --no-cache --arch="$TMP/arch_allow_nodeny.txt" )"
if [ "$rc" = 0 ] && grep -q '<arch ' "$TMP/i.out"; then
    ok "(i) no deny matches, so the edge is permitted without consulting the unfinishable allow (exit 0)"
else
    no "(i) exit $rc — an allow nobody needed refused a determinable answer: $( head -c 200 "$TMP/i.err" )"
fi
if [ "$LINKS_LIBCXX" -eq 1 ]; then
    printf 'allow path zz/.* -> (a|a)+z\nallow path zz/.* -> .*\ndeny path zz/.* -> .*\n' >"$TMP/arch_allow_later.txt"
    rc="$( capRun 30 "$TMP/i2.out" "$TMP/i2.err" "$FIX" --no-cache --arch="$TMP/arch_allow_later.txt" )"
    if [ "$rc" = 0 ] && grep -q '<arch ' "$TMP/i2.out"; then ok "(i) a deny fires, the first allow is abandoned, a later allow matches: permitted (exit 0)"
    else no "(i) later matching allow after an abandoned one: exit $rc — $( head -c 200 "$TMP/i2.err" )"; fi
    printf 'allow path zz/.* -> (a|a)+z\ndeny path zz/.* -> .*\n' >"$TMP/arch_allow_only.txt"
    rc="$( capRun 30 "$TMP/i3.out" "$TMP/i3.err" "$FIX" --no-cache --arch="$TMP/arch_allow_only.txt" )"
    if [ "$rc" = 1 ] && grep -qF "path-rule 'zz/.* -> (a|a)+z'" "$TMP/i3.err"; then ok "(i) a deny fires and the only allow is abandoned: refused, naming the ALLOW rule (exit 1)"
    else no "(i) deny fires, allow abandoned: exit $rc — $( head -c 200 "$TMP/i3.err" )"; fi
else
    printf '  INFO  (i) the two abandoned-allow cases need libc++'"'"'s match budget; the deny-first arm above is the portable half\n'
fi

# ── (f) the skill scanner: linear net-exfil agrees with its regex, bounded time, and undecided fails closed ───────
SK="$TMP/skills"; mkdir -p "$SK"
python3 - "$SK" <<'PY'
import random, re, sys
sk = sys.argv[1]
oracle = re.compile(r"(\b(curl|wget|nc)\b[^\r\n]*(\$[A-Za-z_][A-Za-z0-9_]*|base64))|((\$[A-Za-z_][A-Za-z0-9_]*|base64)[^\r\n]*\b(curl|wget|nc)\b)", re.ASCII)
tokens = ["curl", "wget", "nc", "ncx", "xnc", "curl_", "_wget", "$A", "$_b", "$1", "$", "$$x", "base64", "xbase64y", "base6",
          " ", " ", "|", "-", "\r", "a", "_", "0", "=", "'", '"', "$nc", "nc$", "base64nc", "c\rurl", "\t"]
rng = random.Random(20260916)
expected = []
for chunk in range(8):
    lines = []
    while len(lines) < 150:
        line = "".join(rng.choice(tokens) for _ in range(rng.randint(1, 9)))
        if "\n" in line or line.strip() in ("", "```") or line.lstrip(" \t").startswith(("```", "~~~")):
            continue
        lines.append(line)
    # every generated line sits inside one bash fence; line numbers start at 3 (heading, fence)
    with open(f"{sk}/chunk{chunk}.md", "w", newline="") as fh:
        fh.write("# probe\n```bash\n" + "\n".join(lines) + "\n```\n")
    for i, line in enumerate(lines):
        if oracle.search(line):
            expected.append(f"chunk{chunk}.md:{i + 3}")
with open(f"{sk}/expected.txt", "w") as fh:
    fh.write("\n".join(sorted(expected)) + "\n")
PY
: >"$SK/got.txt"
for f in "$SK"/chunk*.md; do
    "$BIN" --scan-skill="$f" 2>/dev/null | grep -o '<f p="[^"]*" rule="EXFILTRATE:net-exfil"' | sed -E 's#<f p="[^"]*/([^/"]*)" rule=.*#\1#' >>"$SK/got.txt"
done
sort -o "$SK/got.txt" "$SK/got.txt"
expectedCount="$( grep -c . "$SK/expected.txt" )"; gotCount="$( grep -c . "$SK/got.txt" )"
if [ "$expectedCount" -ge 100 ] && cmp -s "$SK/expected.txt" "$SK/got.txt"; then
    ok "(f1) net-exfil agrees with the regex oracle on all 1,200 generated fenced lines ($expectedCount positives)"
else
    no "(f1) net-exfil disagrees with the regex oracle: expected $expectedCount positives, got $gotCount — $( diff "$SK/expected.txt" "$SK/got.txt" | head -4 | tr '\n' ' ' )"
fi
python3 -c "import sys; sys.stdout.write('# probe\n\x60\x60\x60bash\n' + 'curl ' * 40000 + '\n\x60\x60\x60\n')" >"$SK/dos.md"
python3 -c "import sys; sys.stdout.write('# probe\n\x60\x60\x60bash\n' + 'curl ' * 40000 + '\$SECRET\n\x60\x60\x60\n')" >"$SK/dos_hit.md"
rc="$( capRun 20 "$TMP/f2.out" "$TMP/f2.err" --scan-skill="$SK/dos.md" )"
if [ "$rc" = 0 ]; then ok "(f2) a 200,000-byte fenced curl-run line scans clean within 20 s (the quadratic regex ran past 60 s)"
else no "(f2) the 200,000-byte curl-run line: exit $rc (TIMEOUT means the scan is still quadratic)"; fi
rc="$( capRun 20 "$TMP/f2h.out" "$TMP/f2h.err" --scan-skill="$SK/dos_hit.md" )"
if [ "$rc" = 2 ] && grep -q 'rule="EXFILTRATE:net-exfil"' "$TMP/f2h.out"; then ok "(f2) the same line ending in \$SECRET is still caught as net-exfil (exit 2), bounded"
else no "(f2) the long net-exfil line: exit $rc, finding $( grep -o 'rule="[^"]*"' "$TMP/f2h.out" | head -1 )"; fi
printf '# probe\n\nplain prose line\n' >"$SK/clean.md"
if [ "$FAULTS" -eq 1 ]; then
    rc="$( RIPWIRE_FAULT_REGEX_MATCH=1 capRun 20 "$TMP/f3.out" "$TMP/f3.err" --scan-skill="$SK/clean.md" )"
    if [ "$rc" = 2 ] && grep -q 'rule="SCAN-INCOMPLETE:regex-abandoned" sev="critical"' "$TMP/f3.out"; then
        ok "(f3) an abandoned match fails closed: CRITICAL SCAN-INCOMPLETE:regex-abandoned, exit 2"
    else
        no "(f3) an abandoned match in the skill scanner: exit $rc, $( head -c 200 "$TMP/f3.out" )"
    fi
    rc="$( capRun 20 "$TMP/f3c.out" "$TMP/f3c.err" --scan-skill="$SK/clean.md" )"
    if [ "$rc" = 0 ] && grep -q 'verdict="clean"' "$TMP/f3c.out"; then ok "(f3) control: the same file without the fault scans clean at exit 0"
    else no "(f3) control: exit $rc"; fi
else
    printf '  INFO  (f3) fault switches compiled out (NDEBUG): the fail-closed path is proved on the plain-flavour leg\n'
fi

# ── (g) the stack bound: a pattern too long or too deeply nested is refused by name, the limit itself still compiles ──
LIT2048="$( python3 -c "print('a' * 2048)" )"; LIT2049="$( python3 -c "print('a' * 2049)" )"
NEST64="$( python3 -c "print('(' * 64 + 'q' + ')' * 64)" )"; NEST65="$( python3 -c "print('(' * 65 + 'q' + ')' * 65)" )"
BIG="$( python3 -c "print('a' * 20000)" )"
rc="$( capRun 20 "$TMP/g1.out" "$TMP/g1.err" "$FIX" --no-cache --regex="$BIG" )"
if [ "$rc" = 1 ] && grep -q 'bytes and the limit is 2048' "$TMP/g1.err"; then ok "(g) a 20,000-byte --regex is refused by name at exit 1 (it died with SIGBUS in a 512 KiB grep worker)"
else no "(g) a 20,000-byte --regex: exit $rc — $( head -c 160 "$TMP/g1.err" )"; fi
rc="$( capRun 20 "$TMP/g2.out" "$TMP/g2.err" "$FIX" --no-cache --graph-query="file(all,\"$LIT2049\")" )"
if [ "$rc" = 1 ] && grep -q 'is 2049 bytes and the limit is 2048' "$TMP/g2.err"; then ok "(g) 2,049 bytes: refused, naming the size and the limit"
else no "(g) 2,049 bytes: exit $rc — $( head -c 160 "$TMP/g2.err" )"; fi
rc="$( capRun 20 "$TMP/g3.out" "$TMP/g3.err" "$FIX" --no-cache --graph-query="file(all,\"$LIT2048\")" )"
if [ "$rc" = 0 ] && grep -q '<query ' "$TMP/g3.out"; then ok "(g) exactly 2,048 bytes still compiles and answers"
else no "(g) 2,048 bytes: exit $rc — $( head -c 160 "$TMP/g3.err" )"; fi
rc="$( capRun 20 "$TMP/g4.out" "$TMP/g4.err" "$FIX" --no-cache --graph-query="file(all,\"$NEST65\")" )"
if [ "$rc" = 1 ] && grep -q 'groups nest 65 deep and the limit is 64' "$TMP/g4.err"; then ok "(g) groups nested 65 deep: refused, naming the depth and the limit"
else no "(g) 65 nested groups: exit $rc — $( head -c 160 "$TMP/g4.err" )"; fi
rc="$( capRun 20 "$TMP/g5.out" "$TMP/g5.err" "$FIX" --no-cache --graph-query="file(all,\"$NEST64\")" )"
if [ "$rc" = 0 ] && grep -q '<query ' "$TMP/g5.out"; then ok "(g) groups nested exactly 64 deep still compile and answer"
else no "(g) 64 nested groups: exit $rc — $( head -c 160 "$TMP/g5.err" )"; fi

# ── (d) file() matches the ROOT-RELATIVE path, so the checkout's directory name cannot select anything ─────────
mkTree(){
    mkdir -p "$1/src" "$1/lib"
    printf 'int one() { return 1; }\nint two() { return one(); }\n' >"$1/src/one.cpp"
    printf 'int three() { return 3; }\n' >"$1/lib/three.cpp"
}
mkTree "$TMP/clone_alpha/repo_alpha"
mkTree "$TMP/clone_beta/repo_beta"
countOf(){                       # countOf <cwd> <root spelling> <expr>
    ( cd "$1" && "$BIN" "$2" --no-cache --graph-query="$3" 2>/dev/null ) | grep -oE '<query [^>]*count="[0-9]+"' | grep -oE 'count="[0-9]+"' | grep -oE '[0-9]+'
}
for expr in 'file(all,"alpha")' 'file(all,"^src/")' 'file(all,"three")'; do
    ca="$( countOf "$TMP" "$TMP/clone_alpha/repo_alpha" "$expr" )"
    cb="$( countOf "$TMP" "$TMP/clone_beta/repo_beta" "$expr" )"
    cr="$( countOf "$TMP/clone_alpha" "repo_alpha" "$expr" )"
    cd_="$( countOf "$TMP/clone_alpha" "./repo_alpha/" "$expr" )"
    if [ -n "$ca" ] && [ "$ca" = "$cb" ] && [ "$ca" = "$cr" ] && [ "$ca" = "$cd_" ]; then
        ok "(d) $expr: count=$ca in both clones and under absolute, relative and ./-with-slash root spellings"
    else
        no "(d) $expr: counts differ by checkout — alpha abs '$ca', beta abs '$cb', alpha rel '$cr', alpha ./rel/ '$cd_'"
    fi
done
[ "$( countOf "$TMP" "$TMP/clone_alpha/repo_alpha" 'file(all,"alpha")' )" = "0" ] \
    && ok "(d) file(all,\"alpha\") selects nothing: no root-relative path contains the clone's directory name" \
    || no "(d) file(all,\"alpha\") selected symbols in repo_alpha — the pattern matched the checkout directory"
[ "$( countOf "$TMP" "$TMP/clone_alpha/repo_alpha" 'file(all,"^src/")' )" = "2" ] \
    && ok "(d) an anchored ^src/ selects the two src/ symbols under an ABSOLUTE root" \
    || no "(d) ^src/ did not select exactly the two src/ symbols under an absolute root"
( cd "$TMP" && "$BIN" "$TMP/clone_alpha/repo_alpha" --no-cache --graph-query='file(all,"one")' 2>/dev/null ) >"$TMP/rows.xml"
rowsTotal="$( grep -o '<s [^>]*p="[^"]*"' "$TMP/rows.xml" | wc -l | tr -d ' ' )"
rowsOff="$( grep -o '<s [^>]*p="[^"]*"' "$TMP/rows.xml" | grep -vc 'p="src/one\.cpp:' )"
if [ "$rowsTotal" -gt 0 ] && [ "$rowsOff" = "0" ]; then
    ok "(d) every row file(all,\"one\") selects prints p=\"src/one.cpp:…\" — the path matched is the path shown ($rowsTotal rows)"
else
    no "(d) file(all,\"one\") rows: $rowsTotal total, $rowsOff not under src/one.cpp"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
