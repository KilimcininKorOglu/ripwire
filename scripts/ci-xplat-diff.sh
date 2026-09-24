#!/usr/bin/env bash
# ci-xplat-diff.sh — Windows vs Linux: the same verbs on the same fixture must print the same bytes.
#
# Reads two directories written by scripts/ci-xplat-outputs.sh (Linux: the ubuntu-24.04 Release clang leg; Windows:
# the packaged, UNZIPPED windows-x64 release binary) and applies exactly these rules — nothing is normalised away:
#   R1 identity   every output the Linux side wrote (*.xml, *.rc, *.json, *.txt; *.err is platform notes and is
#                 skipped) exists on the Windows side and is byte-identical. No path-separator, line-ending or
#                 case folding is applied: '/' is the only separator either platform may print, and "\n" the only
#                 line ending (stdout is binary on Windows, os::init_process).
#   R2 separator  the Windows-only bslash-map.xml (root typed as test\fixture) is byte-identical to Linux's
#                 repo-map.xml: a root typed with '\' enters the program as '/' (os::normalize_path_arg), and root=
#                 and every p= print it that way.
#   R3 CRLF       on EACH side, crlf-{map,for,callers,impact} equal tree-{map,for,callers,impact}: CRLF line endings
#                 change no symbol, rank, edge, line number or count. crlf-expand is exempt from R3 on purpose —
#                 --expand prints the source bytes, so its CDATA carries the CRs and its reason=/est_tokens= count
#                 them — but it is still under R1, so both platforms must print the SAME CRLF bytes.
# Usage: bash scripts/ci-xplat-diff.sh <linux outputs dir> <windows outputs dir>
set -u
LIN="${1:?usage: ci-xplat-diff.sh <linux dir> <windows dir>}"
WIN="${2:?usage: ci-xplat-diff.sh <linux dir> <windows dir>}"
fail=0
# verdict PASS|FAIL MESSAGE — a FAIL marks both the run and the rule being checked
verdict() { printf '  %s  %s\n' "$1" "$2"; if [ "$1" = FAIL ]; then fail=1; rulefail=1; fi; }
show() { # first differing bytes, readable
    diff <( tr '>' '\n' <"$1" ) <( tr '>' '\n' <"$2" ) | head -12 | sed 's/^/        /'
}

n=0; rulefail=0
for f in "$LIN"/*.xml "$LIN"/*.rc "$LIN"/*.json "$LIN"/*.txt; do
    [ -e "$f" ] || continue
    b="${f##*/}"; n=$(( n + 1 ))
    if [ ! -e "$WIN/$b" ]; then
        verdict FAIL "R1 $b: written on Linux, missing on Windows"
    elif cmp -s "$f" "$WIN/$b"; then
        :
    else
        verdict FAIL "R1 $b differs (Linux $( wc -c <"$f" | tr -d ' ' ) B, Windows $( wc -c <"$WIN/$b" | tr -d ' ' ) B):"; show "$f" "$WIN/$b"
    fi
done
# 5 verbs x 3 copies + their 15 rc files + 3 MCP files. A short list means an output step silently wrote nothing.
if [ "$n" -lt 33 ]; then
    verdict FAIL "R1 only $n Linux outputs found in $LIN (expected >= 33): nothing meaningful was compared"
else
    [ "$rulefail" -eq 0 ] && verdict PASS "R1 all $n Linux outputs are byte-identical on Windows"
fi

if [ ! -e "$WIN/bslash-map.xml" ]; then
    verdict FAIL "R2 Windows side has no bslash-map.xml (run ci-xplat-outputs.sh with --windows)"
elif cmp -s "$LIN/repo-map.xml" "$WIN/bslash-map.xml" && [ "$( cat "$WIN/bslash-map.rc" 2>/dev/null )" = 0 ]; then
    verdict PASS "R2 a root typed test\\fixture on Windows maps byte-identically to test/fixture on Linux"
else
    verdict FAIL "R2 bslash-map.xml (rc=$( cat "$WIN/bslash-map.rc" 2>/dev/null )) differs from Linux repo-map.xml:"; show "$LIN/repo-map.xml" "$WIN/bslash-map.xml"
fi

rulefail=0
for side in "$LIN" "$WIN"; do
    for v in map for callers impact; do
        if cmp -s "$side/tree-$v.xml" "$side/crlf-$v.xml"; then
            :
        else
            verdict FAIL "R3 ${side##*/}: crlf-$v.xml differs from tree-$v.xml — CRLF line endings changed a structural answer:"; show "$side/tree-$v.xml" "$side/crlf-$v.xml"
        fi
    done
done
[ "$rulefail" -eq 0 ] && verdict PASS "R3 CRLF copies give the same map/--for/--callers/--impact as LF on both sides (crlf-expand under R1 only)"

if [ "$fail" -ne 0 ]; then
    echo "SOME CHECKS FAILED"; exit 1
fi
echo "ALL PASS"
