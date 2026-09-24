#!/usr/bin/env bash
# regexcheck.sh — soundness gate for the Russ-Cox regex→trigram prefilter (--regex).
# The whole point of the prefilter is to be a SOUND over-approximation: it may open extra
# files, but it must NEVER drop a file that genuinely matches. So for a battery of patterns
# (a literal, an alternation, a char-class, an anchored ^, a spanning Foo.*Bar, and a
# no-trigram .*) we assert THREE things:
#   (S) prefiltered output == full-scan output   (--regex=PAT  vs  --regex=PAT --no-prefilter)
#       — the full scan opens every file, so equality proves the prefilter dropped no match.
#   (O) the file set ripwire reports ⊇ the file set an INDEPENDENT `grep -lE` finds
#       — a second, external oracle that the verifier itself can't bias.
#   (D) output is byte-identical run-to-run (determinism contract).
# Plus a NARROWING check: a pattern keyed on a token unique to one file must report fewer
# candidate files than `.*` (all files) — proving the prefilter actually excludes files
# (otherwise "sound" would be trivially satisfied by always scanning everything).
#
# Does NOT edit test/regression.sh.  Usage:
#   RIPWIRE_BIN=build/ripwire bash test/regexcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/regexcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/regexfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/regexfix dir — fixture missing"; exit 2; }
cd "$ROOT"   # repo-relative paths in the XML, so the oracle paths line up

echo "regexcheck: BIN=$BIN  CORPUS=test/regexfix"

# The required-by-the-gate battery: one of each shape, plus extra adjacency/escape stressors.
#   literal · alternation · char-class · anchored ^ · spanning Foo.*Bar · no-trigram .*
PATS=(
  'compute'                # a plain literal (>=3 chars → real trigram constraint)
  'open|close'             # alternation of two literals
  '[A-Z]\w+'               # a char class + \w (CamelCase identifiers)
  '^int '                  # an anchored line start
  'Foo.*Bar'               # a SPANNING pattern — the unsound-seam trap (Foo and Bar non-adjacent)
  '.*'                     # NO usable trigram ⇒ must fall back to scanning ALL files
  'zylophoneXyzzy'         # a rare literal unique to one file (narrowing probe)
  'Foo .* Bar'             # spanning with literal spaces around .*
  'a.*b.*c'                # multiple gaps
  '(Foo|Quux)'             # grouped alternation
  'Wid[g]et'               # a single-element char class inside a literal run
  'comp.te'                # a '.' wildcard inside a literal
  'open\('                 # an escaped metacharacter (literal paren)
  # 2026-09-23: escapes whose TAIL the engine reads. The analyser took `\x65` for the letters x,6,5 and
  # required THAT trigram of every file, so a pattern spelling one byte by number dropped every file that
  # matched, at capped="0". One in a literal run, one in a class, one as \uHHHH, and one as the branch of
  # an alternation that is a file's ONLY match (arm (E) below pins that shape by name).
  'op\x65n\('              # \xHH inside a literal run (\x65 = e)
  '[\x6f]pen'              # \xHH inside a char class (\x6f = o)
  'comp\u0075te'           # \uHHHH (\u0075 = u): four digits, same tail rule
  'zylophoneXyzzy|\x63ompute'   # the escaped branch is the only match in two fixture files
  # 2026-09-23 (F2): a non-capturing group CONSUMES its content -- it is an ordinary group, not a
  # zero-width assertion. Reading (?:...) as epsilon let a seam trigram span across it, so a pattern
  # whose only occurrence of a byte is inside the group dropped every file. beta.py's def open(self):
  # is this arm's only match, mid-literal so the seam actually forms (unlike a group at branch end).
  'op(?:e)n\('             # (?:...) mid-literal: must consume 'e', not vanish
)

# ── (S) soundness + (D) determinism, per pattern ──────────────────────────────────────────────
for p in "${PATS[@]}"; do
    "$BIN" "$CORPUS" --regex="$p" --no-cache               >"$TMP/pf"  2>/dev/null
    "$BIN" "$CORPUS" --regex="$p" --no-cache               >"$TMP/pf2" 2>/dev/null   # determinism: run twice
    "$BIN" "$CORPUS" --regex="$p" --no-prefilter --no-cache >"$TMP/fs" 2>/dev/null   # full-scan oracle

    # presence guard: a refused pattern writes no <grep> element to EITHER file, and empty == empty would
    # read as agreement (CONTRIBUTING §2 shape 3). The oracle must have answered before it is compared to.
    if ! grep -q '<grep ' "$TMP/fs"; then
        no "$(printf '%-12s' "$p") full-scan oracle gave no <grep> answer (refused? rc/stderr not captured here) — nothing to compare"
        continue
    fi

    det="ok"; diff -q "$TMP/pf" "$TMP/pf2" >/dev/null || det="BAD"
    snd="ok"; diff -q "$TMP/pf" "$TMP/fs"  >/dev/null || snd="BAD"

    if [ "$snd" = ok ] && [ "$det" = ok ]; then
        ok "$(printf '%-12s' "$p") prefiltered==full-scan + deterministic  $(grep -o 'files="[0-9]*" hits="[0-9]*"' "$TMP/pf")"
    else
        [ "$snd" = ok ] || { no "$(printf '%-12s' "$p") prefiltered != full-scan (DROPPED A MATCH)"; diff "$TMP/fs" "$TMP/pf" | head -4; }
        [ "$det" = ok ] || no "$(printf '%-12s' "$p") non-deterministic (run-to-run differs)"
    fi
done

# The root-relative <f p="…"> set of an answer, past the legend comment (whose prose spells that shape).
fileSetOf(){ python3 -c '
import re, sys
xml = sys.stdin.read().split( "-->", 1 )[ -1 ]
for m in re.finditer( r"<f p=\"([^\"]*)\"", xml ):
    print( m.group( 1 ) )
' | sort -u; }

# ── (E) an alternation whose ESCAPED branch is a file's only match reaches that file (2026-09-23) ──
# `zylophoneXyzzy|\x63ompute`: the analyser read `\x63` as the letters x, 6, 3 and ORed the trigram "x63" in,
# so a file the first branch did not admit was skipped — beta.py and gamma.md hold `compute` and no
# `zylophoneXyzzy`, and both vanished from an answer that still said capped="0". Three assertions: the fixture
# HAS such files (presence guard), the prefiltered answer lists every one of them, and the prefiltered file
# count equals full-scan's and exceeds the first branch's alone (the escaped branch admitted files, so a
# trivial ALL is not what passed).
esc='zylophoneXyzzy|\x63ompute'
onlyEsc="$( grep -L 'zylophoneXyzzy' "$CORPUS"/* | xargs grep -l 'compute' | sed "s|^$CORPUS/||" | sort -u )"
if [ -n "$onlyEsc" ]; then
    ok "(E) presence: $( printf '%s\n' "$onlyEsc" | wc -l | tr -d ' ' ) fixture file(s) hold 'compute' and no 'zylophoneXyzzy': $( printf '%s' "$onlyEsc" | tr '\n' ' ' )"
else
    no "(E) presence: no fixture file holds 'compute' without 'zylophoneXyzzy' — the arm would have nothing to drop"
fi
"$BIN" "$CORPUS" --regex="$esc" --grep-in=any --no-cache >"$TMP/esc.pf" 2>/dev/null
"$BIN" "$CORPUS" --regex="$esc" --grep-in=any --no-prefilter --no-cache >"$TMP/esc.fs" 2>/dev/null
escSet="$( fileSetOf <"$TMP/esc.pf" )"
missE=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    printf '%s\n' "$escSet" | grep -qxF "$f" || { missE=1; echo "      $f holds 'compute' but the prefiltered /$esc/ answer dropped it"; }
done <<< "$onlyEsc"
pfF="$( grep -o ' files="[0-9]*"' "$TMP/esc.pf" | head -1 | grep -o '[0-9]*' )"
fsF="$( grep -o ' files="[0-9]*"' "$TMP/esc.fs" | head -1 | grep -o '[0-9]*' )"
oneF="$( "$BIN" "$CORPUS" --regex='zylophoneXyzzy' --grep-in=any --no-cache 2>/dev/null | grep -o ' files="[0-9]*"' | head -1 | grep -o '[0-9]*' )"
cappedE="$( grep -o ' capped="[01]"' "$TMP/esc.pf" | head -1 | grep -o '[01]' )"
if [ "$missE" -eq 0 ] && [ -n "$pfF" ] && [ -n "$fsF" ] && [ "$pfF" -eq "$fsF" ] && [ "$fsF" -gt "${oneF:-0}" ]; then
    ok "(E) /$esc/ prefiltered files=$pfF == full-scan files=$fsF > first-branch-only files=$oneF, every escaped-only file listed (capped=\"${cappedE:-?}\")"
else
    no "(E) /$esc/ prefiltered files=${pfF:-none} full-scan files=${fsF:-none} first-branch-only files=${oneF:-none} capped=\"${cappedE:-?}\" — the escaped branch's files were dropped from a complete-looking answer"
fi

# ── (O2) an escape-aware external oracle: `grep -E` cannot spell \xHH, ripgrep can ──────────────
# ripgrep is a suite prerequisite (CONTRIBUTING §1), so its absence is a FAIL, never a silent skip.
if command -v rg >/dev/null 2>&1; then
    for p in 'op\x65n\(' '[\x6f]pen' 'zylophoneXyzzy|\x63ompute'; do
        cx="$( "$BIN" "$CORPUS" --regex="$p" --grep-in=any --no-cache 2>/dev/null | fileSetOf )"
        gp="$( rg -l -- "$p" "$CORPUS" 2>/dev/null | sed "s|^$CORPUS/||" | sort -u )"
        if [ -z "$gp" ]; then no "(O2) rg found no file for /$p/ — the oracle has nothing to compare (fixture drift?)"; continue; fi
        miss=0
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            printf '%s\n' "$cx" | grep -qxF "$f" || { miss=1; echo "      rg matched $f but ripwire dropped it"; }
        done <<< "$gp"
        if [ "$miss" -eq 0 ]; then ok "(O2) oracle ⊇ rg   $(printf '%-26s' "$p") ($( printf '%s\n' "$gp" | wc -l | tr -d ' ' ) files)"; else no "(O2) oracle dropped an rg-matched file for /$p/"; fi
    done
else
    no "(O2) ripgrep is not on PATH — the escape-aware oracle cannot run (CONTRIBUTING lists rg as a suite prerequisite)"
fi

# ── (F1) [\x7e-\x7f] class range must not HANG — regression gate for the range-loop overflow ──────
# parseClass enumerated a range with `for( char ch = lo; ch <= hi; ++ch )`. AppleClang/Apple's arm64 and
# x86_64 ABIs both make plain `char` signed, so CHAR_MAX == 0x7f; when `hi == 0x7f`, `ch <= hi` is always
# true and the loop never terminates (RSS grows without bound). `\x7f`/`\u007f` are portable escapes
# (regexguard.h vouches for them), so an ordinary shell pattern reaches this. Alarm-guarded: a process
# still running past a short alarm is a HANG, which is a FAIL here, never a slow PASS.
f1pat='[\x7e-\x7f]'
perl -e 'alarm 20; exec @ARGV' "$BIN" "$CORPUS" --regex="$f1pat" --grep-in=any --no-cache \
    >"$TMP/f1.pf" 2>"$TMP/f1.pf.err"; f1rc=$?
perl -e 'alarm 20; exec @ARGV' "$BIN" "$CORPUS" --regex="$f1pat" --grep-in=any --no-prefilter --no-cache \
    >"$TMP/f1.fs" 2>"$TMP/f1.fs.err"; f1fsrc=$?
if [ "$f1rc" -eq 142 ] || [ "$f1fsrc" -eq 142 ]; then
    no "(F1) /$f1pat/ hung past a 20s alarm (pf rc=$f1rc, fs rc=$f1fsrc) — parseClass range-loop overflow"
elif [ "$f1rc" -ne 0 ] || [ "$f1fsrc" -ne 0 ]; then
    no "(F1) /$f1pat/ non-zero exit (pf rc=$f1rc, fs rc=$f1fsrc) — expected both to search cleanly"
elif ! diff -q "$TMP/f1.pf" "$TMP/f1.fs" >/dev/null; then
    no "(F1) /$f1pat/ prefiltered != full-scan (DROPPED A MATCH)"
else
    ok "(F1) /$f1pat/ no hang, prefiltered==full-scan  $(grep -o 'files="[0-9]*" hits="[0-9]*"' "$TMP/f1.pf")"
fi

# ── (F2) (?:...) against the real repo — a group that actually has files to drop ───────────────────
# `std::(?:string)&` is the reviewer's own reproduction: a non-capturing group read as epsilon required
# the seam trigram "::&" of every file, so every real `std::string&` occurrence in this repo's own
# sources (files="138" against a full scan) vanished from the answer at capped="0". Run against src/
# itself (an established pattern here — see regexrefusecheck.sh, grepanchorcheck.sh) so this arm cannot
# pass by having nothing to compare.
f2pat='std::(?:string)&'
"$BIN" "$ROOT/src" --regex="$f2pat" --grep-in=any --no-cache --limit=100000 >"$TMP/f2.pf" 2>/dev/null
"$BIN" "$ROOT/src" --regex="$f2pat" --grep-in=any --no-prefilter --no-cache --limit=100000 >"$TMP/f2.fs" 2>/dev/null
f2pfSet="$( fileSetOf <"$TMP/f2.pf" )"
f2fsSet="$( fileSetOf <"$TMP/f2.fs" )"
f2fsF="$( grep -o ' files="[0-9]*"' "$TMP/f2.fs" | head -1 | grep -o '[0-9]*' )"
if [ -z "$f2fsF" ] || [ "$f2fsF" -eq 0 ]; then
    no "(F2) /$f2pat/ full-scan oracle found 0 files under src/ — nothing to compare (repo drift?)"
elif [ "$f2pfSet" = "$f2fsSet" ]; then
    ok "(F2) /$f2pat/ prefiltered==full-scan under src/ (files=$f2fsF) — (?:...) is no longer read as epsilon"
else
    no "(F2) /$f2pat/ prefiltered != full-scan under src/ (DROPPED A MATCH) — (?:...) still invents a seam"
fi

# ── (O) independent grep oracle: ripwire's matched-FILE set must be a SUPERSET of grep -lE's ──
# (BRE-safe subset of the battery; uses grep -E so the pattern syntax matches.)
for p in 'compute' 'Widget' 'open|close' '[A-Z][a-z]+' 'Foo.*Bar' 'zylophoneXyzzy' '(open|close)'; do
    # G1 (2026-08-15): a matched file's path now lives ONLY on the wrapping <f p="…"> (no ":LINE" suffix —
    # that moved to the nested <hit l="…">), so the old "strip at the first colon" sed left a trailing
    # unstripped quote on every path (no colon to truncate at) and every comparison below false-missed.
    # Extract <f p="…"> distinctly, past the legend comment (whose own prose illustrates that exact shape).
    # R-H span tiers (2026-08-19): grep-in=any — this arm's oracle is `grep -rlE`, i.e. every file the
    # regex matches ANYWHERE, so it must be compared against the un-tiered listing. The tiered default is a
    # deliberate SUBSET (comment/string rows held back and disclosed), which grepscancheck (7b) pins.
    cx="$( "$BIN" "$CORPUS" --regex="$p" --grep-in=any --no-cache 2>/dev/null | python3 -c '
import re, sys
xml = sys.stdin.read().split( "-->", 1 )[ -1 ]
for m in re.finditer( r"<f p=\"([^\"]*)\"", xml ):
    print( m.group( 1 ) )
' | sort -u )"
    # G1: $CORPUS is an absolute single-root, so ripwire's p= is now root-relative to it — strip the same
    # prefix from the independent grep oracle's paths so both sides compare the same spelling.
    gp="$( grep -rlE -- "$p" "$CORPUS" 2>/dev/null | sed "s|^$CORPUS/||" | sort -u )"
    miss=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        printf '%s\n' "$cx" | grep -qxF "$f" || { miss=1; echo "      grep matched $f but ripwire dropped it"; }
    done <<< "$gp"
    if [ "$miss" -eq 0 ]; then ok "oracle ⊇ grep   $(printf '%-14s' "$p")"; else no "oracle dropped a grep-matched file for /$p/"; fi
done

# ── NARROWING: the prefilter must EXCLUDE files (else soundness is trivial). A token unique to one
#    file ⇒ fewer candidate files than '.*' (which has no trigram constraint ⇒ all files). ─────────
allF="$(  "$BIN" "$CORPUS" --regex='.*'            --no-cache 2>/dev/null | grep -o 'files="[0-9]*"' | grep -o '[0-9]*' )"
rareF="$( "$BIN" "$CORPUS" --regex='zylophoneXyzzy' --no-cache 2>/dev/null | grep -o 'files="[0-9]*"' | grep -o '[0-9]*' )"
if [ -n "$allF" ] && [ -n "$rareF" ] && [ "$rareF" -lt "$allF" ]; then
    ok "narrowing (rare pattern files=$rareF < all files=$allF — prefilter excludes files)"
else
    no "narrowing FAILED (rare=$rareF, all=$allF — prefilter is scanning everything)"
fi

# ── no-trigram FALLBACK: '.*' must behave EXACTLY like the full scan (already covered by (S) above,
#    asserted explicitly here for clarity — the correctness-over-speed fallback). ─────────────────
"$BIN" "$CORPUS" --regex='.*' --no-cache               >"$TMP/dotpf" 2>/dev/null
"$BIN" "$CORPUS" --regex='.*' --no-prefilter --no-cache >"$TMP/dotfs" 2>/dev/null
diff -q "$TMP/dotpf" "$TMP/dotfs" >/dev/null \
    && ok "no-trigram fallback ('.*' prefiltered == full-scan == every file)" \
    || no "no-trigram fallback broken ('.*' differs from full scan)"

# ── malformed vs exotic: §P0.4 changed this contract. A regex std::regex REJECTS must REFUSE —
# exit 1, a diagnostic on stderr, and NO hits= element (a silent hits="0" was the false-zero bug).
# A pattern that merely LOOKS exotic but compiles must still search at exit 0. Either way, never a
# crash: exit codes above 1 (signals, aborts) fail both arms.
for p in '(' '[' 'a{2,' '\Q\E'; do
    err="$( "$BIN" "$CORPUS" --regex="$p" --no-cache 2>&1 >"$TMP/refuse.out" )"; rc=$?
    if [ "$rc" -eq 1 ] && [ -n "$err" ] && ! grep -q '<grep' "$TMP/refuse.out"; then
        ok "malformed pattern /$p/ refuses (exit 1 + stderr, no hits element)"
    else
        no "malformed pattern /$p/: want exit 1 + stderr + no hits element, got exit $rc (stderr ${#err}B)"
    fi
done
for p in '(?:foo)' '[^x]+'; do
    "$BIN" "$CORPUS" --regex="$p" --no-cache >/dev/null 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && ok "exotic-but-valid pattern /$p/ still searches (exit 0)" \
                    || no "exotic-but-valid pattern /$p/ no longer searches (exit $rc)"
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
