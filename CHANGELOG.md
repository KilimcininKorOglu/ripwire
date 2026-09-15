# Changelog

All notable changes to ripwire are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Everything here is pre-1.0: the flag surface may still change. When a flag is superseded it is
deprecated with a stderr pointer at its replacement and kept working; removals wait for a major
version. A `v0.1.0` tag exists (2026-08-02) but its GitHub Release carries no binaries; **v0.2.0 is
the first release with published, SHA-256-checked archives**, and it contains everything below.

Every measured number in this file names its corpus and method. Numbers without a stated method are
not published here — see `docs/EVALS.md` for the instruments behind the headline figures.

---

## [Unreleased]

### Fixed — the suite's `skip=` count stopped depending on where the checkout lives

`test/pargates.py` decided whether a gate had SKIPPED — ran, but proved nothing — by looking for the word
SKIP in the first 400 characters of its transcript. Characters, not bytes: the harness decodes the capture
and slices the decoded string, and this suite prints box-drawing rules and em dashes liberally, so every
offset quoted against that threshold has to be in code points too. That is a ruler laid over a document whose origin moves.
Gates open with a banner naming their own absolute paths (`<name>: BIN=<abs>  ROOT=<abs>`) — 515 of the
628 transcripts captured from one full suite run carry the crawl root in their first line — so for those
the window's CONTENTS are a function of the checkout's pathname, and every offset after the banner travels
with it. Measured on `test/w3fixlegendcheck.sh`, whose transcript is byte-identical after line 1: the
banner is 217 B from an 87-character worktree root and 67 B from a 12-character one — a 150 B shift from a
75-character rename, about 2 B per character because the root is spelled twice. The same commit, the same
binary and byte-identical gate output therefore reported `skip=2` from a 137-character checkout and
`skip=3` from a 38-character one, differing only in how one honest arm-level SKIP fell relative to byte
400. That observation belongs to a named tree: commit `3c191bdf` on a feature branch, where
`test/w3fixlegendcheck.sh`'s N=3 partition arm ties (`TIE 0.0928 vs 0.093`) and honestly skips near the
top of its transcript. Re-run on that tree from two checkouts with the same binary and arm output
byte-identical after line 1, the tie row starts at character 302 from a 38-character root and 402 from a
138-character one — it straddles the window by two characters. (In bytes those rows are at 308 and 408; the
six is the box-drawing rule and em dash above them, and the window is in characters.) On the merge base that arm does not tie, so the
symptom cannot be shown there at any path length, and an absolute offset is a property of a tree rather
than of a gate. The suite's summary line is what a contributor reads before every push, so a count that moves with
the pathname is not evidence.

The exposure was not one gate's, and the dangerous direction was the opposite one. Measured over all 628
gate transcripts of one full suite run on this repository: 24 gates print a skip MARKER downstream of at
least one absolute-root mention — 28 by the bare substring the old rule actually looked for, the four
extra being gates that only narrate the word — so their classification travelled with the checkout. The nearest was a
REAL standing skip — `test/editchecknotecheck.sh` declares its skip at character 145 — the same figure in
bytes, since everything before it there is ASCII — and 255 more characters of checkout path (a 342-character
root, ordinary for a nested worktree or a CI runner) push that declaration out of the window, at which point a gate that proved nothing is counted as a pass. Which gates
are in range is a property of the machine rather than of the commit, so a wider window was never the
answer.

The rule is now written down instead of measured in bytes: **a gate that proves nothing says so before it
claims anything.** The first verdict marker in the transcript decides — a SKIP ahead of every PASS and
FAIL marker is a whole-gate skip, while a SKIP that follows one is an arm-level skip inside a gate that
did prove something, and that gate is a pass. It reads verdict markers rather than a bare substring,
because five gates narrate the word SKIPPED in prose and prove plenty. This is what the tree already did
on purpose — `test/namingcalibrationcheck.sh` runs its live arm first so its skip banner precedes its
instrument arm's pass rows, and `test/argvdiffcheck.sh`'s skip is its opening line — so the classification
is unchanged where it was already right: replayed over those same 628 transcripts, the new rule and the
old one disagree on ZERO gates, and a full suite run reports the same three environmental skips as before.

The same failure family turned up one level down, inside the fix, and the review caught it. The rule
counts a FAIL as a verdict, but the shared failure-marker expression was compiled without `re.M` and the
classifier matches it against a WHOLE transcript — so `^` bound only to the start of the string, every
anchored alternative in it was dead below line 1, and the only one that could still fire was the single
unanchored one. A gate that printed a FAIL row, then a SKIP row, and exited 0 therefore read as having
proved nothing, when it had claimed a verdict before it skipped. It is now compiled with `re.M`, which is a
no-op for the other caller: that one searches a line at a time, and a single line has no newline for `^` to
find. The arm that pins it, (D2), deliberately does NOT print the one unanchored alternative — a probe
carrying it would be matched by accident and the arm would pass while asserting nothing, which is the
difference between a test and a demonstration.

One direction is newly open and is disclosed rather than left to be discovered. A whole-gate skip that
prints any PASS row BEFORE its skip marker now counts as a pass, because in a transcript it is
indistinguishable from a gate that proved an arm and then skipped one. No gate in the suite does this
today — the replay above is the evidence — and it is the convention both sanctioned skips already follow,
but nothing enforces it: a gate that grew a fixture-present PASS row above its skip banner would go from
skip to pass silently. Enforcing it needs a static sweep of every gate's skip path, which belongs beside
`test/gateexitcheck.sh` arm (D); that arm flags an `exit 0` only where a skip word and `ALL PASS` appear
within three lines of each other, so it does not police marker order and never did.

`test/skipclassifycheck.sh` is the gate, and it drives the real `test/pargates.py` rather than a
reimplementation of it: one probe gate, byte-identical, classified from two corpus roots about 130
characters apart, after a presence guard proves that the same probe's skip row really does land on
opposite sides of the old boundary — without that contrast the arm would pass against a classifier that
never read the output at all. It reds on the byte-window classifier at four arms and greens on the rule.
The gate side of the same contract is `test/gateexitcheck.sh` arm (D).

### Fixed — a relative command with no anchor, and the roots that never declared themselves

A second review of the three `--situ` entries below found twelve defects — counted one per
independently described correction below, which is four surfaces that spelled a path or a command
relative to a root they never declared, one in the shared path relativizer, three in the new
lexical-siblings block and four disclosure readings dropped when sentences became attributes (4 + 1 + 3
+ 4) — every one of them a document that could not be resolved by the reader holding it, and all twelve
are fixed here. The two byte ratchets named at the end moved with the fixes and are not counted among
them: a pin is not a defect. A third review, of this entry's own fixes rather than of the entries below
it, found two more — the filesystem root in that same relativizer, and a quadratic scan in the new
lexical-siblings block — and both are fixed here too. A fourth review found a FIFTEENTH in shipped
output: a `run=` command did not shell-quote its path. Separately, this lane's own new cap left two
published counts stale (README's cap total and `docs/TUNING.md`); both were republished by their
generators rather than edited, and they are drift this entry caused rather than a sixteenth defect.

A run= IS A COMMAND, AND ITS PATH COMES FROM THE CORPUS. `testmap.h`'s `spell()` concatenated the
runner verb and the path, so a repository containing the legal filename `test/check;touch PWNED.sh`
made the tool emit `run="bash test/check;touch PWNED.sh"` — a command this tool hands an agent to
paste, which runs `touch PWNED.sh` in the reader's shell (CWE-78, external reachability). The path is
now always one shell argument. It is quoted only when it is not provably safe, and that is measured
rather than preferred: `shSingleQuote` always wraps, so quoting unconditionally would move the `run=`
bytes of every test row in eight emitters — 13 literal command assertions across 7 gates,
`docs/COMMANDS.md`, 15 committed capture snapshots, README and the `printf_parity` pins. Every path
`git ls-files` tracks here is inside the safe allowlist (`[A-Za-z0-9._/-]`, never a leading `-`, which
a shell reads as a flag), measured at 0 outside it, so the conditional form is byte-identical on every
real corpus while a hostile name is still quoted — `printffmtparitycheck` needed no re-pin. The
predicate is an allowlist, so an unenumerated byte is quoted by default. `test/runhintcheck.sh` arm (5)
EXECUTES the emitted command in a scratch corpus and asserts the payload did not fire, with the
unquoted spelling as its control. Red before the fix: the emitted command created the sentinel file.

AND QUOTING WAS NOT SUFFICIENT — the same trust boundary, one layer in. A root-level
`-cimport os;open("PWNED","w")#_test.py` passes `isTestPath`, keeps its leading dash, survives quoting
intact, and then `python3` reads `-c` as "execute this code": the path reaches the INTERPRETER as an
option rather than the shell as code. Measured, both directions, over the whole population of verbs
`runnerVerb` can emit (exactly two — `.sh`→`bash`, `.py`→`python3`): `python3 '<path>'` exited 0 and
created the payload file, `python3 -- '<path>'` exited the file's own 7 and did nothing, and
`bash -- '<path>'` likewise. `bash` did not reproduce the bypass with the equivalent payload (it
rejected the combined `-c` form, rc=1), so the confirmed case is `python3`; `--` is emitted for both
because both honour it. An option terminator now precedes any path that is not provably safe — a
leading `-` is already outside the allowlist, so this too is byte-identical on every real corpus and
`printffmtparitycheck` still needs no re-pin. `runhintcheck` arm (6) pins it, with the
quoted-but-unterminated spelling as the control that proves quoting alone was not the fix.

A RELATIVE COMMAND IS ONLY AS GOOD AS ITS ANCHOR. Making `run=` root-relative is what makes a change
report independent of where the tree is checked out — and it makes every one of those commands useless
to a reader who cannot tell what they are relative to. Four surfaces had exactly that hole. The shared
run-hint clause claimed "relative to root=" unconditionally, including on a MULTI-root run, which
declares no `root=` at all and (correctly) keeps the absolute command: the spelling and the sentence now
answer to one predicate, `testmap.h runsAreRootRelative`, so they cannot disagree. `--flags --flip`
spelled every `p=` relative to the crawl root and declared no root either; `<flip>` now carries `root=`
with the one sentence that defines it, like every other verb. The MCP edit receipt — the surface that
hands a caller a command to paste — spelled `file`, every `tests_to_run[].run` and its stderr `next:`
relative to a root it never named; it now carries `"root"`, single-root only, the same condition every
other `root=` keeps. And `--help` still told the reader `run=` was "spelled with the same root you
scanned", which stopped being true in this lane; `--help` and `docs/COMMANDS.md` now say what the code
does.

A "./" THAT RETURNED TOO EARLY. `sarif.h rootRelativeUri` stripped a stored path's leading `./` and
RETURNED, before the root prefix was ever tried. That is right for the root `.` and wrong for every
other relative spelling: `ripwire ./corp` stores `./corp/test/x.sh`, the early return yielded
`corp/test/x.sh`, and pasting that from the root the document declares is `cd ./corp && bash
corp/test/x.sh` — rc 127. Both sides now drop the optional `./` first and compare what is left, which
leaves the one case the early return got right byte-identical. `test/rootrelemitcheck.sh` ARM 9b turns
the old spelling pair into a matrix: `.`, `corp`, `./corp`, `corp/`, an absolute path and a symlink all
print the SAME command, and each printed command is EXECUTED from the root it names.

AND THE ONE ROOT THAT IS ITS OWN SEPARATOR. That same relativizer then matched a prefix only when the
byte after it was a `/`, which the filesystem root can never satisfy: under `ripwire /` the stored
spelling is `/test/check.sh`, the byte after the prefix is `t`, and the ABSOLUTE path was emitted into a
document whose `root="/"` declares every path relative to it — `testmap.h runsAreRootRelative` is true
for any single non-empty root, `/` included, so the envelope's claim and its own rows disagreed. This is
every `p=`/`uri=` emitter in the tool, not SARIF alone: all of them route through this one pair. The
added clause strips the single leading slash, runs AFTER the general shape so no other prefix changes by
a byte, and is guarded on length so a file spelled `/` stays `/` rather than becoming an empty URI. A
corpus at the filesystem root means crawling the whole machine, so no end-to-end arm can reach it;
`test/sarifcheck.sh` arm 11 is a unit driver over the function itself, compiled with the flags CMake
gave the binary under test (the recipe `extentcheck.sh` (U) and `jsonwalkcheck.sh` already use). Its 22
rows pin both halves together — the predicate the envelope claims and the URI the relativizer returns —
and the non-root prefixes sit in the same table, so an over-stripping fix fails there rather than on a
consumer's machine. Red before the change: 4 of the 22 failed, including `rootRelativeUri(
"/test/check.sh", "/" )` returning `/test/check.sh`.

A SMALL BLOCK PAGED WITH SOMEONE ELSE'S WINDOW. The new lexical-siblings block honoured `page.offset` —
which is section `[1]`'s blast-radius offset. `--situ=F --offset=20` printed `shown=0 total=9 capped=1`
with a `next:` offering `--limit=9`, relief that cannot restore rows an OFFSET removed, and `--offset=7`
dropped six rows silently. It is a small fixed block with a cap, like the decl/def partner rows above it:
cap and `--limit`, no offset. In the same family, `unindexed_rows_floor` was computed only for a NON-EMPTY
list and the emitter suppressed the empty one, so the case where the crawl's 500-row cut removed the only
candidate printed nothing at all — a silent zero, which is the one thing METHODOLOGY §9 forbids outright.
The floor is a property of the candidate list, not of the answer: it is recorded whenever that list was
short, and the block speaks at zero. The MCP twin's `siblings_total` was the length of the array beside it
— a tautology — and now states `siblings_capped` explicitly beside a population.

A CAP THAT BOUNDED THE ANSWER AND NOT THE WORK. That same lexical-siblings block compared every
unchanged indexed file and every unsupported crawl row against every changed path, and
`isLexicalSiblingOf` re-split both paths into directory and stem on each pair; the sibling ROW cap
applies only after collection, so it bounded what was printed and never what was computed —
O( (F + U) x C ). SAME DIRECTORY is the rule's most selective clause, so the changed paths are now
indexed by directory once (a sorted vector and a `lower_bound`, not a hash or tree map) and a candidate
is compared only against the changed paths sharing its directory: one `dirOf` and one binary search per
candidate, nothing more for a candidate whose directory nothing changed in. The predicate is still
`isLexicalSiblingOf`, called on the narrowed range rather than restated, so the rule cannot drift from
the prose that documents it. METHOD: the two implementations are timed on the function itself — its only
inputs are `ing.files` and the changed-file bitmap — built `-O2` with the flags CMake gives the shipped
binary, the two binaries interleaved, best of 5, two passes. The path population is a real
`llvm-project` checkout (`4d5358b1`, clang+llvm, 8,856 paths) and `golang/go` (12,555 paths), plus that
llvm population grown to the 182,555-file rung of `docs/EVALS.md` by re-rooting whole copies of the tree
— synthetic in SIZE only, every path keeping a real directory shape and a real stem. The changed set is
spread evenly rather than clustered, because a clustered one makes every candidate's FIRST comparison hit
and understates the old cost. The host was at load average 38 on 18 cores (other work in flight), so the
absolute figures are upper bounds and the interleaved RATIO is the measurement: at 182,555 files C=500
2.20 s → 9.7 ms (226x) and C=2,000 9.10 s → 22.6 ms (403x); at the real 8,856-file rung C=2,000 333 ms →
11.6 ms (29x); on `golang/go` C=2,000 449 ms → 42.8 ms (10x). The rows are unchanged and proven so: the
emitted row list is byte-identical between the two implementations on all nine rungs measured (1,413 rows
in total), and `test/situshapecheck.sh` arm (7) already pins the case this narrowing could break — a
same-stem DECOY in another directory stays excluded, beside the same-directory-different-stem row, the
test partner and the changed file itself. No timing gate is added; there are none here.

AN ATTRIBUTE WITHOUT A READING IS A TOKEN, NOT A DISCLOSURE. The compression below shortened four
sentences into attributes, and four readings went with them: what makes the counts a floor (call edges are
name-based), what an unindexed file IS, which header the resolver gauges come from, and whose cap
`prcontext_cap=` is. `--situ` is the one dialect with no legend anywhere to look a name up in — it refuses
`--legend=compact` — so each gauge keeps a short gloss, and `test/situshapecheck.sh` arm (8) asserts the
READING, not the token. Two byte ratchets moved with them (floor 200 → 360, partner 140 → 220): a ratchet
that forbids a restored disclosure is a ratchet aimed at the wrong thing.

Measured with `wc -c`, this lane's base binary (`6621370f`) against this one over the SAME tree, so the
pair carries all three `--situ` entries below together. On this repo (root 131 chars):
`--situ=src/graph.h` 4,448 → 2,955 B, `--situ=src/situ.h` 2,332 → 2,040 B, `--situ=src/testmap.h`
2,325 → 2,033 B, `--test-gate=src/testmap.h` 5,455 → 5,247 B. On RocksDB @0e2801ac (root 66 chars):
`--situ=db/write_batch.cc` 7,489 → 7,376 B, `--test-gate=db/write_batch.cc` 9,946 → 9,868 B,
`--affected=db/write_batch.cc` 7,124 → 7,113 B. Gates: `test/situshapecheck.sh` (17 rows red on that base
binary, arms (8)–(11) new), `test/rootrelemitcheck.sh` ARM 9b/9c/9d, `test/runhintcheck.sh` 2c/2d,
`test/receiptpostcheck.sh` (18). Two gate self-checks were wrong in the same way the code was — an empty
`run=` made `eval ""` succeed, and an empty `next=` fell out of an if/elif chain printing neither PASS nor
FAIL — so each now reds on the outcome it exists to forbid. `situStemOf` was a fourth spelling of
`stripExt( baseNameOf( p ) )`; one `mention.h pathStem` now serves all four call sites. Pins moved:
`test/testgatelegendbudgetcheck.sh` 3,000 → 3,070 B for the 56 B conditional root sentence (measured
2,957 → 3,013 B on its `src/model.h` fixture), and `test/printf_parity.manifest` for `pack_task` and
`help_all`, the two labels whose text this round changed. The cap inventory is 211, not the 210 the
reference-guide entry below records: this PR's own sibling-row cap is the 211th, and `README.md` and
`docs/TUNING.md` were regenerated to say so (`test/readmedriftcheck.sh` (L2), `test/capsweepcheck.sh` (C)).

### Added — `--situ` lists a changed file's lexical siblings

The files that move WITH a changed file are usually its neighbours by name, and the caller walk can reach
none of them: a header does not call the source that implements it, an `.inl` is not indexed by any grammar
in any build, and a harness the graph cannot link — a fixture-built test, a generated `main` — is reached by
nothing. A byte-and-answer attribution over a frozen 30-question set found two answers incomplete for
exactly that reason. Section `[1]` of `--situ` now lists them, under the decl/def partners and the floor
clause: `lexical siblings (N) not_dependents=1 — same directory and stem as a changed file (its header/impl
partner, its test, its .inl): NOT transitive dependents, so they are absent from the list below; lexical and
static, never a graph result`, then one root-relative path per row. The rule is the
dumbest one that is always right — same directory, and the same filename stem or the stem-partner convention
the tests-to-run rows already use (`<stem>_test`, `test_<stem>`, `<Stem>Test`, `_unittest`, `_spec`). Same
directory is load-bearing rather than a speed trick: a same-stem file in another directory is a namesake, not
a partner, and listing namesakes would make the block noise on exactly the large trees it is for. The
candidate population is the CRAWL's, not the index's, so an `.inl`/`.ipp`/`.tcc` partner — the sibling a C++
change most often has to edit, and one no grammar can read — is named; the crawl's unsupported-extension row
list is itself capped, and the one case where that can shorten this list is disclosed as
`unindexed_rows_floor=1` — on the EMPTY list too, because a cut that removes the only candidate is exactly
the case a silent zero would hide. The block is capped at 8 rows with `shown=`/`total=`/`capped=1` and a
pasteable `next:`, and `--limit=N` raises it like the report's other two listings; it does NOT take section
`[1]`'s `--offset`, which is the blast-radius window's, so no offset can empty it. The MCP
`situational_awareness` twin carries the same list as `siblings` with `siblings_total`, `siblings_capped`
(always emitted: that payload serves every row, and an absent flag would be the silence this rule forbids)
and `siblings_unindexed_rows_floor`. It costs what it lists: the block's own rendered lines on RocksDB
@0e2801ac at `--situ=db/write_batch.cc` are 276 B — a 244 B header and one 30 B row naming
`db/write_batch_test.cc`, which no other section of that report reaches; on this repo, where every source
file is a lone `.h`, no file has a lexical sibling and the block prints nothing at all. Gate:
`test/situshapecheck.sh` arms (7)–(7d) on a fixture with a `.h`/`.cc`/`_test.cc`/`.inl` quadruple, a
same-stem DECOY in another directory and a same-directory file with a different stem — both must be absent —
plus a nine-sibling stem for the cap and its disclosure, a no-git copy of the same tree proving the block is
static (and therefore cannot leak), and the MCP twin agreeing row for row. All four arms red on the previous
binary.

### Changed — `--situ`'s disclosures are attributes

`--situ` is the only report with no XML root to hang attributes on, so every disclosure it owed was written
as a sentence, and the sentences grew: the graph-count floor clause ran 601 B, the decl/def partner header
228 B, the tests-to-run header 233 B and the script-gate caveat 167 B — 1,229 B of prose on every call,
carrying facts a reader can only act on once they are named. They are now named, and the four lines together
are 905 B. The floor line is `counts_floor=1 graph_ambiguous=N graph_unresolved=N graph_unindexed=N (the map
header's own gauges) — every count above is a FLOOR, never a total: call edges are name-based, so dynamic
dispatch, callbacks and macros can be missing; a zero is "none found", never "none exists"` (601 → 344 B),
using the same attribute spellings the XML and JSON dialects already use, so the three share one vocabulary.
The partner header carries `not_dependents=1` (228 → 209 B), section `[1]` carries `prcontext_cap=20` where
it used to spell `--pr-context`'s own cap as an aside, section `[2]` carries `order=evidence` — the attribute
`--affected`'s root already carries for the same ordering (233 → 220 B) — and the script-gate blind spot is
`script_gates_unmodelled=N`, the same counter `--affected` publishes, with its cause kept (167 → 132 B). An
attribute is shorter than a sentence; it is not shorter than the FACT, so every gauge keeps a short gloss —
this is the one dialect with no legend anywhere to look a name up in (`--situ` refuses `--legend=compact`).
Nothing was dropped: every floor, cap and caveat survives, and the readings that have no attribute form (how
to read a zero; what `[changed]`/`[partner]`/`hops` mean on a row) stay as the shortest sentence that defines
them. The four line lengths above are the gate's own `${#line}`, measured on this repo at
`--situ=src/graph.h` (the partner header on the gate's fixture at `--situ=core/widget.cc`, since this repo
has no decl/def partner for `graph.h`), against the binary this lane branched from (`6621370f`) over the same
tree — one number, one corpus, and the gate's header carries the same table. The whole-report numbers for
this lane are in the review entry above, where they belong: the same pair of binaries also carries the
relativized `run=` and the new sibling block, so no single entry owns them. The gate is the new
`test/situshapecheck.sh`: one arm per converted disclosure, each
asserting the attribute is present, that its value agrees with the XML sibling's where one exists
(`graph_unindexed=`, `script_gates_unmodelled=`), that the reading survives, and a per-line byte ratchet so
the prose cannot creep back; 10 of its rows are red on the previous binary. `test/floormarkcheck.sh` keeps
the two anchor phrases it matches — `counts_floor=1` and "is a FLOOR, never a total" — and situshapecheck
mirrors them, so a regression reds in both.

### Changed — one absolute root per change report

`--test-gate`, `--situ` and `--affected` state the crawl root once, in the envelope (`root=` in XML and
JSON, the `root:` line in `--situ`'s text), and every path below it is relative to that root — which is
what makes the document independent of where the tree is checked out. One emitter never joined: the
`run=` command. It pasted the stored disk path verbatim, so on an absolute root `--test-gate` printed
the checkout prefix three times (the anchor, `next=`, and every `<t>` row's `run=`) and `--situ` once per
runnable test line: a per-row cost against a per-document fact. The runner index now takes the run's root
and spells the command through the same relativizer every `p=` beside it uses, at all fourteen sites that
build one, so the twelve emitters sharing it cannot disagree; a multi-root run, whose disk path lies under
no single root, keeps the absolute command rather than become relative to a root that does not contain it.
The rule is stated where it is consumed: the shared run-hint clause gains "A run= command is relative to
root=: run it from there." (56 B, emitted only on a document that has rows AND a single root — a multi-root
run declares no `root=` and keeps the absolute command, so the sentence would be a false claim there) and
`--situ`'s `[2]` header says "a (run: …) is relative to root:". The saving is one root spelling per echo
less that clause, so it grows with checkout depth and with how many rows have a runner at all; the
whole-report numbers for this lane are in the review entry above, measured against the binary it branched
from over one tree. The gate is a new
ARM 9 in `test/rootrelemitcheck.sh`: a fixture carrying a real runner script, at two checkout depths, over
the eight verbs that echo a command — one anchor per document, no absolute path anywhere else,
byte-identical documents at both depths, and the printed `run=` actually executed from the declared root.
Red first on the unchanged binary (8 FAIL rows); `test/runhintcheck.sh`'s pins move with the contract, and
`test/printf_parity.manifest` moves for `--pack-task` alone, the one verb whose legend text changed.

### Added — `--in=DIR` scopes the recent-changes block to a directory and stubs the map it was not asked for

"What changed recently in DIR?" is six of the thirty questions in this project's frozen reference set (the
RocksDB corpus pinned at `0e2801ac`, scored by the frozen-30 harness described in `docs/EVALS.md`), and
`--rank-by=churn-decay` answered it with a whole-repository symbol map plus one global `<recent n="40">`
block that a directory with more than 40 recently-touched files never fits into; nothing in the binary took
a directory as a scope. `--in=DIR` (root-relative, an existing directory under the root; a trailing slash is
ignored, absolute paths and `..` are refused) keeps the global block byte-identical — three of the six golds
sit outside the named directory and complete only through it — and adds a second block
`<recent scope="DIR" n= of= capped= …>` after it with DIR's files only, `p=` spelled root-relative exactly
as the global block spells them, same order. That spelling is the whole of the retrieval result: scored by
the same harness on the same 30 questions, the sub-root-relative spelling the obvious workaround produces
completed 0 of 30 against 19 of 30 for the root-prefixed one, because every gold path in the set is written
root-relative.

The block pages the way every listing here pages, in `pageview.h`'s vocabulary: 40 rows by default, then
`capped=` beside its `n=` on every page (rule 3), `has_more=`/`next_offset=`/`offset=`/`limit=` when the
listing was cut or a window was asked for, and a pasteable `next=`. Its `of=` IS its total, so the paging
half carries no `total=`: one number under two names is a shape this project has removed elsewhere, because a
parser then has to know they are the same listing to avoid counting it twice. `next=` replays THIS
run's own corpus and window flags (`--since`, `--exclude`, `--no-ignore`, `--ignore-tests`), so the page it
names is a page of the same answer; a presentation flag is deliberately not replayed, because it cannot move
`of=`. Past 120 bytes (`kNextAttrMaxBytes`, the ceiling every other `next=` in the tool already respected)
the attribute is absent and `has_more=` still says the page exists — a hint that pastes wrong is worse than
none. The replayed set is ENUMERATED against the flags that can ride beside `--in`, not hand-picked: it also
carries `--max-file-size` when that run set one, because the crawl's size ceiling drops files out of the index
and the rows are indexed files (a hint emitted under `--max-file-size=2K` named a page of `of="3"` where the
run that emitted it saw `of="2"`), and `scopedMapNextInvocation` now lists every other rideable flag with the
reason it is NOT replayed — a cache flag indexes the same files, `--refetch` would fetch a newer tree,
`--scip` moves edges and not files, and the presentation flags cannot move `of=`. The scoped block rides
exactly when the global one does: an absent block means no history was mined, `n="0"` means history was mined
and no file under DIR was touched. That is a propagated FACT (`DecayedChurnMined::anyHistory`, carried through
`ChurnRanking` to the serializer) rather than a reading of the rows: a window whose only commit touched no
indexed file — the commit that deletes a file is the smallest one — has zero rows AND a mined history, and
inferring the second from the first published it as "no history was mined".

The symbol map collapses to a disclosed stub `<symbols stubbed="1" would_show=N next="…"/>` — the map was
not asked for, so it is not ranked at all (no PageRank runs, and the header carries no `pr_iters=` for an
iteration that did not happen), and `would_show=` is that same run's own `shown=`: the symbol DEFINITIONS it
ranks, counted individually exactly as `shown=` counts them. The rows that run prints FOLLOW from the identity
the map legend already publishes for `shown=` — `rows + sum(overloads-1) = shown`, since the print loop
collapses a const/non-const overload pair into one row carrying `overloads="2"` (this repository: `shown="200"`
over 193 rows, 7 of them at `overloads="2"`). The first wording said "how many symbol ROWS", which is a number
the document does not contain. Reporting post-collapse rows there instead is not available at any price worth
paying: WHICH definitions survive the top-K cut is a fact about the ranking, and not ranking is the whole point
of the stub. It is named as the definition count it is rather than hedged as a ceiling, because a floor/ceiling
marker in this tool means "we could not see everything" — `counts_floor="1"`, `_capped`, the truncation
disclosures — while `would_show` is EXACT and only its UNIT differs from a reader's guess; spending an
uncertainty marker on a unit difference would make "ceiling" mean "exact, but not in the unit you assumed" and
weaken every honest use of the word elsewhere in the output. It deliberately borrows no paging attribute: `total=` is reserved for THE total (rule 2) and the stub's
number is a page size, `shown=` would drag a `capped=` with it (rule 3), and rule 3's own sentence sanctions
an element that carries neither.

DIR is validated against the CRAWL and not only the filesystem — at least one indexed file must be spelled
`DIR/`, byte-exact. The filesystem answers a different question: on a case-folding volume `--in=DB` is a
directory, a symlink alias is a directory, and a subtree `--exclude` dropped is a directory, and all three
would otherwise be answered with an empty block, which reads as "nothing changed there".

REFUSED, exactly, and `--help` lists the same set: with any flag that answers instead of the scoped map,
under multi-root, with `--top-k=N` for any N (the map it sizes is the stub), and with `--json`. The first of
those is DERIVED from the flag tables rather than from a list of verbs — the shape `--html` already used —
so `--map-diff`, `--expand`/`--outline`/`--pack-signatures`, `--doctor`, `--batch`, `--mcp` and the CLI edit
bridge are covered by the same three lines that cover a report verb, and a flag added tomorrow refuses
tomorrow with nobody editing the guard. `--in` is NOT a member of the paging verb set: it is a modifier of
the default map, and membership made the shaping guard refuse every `--top-k`/`--max-tokens`/`--token-budget`
beside it with a message naming verbs and claiming the default map honours the budgets it had just refused.
`--limit`/`--offset` compose (they window the scoped element) and so do `--max-tokens`/`--token-budget` (they
shape the document that is emitted). The MCP surface exposes no churn ranker, so there is no twin to extend.

Two flags are refused for a DIFFERENT reason and now say so, and WHICH two is derived. `kMapShapingFlags` is
the tool's own list of flags that shape the bare map without selecting a verb, so that table minus the
ride-along table is exactly the residue a scoped run cannot compose with: `--no-redact`, `--metrics` and
`--map-diff`. `--map-diff` is the one that genuinely answers instead — it takes its own ranking branch ahead of
churn-decay, so no scoped block was ever going to be built — while the other two shape or un-redact a map this
run replaces with the counted stub. `--metrics` decorates symbol rows the stub does not print, and it is
refused as inert by table membership rather than by a hand-written case, so a shaping flag added tomorrow with
no ride-along row gets the right sentence without anyone editing the guard. `--no-redact` selects no
operation — it only stops
body redaction — and a scoped run serves no bodies at all, because the symbol map is the counted stub. So the
derived "answers instead" diagnostic stated a reason that was not this run's: the flag is INERT here, not
overridden. It is refused ahead of that diagnostic, in the shape the bare map already uses for the same flag,
pointing at both ways forward (drop it, or pass it to a body-serving verb). It is deliberately NOT added to the
ride-along table: accepting an inert modifier silently is the other half of the same defect. The class was then measured — and the first
measurement of it, published in this entry, was wrong. It said that of the flags the guard walks every one
probed reaches its own pairing refusal before this line, with `--external-surface` the only other flag
arriving here. Swept over the derived flag universe (`test/flaguniverse.py`) rather than a sample, 119 of the
171 `kBoolFlags`/`kViewFlags` rows reach that line, and 43 of those answer when run alone — so neither
"reaches the generic line" nor "answers alone" separates the class, because `--metrics` answers alone and what
it answers IS the default map, decorated. Table membership separates it, which is why the refusal derives the
set and `test/recentscopecheck.sh` arm 6s2e re-derives the same set from the same two tables on every run.
`--external-surface` remains a correct competitor and stays the control arm. The guard on the new branch is `--in` AND `--no-redact`: written without the first
half it refused every `--no-redact` run in the tool while quoting `--in=DIR` at it, which eight gates said in
one suite and no arm added for the fix could, since every one of them passes `--in`.

Measured on the RocksDB corpus at `0e2801ac` (`--rank-by=churn-decay`, warm cache, bytes on stdout via
`wc -c`): 39,942 B bare → 10,601 B with `--in=db`, 10,525 B with `--in=util`, 11,071 B with `--in=table`.
The saving is the stub (69 B in place of the 200-row map); the scoped block itself costs ~2.3–2.8 KB per
answer, and the global block is unchanged. On this repository's own tree: 46,787 B → 9,629 B with
`--in=src`; on llvm-project (183,835 tracked files) 48,150 B → 6,051 B with `--in=llvm/lib/Analysis`.
Because the map is never ranked, sorted, bucketed or estimated under `--in`, the run is also cheaper, though
only by the share of it that ranking was: user time, median of five interleaved warm samples with a scratch
cache, 0.73 s → 0.71 s on RocksDB and 2.55 s → 2.37 s on llvm-project (~3% and ~7%). Ingest and the call
graph dominate both, and that is the honest size of this win.

Gate: `test/recentscopecheck.sh`, 99 arms on a 53-commit fixture with 45 files under `db/` (plus two
fixtures of its own for the corpus arms) — the scoped rows
are only DIR's and spelled as the global block spells them, the global block is byte-identical with and
without the flag, page 2 (`--offset=40`) is the exact remainder with no overlap and the pasted `next=`
reproduces it byte-for-byte, `next=` replays `--exclude` and the pasted page lands on the same `of=`, an
over-120-byte `next=` is absent while `has_more="1"` remains, the stub carries no `total=`/`shown=`/`capped=`
and no `pr_iters=` rides the stubbed header, a window that mined nothing prints NEITHER block, a case-folded
name / a symlink alias / an excluded subtree each refuse naming the crawl, eight preemption arms sample the
derived refusal (`--lint`, `--hotspots`, `--query`, `--map-diff`, `--expand`, `--pack-signatures`, `--doctor`,
`--batch`), `--top-k` refuses with exactly one message where it used to print three, and `--max-tokens`/
`--token-budget`/`--limit` compose with a clean stderr. Two arms cover the continuation's corpus directly:
a run under `--max-file-size=2K` on a fixture holding one oversize file must replay the ceiling and the pasted
page must land on the same `of=`, and a window whose only commit touched no indexed file must print `n="0"`
where `--since=HEAD` (which reads no commit) still prints neither block. `perl` and `xmllint` are
PREREQUISITES of the gate (exit 2, naming the tool) rather than arms: a missing tool is an environmental
condition, and reporting it as a FAIL made `test/regression.sh` name this gate as a product regression for a
tool the machine never had. Three arms cover the refusal wording: the inert `--no-redact` message, the
`--external-surface` control that must keep the competing wording, and — the one that was missing — a
`--no-redact` run with NO `--in` at all, which fails if the message so much as mentions the scoped flag.

### Fixed — two generated documents published numbers and links nothing derived

`docs/COMMANDS.md`'s table of contents is generated: one `[`--flag`](#anchor)` per entry, with the anchor
derived from the flag's spec. The derivation replaced every run of non-alphanumeric characters with a hyphen
and trimmed the ends (the `--in=DIR` heading became `#in-dir`), where the renderer's rule DELETES that
punctuation instead of substituting it — the anchor it mints keeps the flag's own two leading dashes and loses
the `=`. All 169 links in the document therefore resolved to nothing, and had done since it was first
generated; markdownlint's MD051 had been reporting it 28 times on a single line. Fixed in the
generator (`docs/docs_commands_build.py`), which now states the renderer's own rule — lower-case, drop every
character that is not a word character, a hyphen or a space, then spaces to hyphens — and assigns anchors in
emission order so a repeated heading would get the `-1` the renderer appends rather than two links to the
first. Gate: `test/docscommandscheck.sh` arm (J), which audits every fragment against the headings (fenced
sample output skipped — a `###` line inside a code block mints no anchor) and restates the renderer's rule
instead of importing the generator's, because a gate that asks the generator what the anchor should be agrees
with the generator's mistake. Arms (A)–(I) were all green throughout: (B) compares flag NAME sets and (G)
compares bytes, and a document can be byte-reproducible with every link in it dead.

`docs/TUNING.md`, likewise generated, asserted a sum instead of deriving one: "`112 + 12` accounts for the 128
NAMES" is 124, four short of the distinct-name count in the table two lines above it — in the one paragraph
whose subject is that quoting a wrong pair "would be wrong in both halves at once". Recounted from the same
data the table is built from: `src/` declares 129 caps under 128 distinct names, of which 111 are tunable, 12
must stay `constexpr`, and 5 were declared after the sweep was prepared and no measurement has touched
(`kChurnMergeBombMaxFiles`, `kFieldIdCapacity`, `kForPageRowsDefault`, `kForPageUnionSymbolCap`,
`kMaxBlockBytes`) — 111 + 12 + 5 = 128. Neither 112 nor 12 was wrong: they are the FROZEN classification in
`bench/capsweep/tunable.tsv`, and the census beside them is re-read from `src/` on every run, so the two are
different populations and the missing four were five new names minus one (`kSituTestRowsShown`) the sweep
classified and `src/` no longer declares. The paragraph derives all three parts now, states that skew rather
than hiding it, and `capsweep.py emit` REFUSES to render a partition that does not add up — a name classified
in two lists at once, the shape an asserted sum cannot see, exits non-zero instead of publishing. Gate:
`test/capsweepcheck.sh` arm (C) reproduces the document byte-for-byte through that refusal on every run.

### Fixed — a scoped run said its ranking fell back, having run no ranking

`--rank-by=churn-decay` discloses a window that mined no commits: the teleport prior is uniform, so the map is
byte-identical to `--rank-by=pagerank`, and saying so is the difference between a degraded answer and a silent
one. Under `--in=DIR` that same sentence was false three ways at once, on a real invocation
(`--rank-by=churn-decay --in=src --since=HEAD`, a window that reads no commit). Nothing is ranked on a scoped
run — the rank vector is default-constructed and zero-filled, which is exactly why the header carries no
`pr_iters=` — so "using uniform (structural) ranking" named a computation that did not happen. "This map"
named a document the run does not contain, since the symbol map IS the counted stub and, with no history
mined, neither `<recent>` block rides at all. And the comparison it offered is unrunnable: `--rank-by=pagerank`
is refused beside `--in`, so the reader was pointed at a command the tool rejects.

The scoped branch now states what did happen — no block rides, the map is the stub, nothing was ranked, so
there is no ranking to have fallen back — and keeps the pagerank equivalence where it is true, on the unscoped
run a reader gets by dropping `--in`. The two sibling callers (the multi-root arm and undecayed
`--rank-by=churn`) pass `stubbed=false` at the call site with the reason recorded: `--in` rides neither.
Gate: `test/recentscopecheck.sh` arm 13e asserts all three claims are gone and that the notice says nothing was
ranked, with 13f the control that the unscoped sentence survives unchanged.

### Fixed — a pasteable `next=` quoted a tilde no shell expands

Every `next=` in the tool is built by `nextFlag`, which quoted any value whose first character is `~`
whether or not a flag name preceded it. So a run under `--exclude=~tmp` published `--exclude='~tmp'`, and
because the attribute is XML the escaper rendered it `--exclude=&apos;~tmp&apos;` — a replayed argument
corrupted to defend against an expansion that cannot happen. POSIX tilde expansion applies to a word whose
FIRST character is `~`; the word here is the whole argv element and it begins `--exclude=`, and an argument is
not an assignment. Measured on macOS, `sh`/`bash`/`zsh` alike: `sh -c 'p ~root'` passes `/var/root`,
`sh -c 'p --exclude=~root'` passes the literal `--exclude=~root`. The guard is now "word-initial AND no flag
name", a narrowing rather than a deletion — when the value IS the whole word (`src/editplan.h`'s rollback
invocation) the tilde really is word-initial and the quotes are load-bearing.

The worse half was the gate. `test/nextverbcheck.sh` arm (9) pinned the entity-quoted form and explained it as
a shell expanding `~tmp`, which is wrong about POSIX twice over — the tilde is not word-initial there, and
`~tmp` expands nowhere anyway, since `~user` is expanded only for a user that exists. A gate that pins a false
belief does not merely miss the bug, it defends it against the next person to fix it, so the explanation is
deleted rather than reworded and the measured rule stated in its place. The arm pins the bare form, asserts the
invocation carries no `&apos;` anywhere, and gains a mutation control: a space-bearing value is still quoted,
so the change narrowed the tilde case instead of disabling quoting.

### Fixed — a churn window says how many commits it skipped as merge bombs

The churn-decay miner behind `--rank-by=churn-decay` skips any commit touching more than 100 indexed
files — bulk renames, reformats, wide merges — and counted nothing about it, so a `<recent>` block
could silently omit the very commit a question was about: a held-out gold commit that touched 71
source files (more than 100 in all) was invisible to the block, and nothing in the output said a commit
had been dropped. The block now carries `merge_bombs_skipped="N"` on every run, `"0"` included, so its
absence is never ambiguous; the full and compact legends define it and state the 100-file threshold
(`kChurnMergeBombMaxFiles`, now a named constant in `src/gitmine.h`, listed in `docs/LIMITS.md`). On this
repository's own tree the attribute reads `merge_bombs_skipped="5"` — five commits the map had been
quietly built without. Gate: `test/churndecaycheck.sh` arm 7 builds a repository whose HEAD commit adds
101 files and asserts the block reads `"1"`, that none of those files is a row, and that both legends
define the attribute; red on the previous binary (no attribute anywhere), green now. Both legends say
"more than 100 INDEXED files" — the rule counts the files this crawl HOLDS, never the commit's raw file
count, so a commit of 120 `.txt` files and one `.py` is not skipped and the old wording described a
different rule from the code's. The threshold is the named constant at all four call sites now; the two
`--rank-by=churn` walks kept a literal `100` beside a comment claiming parity with it. `merge_bombs_skipped=`
rides the GLOBAL block only: it counts the window's skipped commits, and stamping that number on a
directory-scoped element read as "N commits under DIR were skipped", which is wrong for any DIR smaller than
the repository. STILL UNDISCLOSED, and named here rather than left silent: `--cochange`, `--situ`'s co-change
partners and `--pr-context` apply their own commit-size skip at a cap of 30 with no counter at all — the same
class of silent drop, on three other verbs; disclosing those is a separate round. A window whose
every commit was skipped — a shallow clone of a large tree is exactly this shape: llvm-project at depth
1 is one 183,835-file commit — used to print no block at all, which reads as "no history mined"; it now
prints `<recent n="0" of="0" merge_bombs_skipped="1"></recent>`, zero rows and the reason (arm 7h, red
on the previous binary). A tree with no git history still prints no block.
### Fixed — `--expand` chose its serving mode on two different price lists

`--expand`'s cheapest-complete-answer serving compares the default bundle against the whole file(s) the
requested symbols live in and emits the smaller, disclosing both byte counts on the `<ctx>` root. The two
candidates were priced by two hand-built counters. The bundle was charged the `<ctx>` envelope, the root
attributes, the unproven residue, the ranked map and the rendered `<bodies>`; the file was charged
`wf.rawBytes` plus its own legend — no envelope, no root attributes, no `</ctx>`, and the file's RAW bytes
rather than the `<src p= sym=>` blocks that actually carry them. Measured with `wc -c` on a fixture whose one
symbol sits in an 864 B file: the root said `reason="file 1100B &lt; bundle 1193B"` over a document that came
out 1262 B, so the tool selected — and reported — the whole-file form while the bundle it rejected was the
smaller document. This was the SECOND asymmetry found in this one comparison (the first, one review round
earlier, was the whole-file legend), which is the tell that the bug is the two counters rather than the
missing addends. Both candidates now describe themselves as an `ExpandServeDocument` and are priced by one
`priceExpandServeDocument`, which charges the whole served document — envelope, every root attribute, the
mode's legends, the map where it rides, the payload as emitted, the closing tag — and settles the
self-referential `mode=`/`reason=` disclosure with the same ≤4-pass fixpoint `pricedRootAttr` uses for
`est_tokens=`. The reported figures are that one function's return values, so each is now exactly the
document it names. Gates, red first: `expandmodecheck` (4a)/(4b)/(4d) assert that `reason=`'s own byte count
equals `wc -c` of the delivered document in whole-file mode, in bundle mode and in bundle-with-a-ranked-map
mode, and (4c) sweeps seven file paddings across the decision boundary and asserts the served document is
never larger than the candidate it rejected — 2 of those 7 and both identity arms FAIL against the previous
build. `expandtopk0check` (G-b) moves with it: its priced-bundle identity now reads against the document that
mode serves rather than against explicit `--top-k=0`'s undecorated root, which the old price matched only
because price and document omitted the same decoration; it is red on the previous build too (2403 B priced
against 2474 B served).

Five more from the same review round. The MCP `for` twin appended the `sc=` reading unconditionally while the
CLI lens made it present-only, so a scope-free answer defined an attribute no row carried, and the
signatures-budget exemption hand-built the same decision a second time; both now ask `forIdRouteLegendParts`
once, and `mcpforparitycheck` arm (7) pins the rule in both directions — absent on a scope-free corpus on
BOTH dialects, present on `src` on both (CLI 0 / MCP 1 before the fix). `estchargecheck` arm #18 counted two
of the three droppable legend clauses, so the `route=` reading was pinned in neither direction: with that
clause removed from the binary the arm still reported `clauses=2/2` and PASS, and it is now counted in the
wide run, the probe and the tight control that must have dropped it. `taskroutecheck`'s R-LEG arm ran every
generated command under `eval … || true`, which discards every exit status; it now captures each one and
reports anything that is not 0 (answered) or the documented empty-corpus 1 — measured over the whole corpus,
34 distinct commands, 15 and 19 — and widens its stderr check from the single compact-legend refusal to any
parse refusal. And the three route hooks' mirrored command-word rule asked the shell to split the line, which
never separates a control operator from the word it is attached to: `true; ripwire .` split into `true;` and
`ripwire` and read as not-a-call, as did every `a;ripwire` / `a&&ripwire` / `a|ripwire` / `(ripwire .)` shape.
The rule now lexes the line itself, quote-aware and executing nothing; `routehookcheck` O9 grows to 28 shapes
(19 calls, 9 appearances that run nothing), of which the five operator-attached calls answer 0 on the previous
block, and its byte-identity arm still reports one 147-line text in all three hooks. Last, `docs/LINEAGE.md`
claimed "no network" without qualification in the same sentence that already scopes its dependency clause with
"for the map": `ripwire <git-url>` is a documented input form that shallow-clones before it maps (`src/cli.h`,
and `--refetch` forces a fresh clone), so the clause now names that one exception in the sentence's own voice.

### Changed — agent surfaces ask for the compact legend

The commands ripwire writes for an agent — the `ripwire wrap` paste block, the skills under `skills/`,
the `<run>` line `--help-task` hands the prompt router, and the runnable line the tool-call router
injects — spelled every XML verb with the default legend, the ~3 KB posture the `--legend` help text
itself tells repeated callers to leave: most of a small `--callers`/`--uses`/`--impact` answer, byte-
identical rows either way. Every one of those commands now carries `--legend=compact` where the verb
accepts it (the XML verbs); `--for` keeps the default legend (its compact legend is its own, and the
first call of a session wants the full one), and the text, JSON and writer verbs the binary refuses
the flag on are untouched. Counted on this commit: 158 `ripwire <dir>` verb commands in 17 skill
files (bodies only — no description changed, so no skill's stop rules or boundaries moved), 9
commands in the wrap paste block (its 10–20 line band unchanged), 26 `--help-task` routes and the 2
tool-call routes. Humans running the bare CLI see no difference. Gates, red first: `wrapverbscheck`
arm 7 asserts the flag on every blurb command for the ten XML verbs it spells and its absence on
`--for` (10 FAIL against the previous build); `skilltruthcheck` asserts it on every skill command for
the shipped verb list (152 of 154 missing before the transform) and its absence on `--for`. Each surface also
says how to get the full legend back (owner question, 2026-09-13): the wrap paste block, the router skill's
shared conventions, the three route hooks' injected context and the MCP schema's `legend` field each carry
one sentence — add `--legend=full` when a definition's reasoning is needed (a term you do not recognise, a
floor or cap you need explained, a map a human will read); `wrapverbscheck` arm 8 asserts the sentence on
all four surfaces, red first.

### Fixed — the route hooks counted a directory named ripwire as a ripwire call

The `--observe` arm of `hooks/ripwire-claude-route.sh` and `hooks/ripwire-codex-route.sh` closes the
adoption-within-two window by inspecting the next two ripwire calls after a recommendation. It
recognised a call by any token ending in `/ripwire`, so `cd …/ripwire && git log --oneline` — the
directory, in argument position — consumed a window slot, and a real adoption two commands later was
logged as `missed` (found in the local routing analysis of 2026-09-12; the numbers stay local). A call
is now counted only when the command word itself is the binary — `ripwire`, `./build/ripwire`, any
path whose basename is `ripwire` in command position (at the start, after `;` `&` `|` `(` or `$(`,
past leading `VAR=value` assignments) — never a directory argument or a bare word after `echo`.
`test/routehookcheck.sh` O8 and `test/codexpromptroutecheck.sh` carry the regression shape (red on
the previous hooks: rows=3 where 1 was wanted; the Codex twin's position-2 adoption read as missed).

### Changed — `--for`'s compact legend is present-only, and pinned like every other verb's

Under `--legend=compact` every other XML verb answers with a legend that defines only the terms its
document carries, measured and pinned per schema in `test/compactlegendcheck.sh`; `--for` did not. Its
native compact dialect was the default dialect's sentences with a schema id in front — 1,177 to 1,216
bytes on that gate's own fixture — and it was exempt from the per-verb pin by name, so a call an agent
makes more than any other paid the one legend the compact dialect exists to shrink. It now answers with
one present-only comment: a reading for each row and root attribute the bundle actually prints
(`cx`/`ccx`/`in`/`churn`/`amp`/`clone`/`tested`, `sc=` and the `route=` code, `bundle`/`bodies`/`reason`,
the `total=`/`shown=`/`capped=` window, the hops or bodies clause of the serving shape, the tail and the
confidence gauge), and the data notes keep their numbers without their sentences
(`[floor: kept 7 of 40]`, `[doc mentions: 1 doc, 1 symbol; doc_mentions=]`); the three
ceiling-droppable clauses still fall together under a tight `--token-budget` and the dropped note still
names them. Measured with the gate's own splitter (comment bytes not present verbatim in the default
dialect's document) on its fixture probe `--for=geometry`: 915 B on the pre-change binary → **654 B**
here, pinned at **670** as the new `ripwire.for/v1` row (the table's own rule: the largest measured probe,
up to the next 10 B, plus 10), the exemption gone. A1′ first pinned it at 500 from 494 with only its own
clauses present; the merge with #213 put the `coverage=` reading on the same probe, and this round made
the `sc=` and `route=` readings present-only, so the number was re-measured at each step rather than the
clauses trimmed to hold a pin. Per call, default legend → `--legend=compact`, three tasks
measured with `wc -c` on this repository at the lane's merge of `origin/main` 0e3573af:
`pagerank power iteration` 9,875 → 9,338 B (−537, and 25 → 29 signature rows, because the bytes the legend
gives back are spent on rows), `rank graph teleport` 10,121 → 9,812 B (−309, 22 → 25 rows), and the
name-exact `escapeXml` 6,290 → 4,918 B (−1,372). The **delta** is the claim: the absolute bytes carry
`churn=`/`amp=` readings derived from git history, so they move by a few bytes per commit landed. The MCP
`for` twin declares no `legend` field and serves the default dialect only, so its bytes are unchanged. `legendcoveragecheck` holds:
every attribute the compact document carries on its first screen has a `name=` definition in that one
comment, with `next=`, `pure=` and `schema=` on the recorded floor exactly as before.

### Changed — symbol rows carry a short id (`sc=`) instead of repeating their path

Every scoped symbol row on the map and on the `--for`/`--pack-task`/`--from-trace`/`--pack-signatures`
signature rows printed its canonical id in full — `id="src/mcpverbs.h::rw::applyCompactToBatchSubs"` on a
row that already sits under `<f p="src/mcpverbs.h">` or carries `p="src/mcpverbs.h"` itself. On this
repository's flagless map that was 137 of 137 scoped rows repeating the path the wrapper had just
printed. The row now carries only the segment nothing else on the page holds, `sc=` (the enclosing scope),
and the legend states the composition: the full id is `p::sc::n`, with `p=` taken from the row or its
enclosing `<f>`. Nothing an agent could address before is unaddressable now — `--expand`, `--callers`,
`--impact`, `--uses` and the MCP twins accept the composed `path::scope::name` exactly as they accepted
the printed `id=`, and `test/scroundtripcheck.sh` proves it: the multiset of ids composed from the new
rows is byte-identical to the multiset the previous binary printed on two fixtures, every composed id
resolves through `--expand` to a body of that path and name, a mutated scope resolves to nothing, and the
old spelling still resolves on input. Two smaller cuts ride the same rows: `route=` is a code
(`name-exact(X)`, `subtoken+body`, `subtoken+body:broad`, `subtoken+body:declined(word;carriers,defs)`)
with its reading in the legend instead of 107 bytes of prose per answer (23 bytes now; the `anchors:`
evidence clause is unchanged), and a `--for` compact bundle merges the same-named callees of one `calls`
block into one `<c n= l="70,69"/>` row (`shown=` still counts callees). Measured with `wc -c` against the
build of `origin/main` (f6a27167) run on this same merged tree, so no corpus drift rides the numbers: the
flagless map of this repository 26,449 → 22,407 B (−15.3%, the same rows), `test/cppqualfix` 2,935 →
2,781 B, `test/nestedqualfix` 2,045 → 1,937 B; a fixture with four scoped rows (`test/accessshapefix`)
grows 9 B, because the `sc=` reading is longer than the `id=canonical(…)` clause it replaces and four rows
do not pay it back. On `--for` the bundle is byte-shaped, so the row savings became ROWS: three tasks on
this tree, same tree and same day, main's binary → this one — `pagerank power iteration` 9,470 B at
`shown="20"` → 9,880 B at `shown="25"`, `rank graph teleport` 10,134 B at 19 rows → 10,022 B at 22 rows,
and the name-exact `escapeXml` 5,977 → 5,846 B. Five more ranked rows for 410 B on the first; three more
for 112 fewer bytes on the second.
The new legend is two clauses, both ceiling-droppable with the confidence clause and both exempt from the
signature-trim charge like every other disclosure: the `sc=` composition rule (`; sc=scope (full id
p::sc::n)`, 29 B) on every answer, and the `route=` code vocabulary (54 B) only on the answers whose root
carries `route=` — the same present-only condition the compact dialect already used, and one shared
spelling for both dialects so a code cannot acquire two readings. The route clause rides the document
rather than living only in `--help`'s `--no-route` entry (where the fuller reading of each code still is)
because a code with no reading anywhere in the answer is an undefined first-screen attribute:
`test/legendcoverage_baseline.txt` is a ratchet that may only be edited downward, and dropping the clause
opened two new lines in it. A 259 B first spelling grew a 2.9 KB fixture bundle by 10% and tripped
`test/forrankordercheck.sh`'s 4% ratchet; the 83 B shipped here crosses it nowhere on the nine frozen
fixture bundles (+0.5…+3.2%). The `--json`
twins mirror the attribute (`"sc"`), so `mcpattrparity` holds without a rename. Pins moved with the
bytes, every one of them RE-MEASURED on the merged tree rather than carried over from either lane's own:
seven compact-legend schemas in `test/compactlegendcheck.sh` (map 810 → 920, map-diff 800 → 910,
pack-signatures 680 → 780, metrics 720 → 820, query 630 → 730, pack-task 820 → 980, pack-top-n
660 → 770) for the one new whole-document `sc=` reading; `ripwire.for/v1` 500 → 690 (measured 678 — A1′
pinned that dialect at 500 from 494 with only its own clauses present, and the merge brought the
`coverage=` reading onto the same probe); the ten-verb legend loop 4,900 → 4,700 B (measured 4,645 — DOWN,
because A1′'s present-only `--for` legend outweighs what both lanes added); the MCP manifest ceiling
42,200 → 42,900 (measured 42,820); `test/fixture`'s map `est_tokens` 884 → 894;
`test/forrankordercheck.sh`'s q5 9,470 → 9,880, attributed four ways (main tree/main binary 9,464, this
tree/main binary 9,470, so corpus drift is 6 B — the other 410 B is this change, and it is five more
ranked rows); five goldens regenerated for the row shape and the clauses; the printf-parity manifest
re-pinned for `help_all` alone at each of the lane's two merges with `main` (`UPDATE_GOLDEN_EXPECT`
matched both times, 41 labels unchanged); across the whole lane seven of its 42 labels moved — six for the
row-6 row shape and `help_all` for the merged `--help` text. The second merge (`origin/main` 0e3573af)
also brought `help` and `expand`: `help` moved on main alone (#217 re-worded `--replace-symbol-body`'s
summary line) and `expand` on this lane alone (the whole-file serving's `sc=`), so each was resolved to the
side that moved it, while `help_all` — moved by BOTH — was re-measured against the merged build rather than
picked from a parent that never produced that text.

### Fixed — `--for`'s rung zero fires on the exact ceiling, not on the overshoot allowance

Under an explicit `--token-budget`, `--for` prices its header against the delivered-byte allowance
(budget × 2.36 × 1.15) and, when the document does not fit, first drops the three explanatory legend
clauses whose loss costs no fact (confidence, tail, the `sc=` rule) before touching anything a reader
would miss. The 1.15 tolerance exists for the residual a lens cannot trim — a first signature is not
divisible — but it also gated that first drop, so a document 1–15% over its budget that still carried
all three clauses shipped `over_ceiling="1"` with them riding: on a fixture whose path left a few dozen
bytes of slack, `test/fornotesbudgetcheck.sh`'s 1640 rung measured est_tokens=1755 and
`test/forrootlegendcheck.sh`'s 800 rung 831 (both CI, PR #215). The free drop is now tried against the
number the root promises (budget × 2.36) and only what remains is judged by the tolerance. On the merged
tree the same 1640 rung reads est_tokens=1515 with eight rows intact, and `forrootlegendcheck`'s arm 2
(850 since lane for-widen re-anchored it) reads 832 with the root-relative clause surviving.
`test/estchargecheck.sh`'s late-label sweep control is re-anchored to where that residual band now sits
on its corpus (760..1500; hits at 780–810).
### Changed — tests-to-run rows without a runner are grouped by hop distance

Every tests-to-run row that had no derivable runner said so on the row — `run_unknown="1"` in XML,
`"run_unknown":true` in JSON, `(run: not derivable)` in `--situ`'s text — and on a corpus where almost
no harness has a runner that was the same 16 or 23 bytes repeated once per row: on the RocksDB tree,
`--affected=db/write_batch.cc` listed 127 tests, 126 of them runner-less, and paid 2,016 B of XML and
2,898 B of text for one fact. Rows already come in evidence order (changed, partner, hops ascending,
path), so runner-less rows whose per-row attributes are byte-equal are now served as one row,
`<g hops="2" n="17" p="a,b,c" run_unknown="1"/>` (JSON: `"p"` — or `"test"` — becomes an array beside
`"n"`; text: `[hops=2] (17): a, b, c   (run: not derivable)`), emitted where its first member stood. Rows
with a runner stay single, a group of one stays a `<t>` row, a path that contains a comma is never grouped
at all (`p=` is a comma-separated list and every XML parser undoes an entity before a consumer splits on the
delimiter, so an escaped comma would reappear as a separator and `n=` would disagree with what the reader
counts — the text twin had no escape to undo), and every path is kept verbatim — the multiset of paths
before and after is identical and so is their ORDER, which is what `test/testrowruncheck.sh` arm 12 proves
on a fixture with three hop groups and a runner row
in the middle of one of them, in all three dialects (red on the previous binary). All twelve emitters —
`--affected`, `--exercises`, `--test-gate` XML and JSON, `--situ`, `--pr-context`, `--handoff`,
`--flags --flip`, `--pack-task` XML and JSON, the MCP `situational_awareness` twin and the edit
receipt — render through one seam in `testmap.h`, and the M21(b) rule keeps its meaning: a `<t>` or
`<g>` row carries `run=` or `run_unknown="1"`, never neither. Measured on RocksDB (`wc -c`, same cache,
same commit): `--affected=db/write_batch.cc` 10,668 → 6,992 B, `--test-gate=db/write_batch.cc` 13,242 →
9,747 B (its JSON 11,055 → 7,163 B), `--situ=db/write_batch.cc` 11,769 → 7,357 B, and in the compact
dialect 9,312 → 5,313 B and 11,223 → 7,596 B; 8 `<g>` rows replace 124 single rows (a group covers a
contiguous run only, so the one runner row inside the hops=2 tier splits it in two — order is preserved by
construction, `test/testrowruncheck.sh` arm 12 reads the paths back in emitted order) and the residual
spent on the disclosure is 160 B (XML, 10 `run_unknown="1"`) and 230 B (text) per list.
`--pack-task`'s tests section is byte-budgeted, so it CUTS over its own grouped, escaped rendering: it takes
the largest prefix of the row list whose rendered `<tests>` body fits the section budget, found by bisection
(the rendered size is monotone in the prefix length, so the bisection is exact), and counts `shown=`/`total=`
in test files. Measured on RocksDB with `--pack-task="change WriteBatch::Put"` at the default 6,000-token
budget, `wc -c`, same cache, same commit: `<tests shown="55" total="109">` where the pre-E1 bundle named 28,
the whole bundle 11,993 → 12,490 B. On this tree every harness has a runner, so nothing groups and the only
change is the legend that now defines `<g>`: the `--test-gate` legend pin moves 2,720 → 3,000 B (measured
2,957) and the `ripwire.pack-task/v1` compact pin 820 → 880 B (measured 865), both because the compact
dialect and every rows-bearing full legend now define `run_unknown=` and `<g n= p=>` — a definition
`--affected` and the compact dialect never carried. That compact `<g>` term now says what the full clause
says, in the full clause's own words: its first form promised "every path verbatim (`&#44;` a comma)", an
escape `testmap.h` does not emit — a path holding `,` is not grouped at all — and it never carried the rule
that a `shown=`/`total=` over these rows counts test FILES, so a reader holding only the compact legend was
told to undo an entity that is not there and disagreed with the full legend about what the pair counts. The
term goes 99 → 194 B and is charged only on a document that carries a `<g>` row (measured on a fixture of six
runner-less tests, `--affected --legend=compact` 501 → 596 B); no pin moves, on this tree or on any gate
fixture, because every harness here has a runner and nothing groups. The two wordings cannot be one constant
— the compact dialect exists to re-spell, not to quote — so `test/compactlegendcheck.sh` arm (R) pins them
against each other, reading the phrases it requires out of `kRunHintLegendClause` itself rather than
restating them, and fails the next release where either wording drops one or promises `&#44;` again (red on
the parent commit's source). The MCP manifest ceiling moves 42,384 → 42,800 B
(measured 42,777) for one 207-byte clause, plus the one-space separator that joins it to the sentence before
it, spliced into each of the two tool descriptions that serve these rows as JSON (2 × 208 B):
`situational_awareness` and `explore` return bare JSON with no legend of any kind, so a caller that
reads `p` as a string has nowhere else to learn that it can be an array.
The clause is rows-gated everywhere it is spliced — `--affected`, `--exercises`, `--pack-task`, the
partitioned bundle, and `--pr-context`, whose legend precedes its files in the STREAM but is now decided
after them: the chosen body is rendered first, the pricer charges the clause per candidate trim level from
that level's own body, and the form the chosen body was priced with is the form written, so the priced
legend and the delivered legend cannot disagree. A corpus-level predicate over-approximated it — a test
file outside the selected range, or a trim level whose `testCap` is 0, bought the clause for a document
with no row — and both now pay nothing (measured on `test/defaultceilingcheck.sh`'s 120-file, no-test
fixture: unconditional, the default bundle went 7,989 → 8,025 tokens over its 8,000 budget; gated, 7,989;
`test/prcontextcheck.sh` pins all four sides, red first). The clause is gated on a COUNT the emitter
reports with its rows, never on a search of the rendered bytes: `--pr-context` charges the trim level's own
row count and the partitioned bundle sums what each slice kept. Asking the bytes was wrong twice — a
`--pr-context` body and a `--pack-task` slice can both carry the literal text of the element inside CDATA,
and `--pack-task="write_report" --partition=2` over a two-file corpus with no test at all bought the outer
clause because one body prints `<tests n="%d">` (`test/testrowruncheck.sh` arm 15, red first). `--handoff`
and `--flags --flip` spliced the clause unconditionally and now ask the same count; `--handoff` is
byte-budgeted with heuristic rows dropped tail-first, so on a packet with no test row the 180 B it was
paying could evict a real row (arm 14, red first).

Two byte-accounting rules changed with it. `--pack-task`'s tests section used to group FIRST and cut the
group rows with the generic list cutter under a per-row cap whose estimate was computed on UNESCAPED path
bytes, so a corpus whose test paths hold `&` or `<` rendered wider than the cap admitted; the cutter breaks
at the first over-budget entry, so the whole tail of the section went with it — `run=` singles included.
Measured on a matched pair of ten-test fixtures differing in one byte per name (`&` against `_`) at
`--token-budget=1440`: the control named 5 files and the `&` fixture named none. Cutting over the grouped,
escaped rendering fixes it and is strictly better than cutting the single rows and grouping afterwards,
which would have been safe but spends fewer of its bytes (2 files where grouping-first served 5); across
budgets 1440–1860 the new cut names 6–11 files against the old 5–11, and the `&` fixture never empties
(`test/testrowruncheck.sh` arm 13). And `--pr-context`, which must render a level to price it, rendered
through a helper that returned an empty string on an `open_memstream` failure with no alert at all — a
document could have shipped its legend, root and closing tag around an empty body claiming
`truncated="none"`. Every such render now goes through one seam in `infra/emit.h` (`rw::renderToString`,
which `packtask.h` already had in its own spelling) that reports the failure, and both `--pr-context` exits
fall back to streaming the level straight out: complete, correct bytes, a modelled estimate, and a
`DEGRADED_PATH_ALERT` saying which — serialize.h's own degrade contract.

Six gates read the PATHS out of these rows, and each had its own reader: since a row can now name several
files, `grep -oE '"tests_to_run":\[[^]]*\]'` stopped at the first `]` (the end of the first group's path
array, so three arms asserted over two and a half rows and passed vacuously), `sed`-based XML readers saw
only the single rows, and the text reader took `$1` of a line that on a group line is `[hops=1]`. They all
want the same thing — the files named, in emitted order — so `test/affectedcheck.sh`,
`test/impactpartitioncheck.sh`, `test/receiptpostcheck.sh`, `test/rootrelemitcheck.sh`,
`test/selectorchaincheck.sh` and `test/testrowruncheck.sh` now all ask `test/testrowpaths.py`, one reader for
all three dialects and both row shapes. Two more gates read these rows and keep their own readers, because
neither asks for the paths: `test/listingpagingcheck.sh` sums `n=` over the group rows to prove the family
never pages, and `test/w3fixlegendcheck.sh` counts path occurrences on a `--situ` line. That shared reader
had two silences of its own, and both now fail loudly with a control in `test/testrowruncheck.sh` arm 16. Its
JSON slicer returned the same nothing for a document with no `tests_to_run` field and for one whose array
never closes, and the path reader turned that into an empty list at exit 0 — so a TRUNCATED document
asserted over zero rows and passed, which is the defect the file was written to end. The two are different
claims: no field is an answer (0 paths, exit 0), an unclosed list is exit 2 with a named reason. And the text
dialect's single-row reader took `(\S+)`, which stops at the first space, so a test path holding one was
reported truncated — a path that does not exist, produced silently. It now cuts the run suffix and the
renderer's own attribute tail (`[changed] [partner] [hops=N]`, in that order and no other) and keeps
everything between verbatim; what the text dialect still cannot resolve is a path holding the literal
three-space `(run: ` opener, because that dialect carries no escaping at all — XML and JSON are exact.

Three more things the row work left half-said. `rw::renderToString` asked `open_memstream` and then ignored
what `fflush` and `fclose` answered, returning `ok=true` regardless: a memstream grows by `realloc`, so an
allocation failure the per-row writes swallowed surfaces at the flush, and it is the close that publishes the
buffer and its size at all. Reading them anyway is how a SHORT document passes for a whole one — the same
defect as the empty body one size smaller. Both results are now checked, the alert fires, and `--pr-context`
takes the streaming fallback it already documents. The MCP row-shape clause named the key `p`, and only one
of its three producers spells it that way: `situational_awareness` emits `test`, `explore` and the edit
receipt emit `p`. A clause naming the wrong key is worse than no clause, because a caller reads it as a
contract, so it names both per producer while the rules they share are still stated once; the manifest
ceiling moves 42,800 → 43,000 B for a measured 42,973 (the clause 207 → 305 B in each of the same two
descriptions, 2 × 98 B). And `renderToString` called the emitter outside any handler: a throw from it —
`std::bad_alloc` out of the `std::format` fallback is the reachable one, since the point of the seam is to
buffer a document whose size is not known in advance — skipped the `fclose`, the `free`, the alert and the
documented empty-result fallback in one jump, leaking the memstream and its buffer and handing the caller an
exception where its contract says `ok == false`. Measured on this tree with the fault injected:
`--pr-context` aborted at `rc=134` with **zero bytes** on stdout and `libc++abi: terminating due to uncaught
exception of type std::bad_alloc` — the whole document lost, not just its estimate. The seam now catches at
its own boundary, releases what it owns once, discloses, and returns the degraded value its callers already
read, so the same run exits 0 with a complete 14,627-byte well-formed document carrying the same 20 `<f>`
rows as the undegraded control. The alert names the throw rather than borrowing the buffer's message, which
on that path would be a wrong cause attached to a right consequence. Because a throw path is otherwise
unreachable from a gate, it is driven by an in-source fault switch in `serialize.h`'s
`isChargeBufferFaultInjected` shape — non-NDEBUG only, read once per process, exact `"1"` the only ON value —
and `test/prcontextcheck.sh` arm (F) asserts the whole contract with its own observability probe, red on the
parent commit (`rc=134`, 0 B, no alert). That switch carries the `INFRA_` prefix rather than this project's:
everything under `src/infra/` is built to travel to another repository, and `test/infraportcheck.sh` (C)
refuses a layer file that names the host — it caught the switch's first spelling, which is the gate doing
exactly what it exists for.

### Fixed — an unmeasured `est_tokens` said nothing, a no-throw contract threw, and two test-row readers still went quiet

Six defects from one review, each of them a surface that was silently wrong rather than loudly broken.
**`--pr-context` shipped a wrong `est_tokens` with no disclosure.** When a trim level's measurement render
fails, `prRenderLevel` returns an EMPTY body; the ladder priced that empty body, the price fit, and the root
printed it — while `writePrContext` correctly streamed the complete untrimmed floor. The only signal was
`DEGRADED_PATH_ALERT`, which `src/infra/Diagnostics.h` compiles to `do {} while (0)` under `NDEBUG`, so the
binary a user installs printed a modelled number with nothing at all saying so (non-negotiable #3). The bytes
were never the bug and are unchanged — a failed measurement may not decide what the answer contains — so the
fact goes where this class of fact already lives: `truncated=` now carries `;est-unmeasured`, re-priced with
the label in place, and the legend defines it in the same voice as `budget-floor-exceeded`. That label is 15
bytes and can ride beside `budget-floor-exceeded`, which takes `prBudgetTail`'s worst case from 248 B to
263 B: `tail[256]` (SEVEN bytes of margin, as `test/fixedbufsweep.sh` had warned in terms) becomes
`tail[320]`, 56 B of margin, and the sweep's row moves with the measured recomputation. `rw::formatTo` was
not what had been saving it — it truncates silently and its return is not read there, so an overrun would
have dropped the closing quote of `truncated="` and shipped a malformed root with no diagnostic.
**`renderToString`'s no-throw contract had a throwing last statement**: `out.text.assign( buf, sz )` is the
one allocation on the success path and sat outside the handler, so a `std::bad_alloc` from it escaped a
function documented to return `ok == false`, and jumped the `std::free( buf )` two lines below on the way
out — leaking the memstream buffer. It is caught in its own handler (the two failures need different
cleanup: the emitter's throw owns an open stream, this one owns only the buffer) with its own alert literal,
and control falls through to the single `free()`, so the buffer is released exactly once on every path.
Proved by `INFRA_FAULT_RENDER_COPY_THROW`, the twin of the emitter switch, in `test/prcontextcheck.sh` arm
(G) — red on the parent commit, and honest in both flavours: the switch and the alert live only on the
non-`NDEBUG` build, so the plain-flavour leg proves the degrade and the `NDEBUG` leg asserts only that the
verb is intact and that no false disclosure appears. The `est-unmeasured` LEGEND definition is asserted on
every flavour, which is the point of moving the disclosure off the alert. **The shared test-row reader's
malformed-field detector had a hole of its own species**: `test/testrowpaths.py` found `"tests_to_run"` and
then scanned arbitrarily far forward for a `[`, so `{"tests_to_run":null,"other":[{"p":"ghost.cpp"}]}`
sliced the NEXT field's array and returned `ghost.cpp` at exit 0 — a foreign field's paths served as this
field's answer, where the docstring already promised a `TestRowParseError`. The value is now read
adjacently (past the key, a `:`, optional whitespace, then `[` or raise); `null`, a number, a string and an
object all take the raise, in both `paths` and `jsonlist`, with a well-formed array and JSON whitespace as
controls (`test/testrowruncheck.sh` arm 17). **And two path readers had never been converted.** A census of
`test/` over the four shapes the reader was written to replace found `test/affectedcheck.sh`'s `tset()` —
in the file the reader's own docstring names among those it converted, so that claim was false — splitting
EVERY row's `p=` on `,` including a single row's, which turns a comma-bearing path (never grouped, by
`testmap.h`'s refusal) into two names that name nothing; and `test/testgatecheck.sh`'s `tset()` matching
`<t p=` singles only, which returned the EMPTY set on a two-runner-less-test fixture where the shared reader
returns both paths. Both now route through the shared reader. Every other hit in the sweep either counts
rows (`listingpagingcheck`, `w3fixlegendcheck`, `testgatepagecheck`, all group-aware in place) or pins one
exact row spelling with a regex that fails loudly, and `deeptailcheck`'s `<t p=` rows are `--for`'s tail
listing, a different element sharing the tag. Two documentation drifts close beside them: the
`skills/ripwire-mcp/SKILL.md` verb table claimed `p` for `situational_awareness`, which emits `test` (the
binary states the split at `src/mcp.h`'s `kTestRowJsonShapeClause` and is the authority), and
`bench/arb/run_arb.py` decoded a `&#44;` the seam stopped emitting on 2026-09-13 while decoding none of the
entities it does emit — so a path holding `&` was scored against a file name that does not exist. Both row
shapes there now share one decode.

### Added — the task router knows the recency question, and every new shape is named where an agent reads

Two halves of one gap, both measured as absences rather than argued. **The router could not reach the
history question at all**: `what changed recently in DIR`, `who touched this lately`, `the newest commits
here` — every phrasing abstained with `score="0"`, so `--rank-by=churn-decay` and the `--in=DIR` scope
beside it were unreachable from a task said in words. `ripwire <dir> --help-task="<task>"` now answers
those with the `recency-window` intent under `ripwire-fresh-eyes`. The route is conjunctive in three
parts, because two are not enough: a TIME word, a MOTION word, and a word naming the corpus (or a
directory of it the task named) — a time word alone is usually part of a compound noun, and a time word
plus a motion word is also a sentence about a supplier's terms last quarter. An explanatory question is
never this route however many of the three it holds, and the working tree stays `--situ`'s question. A
directory is composed into `--in=DIR` only when the corpus really holds it AND the running build ships the
flag, read off the flag table itself: a router that recommends a flag its own parser has no row for hands
back a command that exits non-zero on the first paste. Cues are matched WORD-BOUNDED, which is not a
detail: with the substring spelling `here` occurred inside where/there, `source` inside outsource, `file`
inside profile and `code` inside codec, and a sentence about a supplier revising their terms recommended
the churn window at `confidence="high"`. That holds for the multi-word cues too, which delimit their own
interior and nothing at their two ends — `show documentation` contains `how do` and `show issues` contains
`how is`, so both of those questions about this repository's history tripped the explanatory guard and lost
the route that answers them. The route also sits BELOW the weighted tier, which is how it
reads a dirty worktree: on a dirty tree `is my diff safe to merge, i changed these files recently` is
still the `review-diff` question, and that route wins before this one is consulted. Held out
(`bench/taskroute_eval.py`, the committed 225-row corpus plus 24 rows for this round, split by its
content-hash rule): accuracy 0.939 → **0.946** test, 0.946 → **0.950** dev, precision 1.000 and harmful
0.000 unchanged. The 225 pre-existing rows score the same three numbers on the new binary — and, measured,
**0 of them reach the new route at all**, so that identity is reported as the near-vacuous check it is
rather than as evidence.

**And the first call now names the widening step.** `--for`'s file-grain page was named only by a thin
ANSWER's own `next=` — one call too late for an agent choosing what to run first — so every `--for`-shaped
recommendation carries the page as its own `next=`, keyed off the INTENT (a task that merely quotes the
flag inside another verb's argument gets none) and spelled by `forpage.h`'s own `forWidenNext`, so it
obeys the same quoting and the same 120-byte ceiling every other `next=` obeys. The `--help-task` document
also gains the LEGEND it never had in the default dialect: every attribute on its only screen was
undefined, and it now joins `legendcoveragecheck`'s enumeration and `nextverbcheck`'s population.

The shapes this release adds are also named where an agent actually reads them: the recency window with
`--in=DIR` and `merge_bombs_skipped=` (ripwire-fresh-eyes), the thin-answer `coverage=` gauge and the
`--for … --limit=40` page (ripwire-orient and its `map-before-you-read` companion), the `p::sc::n`
composition of a row's identity, and the grouped `<g hops= n= p= run_unknown="1"/>` tests-to-run row
(ripwire-change-check). **A new gate keeps it that way**: `test/agentsurfacecheck.sh` is a ratchet over all
163 long flags `--help` advertises — each is named in a skill body or the `ripwire wrap` primer or recorded
on a committed floor with the reason it is still a gap (5 lines today) — plus a per-shape arm that requires
the term and its verb within five lines of one another on one surface, probing the binary first so a
surface never promises what the build cannot parse. `docs/COMMANDS.md` is deliberately not an accepted
surface: it names every flag by construction, and a gate a generated document satisfies for free cannot
fail.

### Fixed — the reference guide said things the binary does not

@heliocipher's reference guide was verified claim by claim against a 0.6.0 build, and its flags held up: of the 82
`--` tokens it named, the 72 that are ripwire flags all exist and are spelled as it spells them (the other ten
belong to `cmake`, `xmllint`, `graphify`, `skills/install.sh`, or are anchor fragments). What it got wrong it
mostly inherited from this repository.
**"Dynamic dispatch contributes no edge"** was the opposite of the truth — a virtual call emits one edge per
candidate in the receiver's inheritance cone, each `prov="split"` and counted in `amb=`; a four-class fixture
returns three edges, not zero, with CHA-lite correctly dropping the same-name method of the unrelated class. The
honesty section was understating the tool, which costs a reader's trust the way overstating it does.
**`MSVC 19.36+`** was offered as a supported compiler beside an operating-system row naming only macOS and Linux;
it is not a target, and the row now points Windows users at WSL2. **"18 task-shaped skill files"** was one of three
defensible counts of one directory — 17 routable (`skills/*/SKILL.md`), 18 `SKILL.md` files in all
(`skills/hermes/` holds a Hermes-native one), 16 activated for every agent (`ripwire-opt-remarks` carries
`audience: contributor`) — and the README stated two of them, neither labelled. **"208 compile-time caps"** is 210
by `docs/limits_build.py`'s own derivation from `src/`. **"Directory symlinks are not followed"** understated the
limit: no symlink is followed, and a symlinked source file is not indexed at all, so a tree that reaches its
sources through links reads as if they were not there. **Exit code 2 was missing** from the exit-code table, which
is the one a CI script most needs — a policy gate fired (`--arch`, `--scan-skill`, `--quality-delta`), not an
unknown failure. And one sentence sent a reader to `--scan-skills` to check a single file, which is the directory
verb; the file verb is `--scan-skill=FILE`.

Unstated, and now stated: `git` is a runtime dependency for the history-backed verbs, which refuse with exit 1 and
a named reason rather than answering thin — `--map-diff` and `--rank-by=churn` answer and disclose the uniform
fallback, `--dmm` and `--pr-context` return an explicit unavailable row. A git URL as the root is the one thing
that touches the network. The write verbs return a receipt — region, `blob_sha`, contract check, tests to run —
so an agent never re-reads the file, and their payload is a whole definition, signature included, not a braced
body. Test coverage is read from call edges out of indexed test symbols, so a shell suite that runs a built binary
as a subprocess is invisible to it (`harness=script`, `reaches=0`) — which is this repository's own shape. `--json`
is an allow-list of nine verbs. `--quality-panel` has a `strict` preset that drops the two families which reshuffle
on unchanged code. Several verbs stay single-root in a multi-root run. Section 3.2 now splits by why a reader is
there — `scripts/pgobuild.sh` for a binary to use, the plain tree for work on the tool — and scopes the
`NDEBUG`/`DEGRADED_PATH_ALERT` warning to the development tree, where it belongs.

`--replace-symbol-body`'s one-line `--help` summary said it replaces a definition's *body*. It replaces the whole
definition, signature included, as its own long help already said and as both insert verbs say. An agent that
believed the summary sent a braced body and deleted the signature — disclosed in the receipt as
`post_check_unavailable`, not refused.

`test/readmedriftcheck.sh` gains three arms, so these counts cannot drift again: **(J)** the skills count, pinned to
the routable set and to the install fold's "sixteen of the seventeen"; **(K)** the `--json` allow-list, harvested
from `--help=--json` and required to match the guide in both directions, so a verb that gains `--json` support fails
the gate until the guide is updated; **(L)** the cap inventory, pinned to `docs/limits_build.py`'s derivation. Each
carries its own mutation control. Arm **(B)** took `head -1`, and so pinned one of the *two* sites stating the flag
count — the reference guide's copy had been free to drift since it was written; it now checks every site and names
the line that disagrees. `CONTRIBUTING.md` gains the rule those arms encode — an advertised count is an enumeration,
and if a set can be counted more than one way the prose must say which set — and the stale-object build hazard,
which until now lived only in `CLAUDE.md` ([#217](https://github.com/redhat-et/ripwire/pull/217)).

### Added — --for pages its answer one file per row, and says when to widen

On the pre-registered follow-up ladder (a 2,066-file C++ corpus pinned at one commit, the frozen 30
questions, six deterministic steps per tool, no model in the loop), every ripwire follow-up completed 0
answers through step 4: `--for`'s `next=` pointed at `--expand` (a body, not a wider list), `--top-k` was
inert on `--for`, and `--format=candidates` is symbol-grain (40 symbols is about 18 files in 11 KB). The
one follow-up that completed answers in that ladder was a file-grain page — one row per file, about 6 KB.
Local telemetry had `--for` → `--expand` followed 0 of 259 times.

`--for=TASK --limit=N` (`--offset=M` pages it) is now that page: a `<files>` document of one
`<f p= score= n= sym=/>` row per positive-score file, `p=` spelled root-relative exactly as every other
verb spells it, ranked file-first by `score=` — the IDF-weighted share of the query's subtokens the file's
top 8 symbols cover between them (a term counts once however often it recurs, so one huge file cannot
monopolise; ties by the best symbol's lens score, then path). The root carries the house paging vocabulary
(`shown= total= capped= has_more= next_offset= offset= limit=`) and a `next=` naming the next page.
When the answer is THIN — the top-ranked symbol's name, doc or body carries under 50% of the query's
IDF-weighted subtokens (an unmatched subtoken weighs as the rarest, so a `(#12147)` token lowers the share
honestly), or the ranked head spreads over fewer than 3 files — `--for`'s root carries `coverage=` (that
share, whole percent) with its legend clause, and the r=1 row's `next=` names `--for=TASK --limit=40`
instead of the body. A confident answer carries none of the three and is byte-identical to before; the
`--json` and MCP twins follow the same present-only rule. The MCP `for` twin takes the same
`limit`/`offset` and serves the same page through the same renderer. Beside the page every bundle-shaping flag is refused, never ignored (`--limit=0` and non-numeric
values were already refused). `--top-k` stays inert on `--for` and `--help` now says which flag widens.

Measured, on the ladder re-registered with the page as step 2 on the `--for` shapes: ripwire's
complete@step row is unchanged at 14/14/14/14/17/17 — the page completed no question, because the seven
misses it ran on hold 3–21 gold files each — while adding gold files on four of the seven (+2, +1, +3 and
+6 files) at 5,539–6,212 B per page (mean 5,841 B), and the thin rule named the page on 4 of those 7
misses. The frozen-30 single-call instrument is unchanged at 14/30 complete and 42/129 gold files named;
its median bytes-to-answer is 6,348 B (5,988 B before: 10 of the 12 `--for` questions on that instrument
are thin — commit subjects with a `(#NNNN)` token, "how does A reach B" questions — and carry the clause;
the 2 confident ones read the base again, and the 18 non-`--for` questions moved by the 2–4 B the git
stamp moved on every verb). Gate: `test/forwidencheck.sh` — a generated 33-file fixture whose gold file sits at page rank 13
and is absent from the default head and tail; one row per file, determinism, paging with no overlap,
`coverage=` defined in both dialects, thin versus confident `next=`, the refusals, MCP parity — red on the
pre-change binary. The byte pins that ride a thin `--for` header
(forrankordercheck's fixture rows, forrootlegendcheck, compactlegendcheck's loop, the two `--no-route`
goldens) were re-anchored with the measured number; the confident ones read the base again.

### Fixed — the review round: a ceiling priced in the wrong unit, and a shape that outlived its output

Twelve findings from the 2026-09-13 review of this lane, each reproduced before it was touched.

The one that changed behaviour for every budgeted call: `--for` and `--pack-task` tested their ceiling
rungs at `kMinBytesPerToken` (2.36) while `est_tokens=` and `over_ceiling=` price the delivered document
at `kBytesPerTokenDefault` (2.50). A lens therefore spent rungs against a ceiling it was not measured
against, and dropped legend clauses from documents its own root reports as conformant:
`test/cppqualfix --for="widget ping make box" --token-budget=1200` printed `est_tokens="778"` with no
`over_ceiling=` and had dropped all three droppable clauses "(ceiling)". `rw::ceilingBytes( budgetTokens )`
is the one expression for what a root promises, and the ladder now takes two ceilings: the as-built and
task-echo rungs (the echo is a byte-for-byte duplicate of `task=`, so spending it costs a reader nothing)
aim at the exact ceiling, while dropping `route=` and labelling the bundle keep the 1.15 first-entry
tolerance, which exists for a residual a lens cannot trim. The same query now reads `est_tokens="1146"`
at `--token-budget=1200` with every clause riding. No tolerance was widened and no ceiling was raised.

**And then the rung stopped being a byte test at all.** Getting the RATE right left the deeper half: a byte
comparison cannot express this root's promise, because `est_tokens` is not bytes ÷ 2.50. It prices markup at
`kBytesPerTokenDefault` and the `--detail` / auto bodies at `kBytesPerTokenBody` (3.80) — one rate per kind —
so comparing the raw document total against `budget × 2.50` charged every body byte 1.52× what the root charges
it. The same test also assembled its candidate from RESERVES and from the auto section whether or not that
section was rendered, which is not the document stdout receives. Both errors point one way: a document its own
root reports as conformant was judged not to fit, and three definitions a budgeted reader has no other source
for were spent to buy headroom that was already there. Measured on a git-less five-symbol fixture at
`--detail=1`: at every budget in **1069..1099** the kept document prices at `est_tokens="1069"` with no
`over_ceiling=`, and the rung dropped all three clauses anyway and delivered `est_tokens="715"` — 354 tokens of
headroom spent to buy nothing. At 1090..1099 even the raw byte total fitted (2,736 B of 2,737) and only the
reserve-priced half vetoed. The exact ceiling is now the token comparison itself, asked once on the finished
document, so there is no second expression to disagree with the first; the allowance rungs stay byte-based,
which is their contract. Gate: `test/estchargecheck.sh` #18, which reads the price off a wide run and probes
five tokens above it rather than pinning a budget — red on the pre-change binary at the probe arm, green at
its control (the rung must still fire where the drop is real).

**One correction to the record.** The residual this entry previously reported — `ripwire . --for="pagerank
power iteration" --token-budget=2500` delivering 5,769 B against a 6,250 B ceiling with its clauses dropped —
was not an instance of the defect above, and still behaves that way. The 481 B of headroom is the document
AFTER the drop; the document that kept its clauses prices at `est_tokens="2684"` (measured at
`--token-budget=2700`, the first budget at which the same query keeps everything), which does not fit 2,500.
The rung was right there, and the leftover headroom is the granularity of an indivisible ~900 B clause trio.
The real defect needed a body-rate document to show itself, which that bundle (`bodies="0"`) is not.

Rung zero also stopped being byte-negative. It removed 110–164 bytes of clauses and spliced a 161-byte
note naming them: on a route-less compact answer that is **+51 bytes**, a rung that made the document it
was shrinking bigger and cost the reader three definitions to do it. The candidate is built and compared,
and a drop that does not pay is not taken.

The dropped-clause note itself described a different document. Four constants picked by one `coverage=`
lookup: the thin spellings named neither `sc=` nor `route=` though rung zero clears that reading on a thin
answer too, the default spelling claimed `route=` had been dropped under `--no-route` where it never rode,
and the compact spellings named `sc=`, which that dialect defines in a clause rung zero does not touch.
One assembler builds the note from the four facts that decide what was there to lose.

Both identity readings are **present-only** now: `sc=` rides when a served row carries a scope, `route=`
when the root carries the attribute — one decision (`rw::forIdRouteLegendParts`) shared by the append, the
signature-charge exemption, the CLI lens and the MCP twin, which had been mirroring it by hand at four
sites. A corpus of free functions pays nothing for the vocabulary of scope: `test/anchorfix`'s and
`test/routefix`'s goldens are byte-identical to their pre-lane selves again.

Three surfaces were answering in shapes the tool no longer produces. The MCP **file page** composed
`"routed: " + reason` by hand, so one server answered its bundle `route="name-exact(pick)"` and its page
`route="routed: name-exact(pick)"` — a spelling no legend defines; one producer (`routeNoteOf`) serves all
four sites. `--expand`'s **whole-file** serving still printed `id="PATH::SCOPE::NAME"` inside a `<src
p="PATH">` that had just printed the path, on a document carrying no legend at all; it prints `sc=` and the
root states the composition, and the compact dialect gained the `ripwire.expand-file/v1` schema, because
`--expand`'s two servings share no element and one purpose line had been describing the wrong one.
`docs/COMMANDS.md` was rebuilt from a capture re-recorded on this binary in a **ref-clean clone** (96 `id=`
rows → 26, all of them JSON-RPC and cluster ids; 19 `id=canonical(…)` legends → 1, the `--uses` row's
`in_id=`, which names a different symbol and is correct). `bench/shotgun/cc_static.py` keyed on `id`, which
is absent now, so it fell through to `path::name` and collapsed two same-named methods of one file into one
key — a silent miscount in a benchmark; it composes `p::sc::n`.

A cap could cut an answer it did not need to: a merged callee row was charged `name+16` while printing about
four bytes, so a block of overloads exhausted its budget early and wrote `capped="1"` over a listing that
would have fit. Charged at what it prints. And `l=` was appended in rank order, so one fact had two
spellings between queries (`l="70,69"` / `l="69,70"`); sorted ascending.

Three gates were enforcing or reporting the wrong thing. `attrvocabcheck` arm 8 matched map rows by the
retired `id=` spelling, checked zero rows and printed a PASS; it is re-keyed and now fails on zero checks
(six rows cross-checked). `skilltruthcheck` held a hand-typed list of sixty verb names that included `zoom`,
so it enforced `--zoom --legend=compact --mermaid` — a command the binary refuses; the arm now RUNS each of
the 43 distinct `--legend=compact` commands the skills spell against an empty directory and reads the
refusal, which immediately found two more broken lines in `ripwire-quality-bar`. `taskroutecheck` gained the
same probe over all 34 commands the router generates, and the router applies the posture once
(`rw::legendCompactAppliesTo`) instead of in 26 hand-edited strings. `legendcoveragecheck`'s shared-name
floor shrank by the four lines it had been reporting as no-longer-reproducing.

The route hooks and their own meter disagreed about the same command line, and the substitution rate is a
ratio of those counts. The observe regex missed every wrapped invocation an agent types (`time
./build/ripwire`, `sudo`, `env X=1`, `xargs`, `exec`, `nohup`, `if ripwire`, `{ ripwire`) and still matched
`git commit -m "fix; ripwire hook"`. `rw_is_ripwire_call` is the shell's own model — walk the words, ask
whether any command-position word basenames to `ripwire` — mirrored byte-identical in the three hooks and
asked by the meter too; `routehookcheck` O9 diffs the copies and reads 18 shapes.

Pins moved, every number re-measured on this build: `test/compactlegendcheck.sh`'s table was re-derived from
its own stated rule (largest measured probe, up to the next 10 bytes, plus 10), which seven rows had not been
following — map 892 → pin 910, map-diff 885 → 900, pack-signatures 759 → 770, metrics 798 → 810, query
707 → 720, around 760 → 770, pack-task 974 → 990, pack-top-n 745 → 760, `ripwire.for/v1` 654 → 670, and the
new `ripwire.expand-file/v1` 230 → 240; the ten-verb loop reads 4,645 B under its 4,700 pin.

The last two came in without review threads, and both were documents contradicting something the same
repository already states. **The compact-legend policy was not being audited in the direction that matters.**
Every verb command an agent-facing skill spells carries `--legend=compact` where the binary accepts
it (`--for` exempt, its compact legend is its own), and `test/skilltruthcheck.sh` had two arms for it — but
both start from a command that ALREADY carries the flag, so they can only catch a flag that does not belong.
A command that should carry it and does not was invisible to the whole gate, which is how
`ripwire <dir> --rank-by=churn-decay` shipped flagless in `ripwire-fresh-eyes`'s pass 1a. Seven spans across
six skills are fixed (pass 1a and the `--help-task` route beside it, `--max-tokens=3000`, `--no-ignore`,
`--pattern=`, `--run-trace=`, and the two `--grep-in=any` recipes in `ripwire-security-scan`), and the gate
grew the missing direction: a flagless span must carry the flag when the bare command emits XML on an empty
corpus AND appending `--legend=compact` is not refused — both halves asked of the binary, never of a list.
The XML precondition is what makes it sound rather than noisy: 21 spans look like violations without it and
6 were real, because a placeholder operand (`--arch=rules.txt`, `--scip=index.scip`) fails before the legend
check is ever reached and its silence would otherwise read as consent. *Floor, stated rather than implied:*
the arm skips every span whose operand cannot resolve on an empty corpus, so it is a floor on the policy and
not a total — those spans are unproven in both directions, not proven exempt. A positive control (a flagless
`--flags` must classify as a violation) keeps a green from being the classifier failing silently; red on the
pre-fix tree named 5 of 33 flagless spans.

**And the README contradicted its own dependency table.** The guide's opening said "It has no runtime
dependencies" while the table ~120 lines below says "None for the map itself. The history-backed commands
need `git` on the path, and a repository to read" — and names the twelve commands that do. The prose now
scopes the claim the way the table does and names `git`; the no-API-key, no-embeddings, no-index-server and
no-daemon claims are unchanged, because those are true unconditionally. `docs/LINEAGE.md`'s comparison bullet
carried the same unscoped sentence and is scoped identically.

### Fixed — a header's declaration no longer widens to an internal-linkage definition (parser version 96)

The decl-to-def widening behind every `file:name` selector (`--callers=api.h:helper`, `--impact`,
`--uses`, `--safe-delete`, the MCP twins) kept a same-named definition when its file `#include`d the
declaring header. That proof is per FILE, and a translation unit that includes `api.h` for its own
reasons may define an unrelated `helper` in an anonymous namespace or as a namespace-scope `static` —
an overload (`helper(double)` beside the declared `helper(int)`) compiles, and by name it was gathered
and served. Internal linkage makes a definition visible to its own translation unit alone, so no other
file's declaration can stand for it. Raised by CodeRabbit on #139 after merge, outside the diff.

Every C and C++ definition now carries a syntactic `internalLinkage` bit — inside an anonymous
`namespace { }` at any depth, or carrying a namespace-scope `static` (a class-scope `static` member has
external linkage and is not marked). The widening keeps such a definition only for a declaration in its
own file and otherwise counts it in `unproven_defs=`, so the reader still learns that same-named
definitions exist which no row covers; the bare-name selector still shows them, as the legend says.

Measured on the gate fixture (`test/decltodefcheck.sh` arm B2: a header, its defining `.cpp`, one real
caller, and two including TUs with an anonymous-namespace and a `static` overload): `api.h:helper`
answered `count="3"` on main where `api.cpp:helper` answered `count="1"`; it now answers `count="1"`
naming the one real caller, with `unproven_defs="2"`. On this repository at `1cf3086e` the default map
is byte-identical and none of the 11 header-qualified `--callers` selectors over `src/ingest.h`'s
declarations moved (the tree has no colliding internal-linkage overload). `kParserVer` 95 → 96 and
`kCacheVersion` 21 → 22 (the def record gains one byte) with `quality.h`'s mirrors in the same commit;
old caches are rejected and rebuilt.

### Added — Elixir module and arity resolution (parser version 95)

Elixir calls now resolve by module, name and arity, with lexical aliases, filtered imports, default
arguments, pipes, captures and delegates. Nested modules and each target of a multi-target `defimpl`
have separate identities. Types, callbacks and attributes are navigable, and protocol/behaviour
relationships appear in the existing relationship views. CLI and MCP use-site queries share the same
resolution rules; unknown modules and excluded imports no longer fall back to unrelated functions.

The implementation uses the existing vendored parser and cache records, with no Elixir runtime
dependency. Macro expansion and runtime dispatch remain static-analysis limits; the supported syntax
and boundaries are documented in [Elixir extraction](docs/ARCHITECTURE.md#elixir-extraction).

`kParserVer` 94 → 95 with `quality.h`'s `kIngestParserVerMirror` in the same commit (the branch carried
87; main spent 87..92 while it was open and the 0.6.1 round takes 93 and 94 — re-bumped to the next free
number over the merged tip, per the rule in `src/ingest_cache.h`); `kCacheVersion` stays 21.

Four review findings were closed as maintainer commits on the branch, each with a row in
`test/elixirnamearitycheck.sh`. A call that only a `use`-injected import could answer minted no edge
and was dropped silently; it now counts in the map header's `unresolved=` and every answer's
`graph_unresolved=` (an undefined spelling stays undefined, modelling `__using__` stays open). A
variable bound on the right of `=` inside a pattern — `def join(%Socket{} = socket, _)`, a `case`
clause, a `with` generator — is a binding, not a zero-arity call of a same-named function. The quality
key folds the arity out of an Elixir name, so `run(x)` → `run(x, y)` is a `--edit-check`
contract-change on `run` (params 1 → 2) with every caller of the old arity listed and flagged, and a
`--quality-delta` params row, rather than a dead symbol beside a new one; a default (`run(x, y \\ 1)`)
still reports the change but flags nobody (`kQSnapCacheScheme` 10 → 11). `--for` by an exact function
name (`generate_app`, `text`) routes name-exact and ranks the `name/N` symbol first.

Five resolution rules the branch got wrong, found by reproducing against Elixir 1.20.3 / OTP 29 before
the merge, each with a row and a control in `test/elixirnamearitycheck.sh` over `test/elixirresolvefix`.
`import M, except: [...]` after `import M, only: [...]` subtracts from the only-list instead of replacing
it (a function the only-list never named minted an edge, silently; the refusal is now counted). A dotted
nested `defmodule Inner.Deep` aliases `Inner` → `Outer.Inner` from its declaration on, so the later
`Inner.Deep.f()` names the nested module rather than a top-level one — or, with no top-level one,
rather than nothing. `alias __MODULE__, as: Current` inside a multi-target `defimpl` reaches each
implementation's own function, not the first implementation's. `&_seed/0` names the underscore-named
function (the underscore rule is for unused variables; a bare `_seed` read still is one). And `f()` on a
bodyless `def f(x \\ default())` head reaches the head beside the clauses, so `--path=caller,default`
and `--impact=default` see the caller; `f(1)` still reaches the clauses alone. Every one was a wrong
answer or an uncounted drop. They ride parser version 95 — the number this entry introduces, which no
released binary has written — with `kCacheVersion` 21 and `kQSnapCacheScheme` 11 unchanged. Still open,
and documented in [Elixir extraction](docs/ARCHITECTURE.md#elixir-extraction): calls inside
`unquote(...)` / `bind_quoted:` under `quote`.

### Upgrade notes

- **A sidecar must be a regular file: a symlink at a sidecar name is refused, on read as well as on write.**
  `.ripwire_notes`, `.ripwire_quality_baseline` and `.ripwire_arch_baseline` are opened with `O_NOFOLLOW`, so a
  link at one of those names is not opened, wherever its target is. Anything else at the name that is not a regular
  file, a FIFO for example, is refused as well instead of being waited on. If you symlinked one on purpose (into a shared
  config directory, say), replace the link with a regular copy of its target. Until you do, every read of it prints
  a refusal on stderr, no notes surface, `--quality-delta` reports `baseline="git-HEAD (symlinked sidecar refused)"`
  and compares against HEAD, `--arch` reports every violation as new, and `--note-add`, `--quality-baseline`,
  `--arch --baseline` and `--baseline-update` exit 1 without writing. `.ripwire_config` and
  `.ripwire_quality_acks` are unchanged.

### Added — a Ruby constant argument and a rescue class are dependencies; `lazy_edges=` counts distinct pairs (parser version 93)

Round three of the Ruby constant work, on the same corpus-own index as round one (superclass, mixins, autoload —
parser version 82) and round two (constant receivers — 83). Ruby's rule is that EVALUATING a constant is what makes
the autoloader load its file, and a receiver is only one of the places a constant is evaluated. Round two pinned the
other two as its disclosed floor; this round lifts them.

**A constant argument is a directive.** A constant chain that is a direct positional child of an `argument_list`,
or the value of a keyword pair written directly in that list, is a symbolic Include: `raise Errors::Boom`,
`validates_with Validator`, `delegate :name, to: Helper`, `record.is_a?(User)`, `super(Validator)`, `yield User`.
The `argument_list` is the grammar's one node for the arguments of a call (with or without parens), a `super` and a
`yield`, so one read covers all three. The lists of `include`/`extend`/`prepend`/`autoload` stay round one's, one
record per statement. An argument is lazy inside a closure and load-time at class-body or file level, exactly like
a receiver — `validates_with Validator` in a class body is a load-time dependency on validator.rb, which is what a
Rails model file's structure actually is.

**A rescue class is a directive, and it is lazy always.** Every constant chain in a `rescue` clause's exception list
(`rescue Errors::Bust, Errors::Boom => e`) is a symbolic Include. Ruby evaluates that list only while matching an
exception, never when the clause is loaded — `class X; begin; 1; rescue Nope; end; end` is silent, and the same
`begin` with a `raise` inside names `Nope` in a NameError (ruby 4.0.6) — so a class-body rescue is a use, not a
load-time dependency, and it stays out of the ccd/godfiles structure like every other lazy pair.

**One dedupe key.** Arguments and rescue classes share round two's (file, innermost open, written name) record with
receivers: a `raise Errors::Boom`, a `rescue Errors::Boom` and an `Errors::Boom.new` in one nesting are one
directive, and the parser-86 AND rule still decides the lazy bit — a rescue above a class-body receiver of the same
name is one load-time directive.

**`lazy_edges=` over-counted, and the fixture for this round is the shape that showed it.** `<health lazy_edges=>`
and a row's `lazy_edges=` are documented as DISTINCT (file, target) pairs, but the count walked an un-deduped
adjacency that is in directive order, not sorted, and counted a pair once per run of equal ids: `Errors::Boom`,
`User`, `Errors::Bust` in one method resolve to errors.rb, user.rb, errors.rb and read as 3 for 2 pairs. It now
sorts the dropped ids and counts unique ones. At this round's parser version the old count read 1 546 / 1 147 / 6 398 / 2 549
on the four corpora below against the distinct 1 381 / 1 015 / 6 342 / 2 519; every other byte of `--deps` is
identical between the two counts (checked on activerecord). Round two's own fixture never interleaved two spellings
of one file with another target, so its pins were right by shape rather than by the count.

**A value-position constant is a dependency, not import evidence — and the call graph is byte-identical to main.**
The first cut of this round let the new records feed buildGraph's include narrow, which reads a file's resolved
includes as evidence for which definition a bare call means. That is wrong for a value position: `notify(Dev::Config)`
beside `record.update!` says nothing about what `record` is, and the narrow bound `update!` to `Config#update!` on that
reading — on discourse 1,017 call sites newly bound or narrowed, 19 of 20 sampled wrong (the PR #139 review). `Include`
gains `isValueUse` (cache format 21), set for argument and rescue records and cleared by any receiver occurrence of the
same name, and `buildPreciseIncludeAdjWithContext( …, forCallNarrow=true )` — called only for buildGraph's
`fileIncludes` — leaves those records out; `--deps`, `--impact`'s importer tier and the lazy-pair count read them as
before. Measured against main's binary, built from the same merge base: the default map is **byte-identical** on the
four corpora below and on this repository, and `--report`'s totals match to the unit (activesupport 3 650 edges /
410 modules, activerecord 8 638 / 912, the Rails apps 23 784 / 2 067 and 12 108 / 1 384). The pre-fix branch had moved
every one of them (23 447 / 2 030 and 55 more isolated symbols on the first app). Gate: the review's own repro,
`test/rubyargnarrowfix` — two `update!` definitions in different directories, a caller in a third that passes
`Dev::Config` and then calls `record.update!` — declines the call as main does (0 callers, `declined_calls="1"`) while
`dev/config.rb` keeps notifier.rb as a lazy importer; red on the pre-fix binary (1 false caller).

**Disclosed floor, pinned to yield nothing** (`test/rubyargfix/lib/app/floor.rb`): a `when` pattern (evaluated
eagerly by Ruby — the next round's first candidate), an array or hash-literal element, a splat, an assignment's
right-hand side, string interpolation, a binary operand. Each is an evaluation Ruby performs that this round does
not read.

Measured (`--deps --limit=100000 --no-cache`, parser version 88 → 93, measured on the branch's pre-merge binaries; the gems are Rails 7.2.3.2, the apps the same
two Rails apps as rounds one and two, aggregates only):

| corpus | ccd | nccd | shape | load-time importees | lazy_edges | bytes |
| --- | --- | --- | --- | --- | --- | --- |
| activesupport `lib/` (282) | 15 299 → 15 775 | 7.59 → 7.83 | tangled | 201 → 202 | 935 → 1 381 | 75 988 → 85 530 |
| activerecord `lib/` (395) | 4 325 → 4 657 | 1.44 → 1.55 | vertical | 310 → 310 | 1 023 → 1 015 | 114 763 → 129 011 |
| a Rails app, 4683 files / 3532 `.rb` | 13 172 → 17 798 | 0.32 → 0.43 | horizontal | 414 → 1 015 | 5 630 → 6 342 | 750 915 → 855 559 |
| a second Rails app, 2002 / 1895 `.rb` | 6 543 → 7 577 | 0.34 → 0.39 | horizontal | 200 → 557 | 1 878 → 2 519 | 370 991 → 471 865 |

The importee column is the finding: on the two applications the files with a load-time importer went 414 → 1 015
and 200 → 557, because a class-body DSL argument (`validates_with Validator`, `delegate … to: Helper`, `rescue_from
Errors::Boom`) is where a Rails file names what it loads. No shape moved; ccd grew and stayed horizontal,
which is the structure/use cut doing its job. The `lazy_edges` column carries BOTH mechanisms above — new lazy
pairs in, the over-count out — and activerecord is the corpus where the second outweighs the first. The default map
of this repository (no Ruby) is byte-identical before and after.

Gate `test/rubyargcheck.sh` + fixture `test/rubyargfix/` (19 files, written RED against the parser-88 binary: 22
arms red, every control green); `test/rubyrecvcheck.sh`'s floor arm inverts and its report.rb pins move by the one
`raise`/`rescue` directive; `test/rubyrequirecheck.sh`'s main.rb counts its `rescue LoadError` as a shown,
out-of-tree row (12 → 13). `kParserVer` 92 → 93 with the mirror (the branch spent 89 while main spent 89..92 on the extent detector, Kotlin and the yaml patch); cache format 20 → 21 (`Include::isValueUse`);
re-pins with reasons in-file: `test/qschemetrip.hash`, `test/printf_parity.manifest` (the `--impact` help and
legend name the two new closure kinds; the `--deps` legend's lazy definition gains the rescue class). `docs/COMMANDS.md`
regenerated (2026-09-11).
### Changed — `VERIFY_NO_ALIAS` is a release optimizer fact, on LLVM 17 as well

- **`VERIFY_NO_ALIAS` is now an optimizer fact in release, not an inert assume.** `src/infra/Diagnostics.h` §6 adds
  `__builtin_assume_separate_storage` (clang 17+, `__has_builtin`-guarded, `( (void)0 )` elsewhere) beside the debug
  check, so codegen matches `__restrict__` on the parameters (`out=a; out+=b; out+=a;` arm64 10 → 6 instructions);
  `VERIFY_NO_ALIAS_BUF` is the form for two OWNING containers (the object form is inert for their loops; views — `std::span`, `std::string_view` — can share one allocation and are refused at compile time); the comment carries
  the complete-object contract and the macOS `<sys/cdefs.h>` trap that deletes bare `__restrict` in C++ —
  `__restrict__` is the only spelling allowed in `src/`. `test/noaliascheck.sh` (eight arms, red against the old
  definition) proves it. The optimizer half is a separate switch: BasicAA reads the bundle only when
  `basic-aa-separate-storage` is on — `cl::init(false)` in LLVM 17 (AppleClang 16 / Xcode 16.2: the macos-14 CI
  runners and the macos-arm64 release leg), `true` from LLVM 18 — so CMake now probes and passes
  `-mllvm -basic-aa-separate-storage` to our targets (and to the ld64 link under LTO), and the gate classifies the
  compiler by compiling the real slice three ways, with a `=false` negative control and a cross-check against the
  cached CMake probe.
### Added — `VERIFY_NO_ALIAS` guards at 15 call sites where self-aliasing was a silent wrong answer or UB

`VERIFY_NO_ALIAS` / `VERIFY_NO_ALIAS3` at the top of 15 functions whose two-or-more same-element-type
out-parameters would silently mis-compute or invalidate an iterator if a caller ever passed the same
object twice. The check runs in debug builds; in release the macro leaves only the
`__builtin_assume_separate_storage` promise on the two objects, which the optimizer reads on clang 18+
by default, on LLVM 17 / AppleClang 16 only with the CMake-added `-mllvm -basic-aa-separate-storage`
and there for scalar accesses, and not at all on GCC or clang before 17. For these 15 functions the
promise measured no codegen change (the object form says nothing about a container's heap buffer), so
there is no performance claim here: these are correctness contracts.
- **Six more aliasing contracts at function entry, completing the audit; one of them is the tree's only codegen row.** `waterFillRecallShares`
  (`src/recall.h`) reads `demand[i]` while writing `alloc[i]` and never resizes either, so it takes the buffer form:
  release codegen 309 → 301 instructions under the build's own flags. `splitNoteTail` (`src/notes.h`),
  `takeAckNamedToken` and `computeDelta` (`src/quality.h`) take the object form, whose check runs in debug and whose
  release residue is the `separate_storage` promise on the two objects (read on clang 18+ by default, on LLVM 17 /
  AppleClang 16 only with the CMake-added flag and for scalar accesses, never on GCC or clang before 17); for these
  it measured no codegen change. `computeDelta`'s two out-pointers both default to null, so its guard is a
  null-safe `VERIFY_TEXT` rather than the object form.
  `markCandidateFilesIncludingDecl` (`src/graph.h`) and `partitionByScope` (`src/verbs_quality.h`) take the last two
  guards of the audit's apply list, which is now complete: 21 functions state their no-alias contract at entry.

## [0.6.0] — 2026-09-11

**Languages and integrations from outside the project, much faster on the largest trees, and answers that say where
they stop.** Outside contributors wrote the Kotlin support (@xCatG), the Dart support (@calvinchengx), the Hermes
installer mode and Hermes-native skill (@AnkitArya, @ashutoshsinghpr7), JavaScript and TypeScript default-import
resolution (@PollyBot13), `CLAUDE_CONFIG_DIR` support (@s0undt3ch) and the Ruby constant-dependency work
(@andriytyurnikov). Outside reports caught the tool being confidently wrong (@YogevKr, @mariadb-KyleHutchinson,
@snrmwg) and asked how to remove it (@luisdavim). Each is named below, beside the entry their work produced.

### Highlights

**Kotlin.** `.kt` files are indexed: classes, objects and companion objects, functions, calls, imports and
inheritance. Calls cross the Kotlin/Java boundary in both directions, and a reference reaches the other JVM language
only when its own defines no candidate of that name, so adding `.kt` files never moves a Java-only edge. nowinandroid
indexes to 1,850 symbols across 384 files, ktor to 19,906 across 2,527, and retrofit's `Response.java:body` keeps its
279 callers (@xCatG, [#126](https://github.com/redhat-et/ripwire/pull/126)).

**Dart.** The 23rd grammar. On flutter/packages (3,706 `.dart` files) it indexes 71,726 Dart symbols (@calvinchengx,
[#75](https://github.com/redhat-et/ripwire/pull/75), landed in
[#106](https://github.com/redhat-et/ripwire/pull/106)).

**Ruby: the dependencies a Rails application actually has.** A Zeitwerk application spells almost none of its
dependencies with `require`. 0.6.0 reads the ones it does use: superclass constants, `include`/`extend`/`prepend`,
`autoload`, and constant receivers such as `User.find` — the reference that makes the autoloader load the file, where
nothing else in the file says so (@andriytyurnikov, [#57](https://github.com/redhat-et/ripwire/pull/57),
[#65](https://github.com/redhat-et/ripwire/pull/65), and [#78](https://github.com/redhat-et/ripwire/pull/78) landed in
[#91](https://github.com/redhat-et/ripwire/pull/91)).

**Faster where it hurt.** Warm `--grep` on llvm-project falls from 159.7 s to 9.2 s, and the warm default map from
248 s to 10 s ([#83](https://github.com/redhat-et/ripwire/pull/83)). The cold parse on that tree drops from 194.1 s to
155.6 s of CPU ([#127](https://github.com/redhat-et/ripwire/pull/127),
[#130](https://github.com/redhat-et/ripwire/pull/130)), warm `--pack-task` on go from 8.13 s to 5.88 s, and a repeated
`--for` on llvm-project from 274 s to 26 s once the cache stopped evicting its own working root
([#127](https://github.com/redhat-et/ripwire/pull/127)).

**Answers that say where they stop.** A `std::`-qualified call no longer binds an in-repo definition, so memgraph's
`SafeString::move` goes from 2,107 false callers to 3 ([#134](https://github.com/redhat-et/ripwire/pull/134)). A call
the resolver declines to guess is counted and named instead of silently dropped: 65,516 of memgraph's 295,086 call
references ([#136](https://github.com/redhat-et/ripwire/pull/136)). A parse derailed by a member macro carries
`extent_suspect=` and leaves the `--hotspots` ranking, and a budgeted `--for` stops shipping past its allowance
without saying so ([#135](https://github.com/redhat-et/ripwire/pull/135)). And YAML parses the same on aarch64 Linux
as everywhere else ([#140](https://github.com/redhat-et/ripwire/pull/140)).

**Agent integrations.** Initial Hermes and OpenClaw support, activated by `skills/install.sh --hermes` or `--openclaw`,
with `ripwire wrap` printing the MCP setup ([#51](https://github.com/redhat-et/ripwire/pull/51),
[#46](https://github.com/redhat-et/ripwire/pull/46)). `CLAUDE_CONFIG_DIR` is respected wherever ripwire looks for
Claude Code's configuration (@s0undt3ch, [#101](https://github.com/redhat-et/ripwire/pull/101)). `INSTALL.md` lists
every install route and how to remove all of it ([#121](https://github.com/redhat-et/ripwire/pull/121), asked for in
[#111](https://github.com/redhat-et/ripwire/issues/111)).

### Upgrade notes

- **Prebuilt x86-64 binaries now need an x86-64-v3 CPU, on Linux and on macOS.** x86-64 builds target
  `-march=x86-64-v3`: AVX2, BMI1/BMI2, FMA, LZCNT and MOVBE, the floor RHEL 10 sets, found on roughly Intel Haswell (2013)
  or AMD Excavator (2015) and newer. On an older x86-64 CPU the 0.6.0 binary will not run. The Intel macOS binary
  carries the same floor and still runs on macOS 14 and later; on Apple silicon, use the arm64 binary. arm64 builds need
  nothing new, because NEON is in the arm64 baseline. A plain build from source on x86-64 targets the same level;
  `-DRIPWIRE_NATIVE=ON` builds for the configuring machine only, and `./install.sh` from a checkout builds a Release
  binary tuned for that machine's CPU ([#127](https://github.com/redhat-et/ripwire/pull/127),
  [#137](https://github.com/redhat-et/ripwire/pull/137)).
- **The installer checks the CPU before it downloads.** On an x86-64 machine below v3, `scripts/install.sh` stops before
  the download and lists the missing features. `RIPWIRE_SKIP_CPU_CHECK=1` skips the check, for a VM that hides CPU flags
  its host still executes. When a downloaded binary cannot run, the installer now says why instead of reporting a
  version mismatch ([#138](https://github.com/redhat-et/ripwire/pull/138)).
- **The first run on each tree is a cold parse.** The cache format moves from 16 to 20 and the parser version from 81 to
  91, so a cache written by 0.5.0 is not reused. Separately, the cache root key is now one derivation for every cache
  family, so lean, rich, qchurn and MCP blobs written by older builds are clean misses, one cold parse per root, and the
  age pass sweeps them ([#127](https://github.com/redhat-et/ripwire/pull/127)).
  The parser version moves once more, to 92, for the YAML scanner fix below
  ([#140](https://github.com/redhat-et/ripwire/pull/140)); the cache format stays 20.
- **Output that changes by design.** Each change is described in its entry below.
  - `--quality-delta` dials each kind separately, and `churn="self"` no longer gates (#127).
  - `--help` prints one line per flag; `--help=all` prints the whole catalog (#92).
  - `--regex` anchors `^` and `$` match per line, and a match can no longer span lines. The `--grep` root gains
    `corpus_pruned_dirs=` (#85).
  - `--grep` and `--regex` no longer read gitignored files of an extension the indexer skips; `--no-ignore` restores
    them (#87).
  - `--recall` spends its budget on sections in rank order, and its disclosure names what was served (30b72ec0).
  - `--expand` lists up to 100 sibling names per body, where it listed 8 (3367d537).
  - `--handoff` shows up to 50 symbols per code file and 12 per prose file, where it showed 6. `--situ` lists every
    tests-to-run row, and `--doc-drift` and `--flags`/`--flip` page (#127).
  - `--help-task` no longer answers a "how does …" question with a symbol, and the MCP answer can carry `no_route`
    (#127).
  - A call inside a literal `#if 0` is no longer a call site, and graph verb roots carry `graph_unindexed=` (#72).
  - A `std::`-qualified C++ call no longer binds an in-repo definition outside namespace `std`. It counts toward
    `external=` instead, so `external=` reads higher (#134).
  - The map header can carry `declined=`, and `--callers`, `--callees` and `--impact` can carry `declined_calls=`
    (#136).
  - Cuts disclose themselves where they fire: `line_bytes=` on long matched lines, `…` on cut signatures,
    `budget_bytes="7500"` on a trimmed default `--for`, and cut markers on several listings (#100, #108). A cut
    `<calls>` listing keeps the callees ranked for the query (#95).
  - `--for --detail` says `over_ceiling="1"` when the answer passes `--max-tokens` (#77).
  - `--version` prints `emit=`, the formatted-output emitter the binary compiled in (88a5503b).
  - `--since`, `--merge-scout` and `--pr-context` refuse a revision that begins with `-` or does not resolve to a
    commit (#115, #116, #117).
  - A malformed `RIPWIRE_*` ranking calibration variable falls back to its default with one stderr line (#120).
  - `skills/install.sh --openclaw --hook` exits 2 instead of being silently ignored, and `--hermes --hook` is refused
    the same way (#51). `ripwire wrap claude` leads with the CLI (75ed8d3a).
  - `--hotspots` leaves functions flagged `extent_suspect=` out of its ranking and counts them in
    `unranked_extent_suspect=` (#135).
  - A file whose scanned sample holds invalid UTF-8 now reports a degraded parse (#126).
  - A budgeted `--for` that cannot fit its allowance takes the ladder's last rung and discloses the overflow, where it
    used to ship past the allowance silently, so a few already-over-budget bundles come out larger (3d98f84d).

### Added — Kotlin, with calls that cross into Java (parser version 91, cache format 20)

Kotlin (`.kt`) is indexed from a vendored `fwcd/tree-sitter-kotlin` grammar: classes, objects and companion objects,
functions, calls, imports and inheritance, with scope-qualified canonical ids and complexity scoring. A JVM interop
bridge in `graph.h`'s `langCompatible` resolves calls between Kotlin and Java in both directions. Contributed by
**@xCatG** ([#126](https://github.com/redhat-et/ripwire/pull/126)).

- **A disclosure hole closed on the way.** File health never validated UTF-8 on the sample it scans, so a file with
  invalid UTF-8 but no tree-sitter `ERROR` or `MISSING` node reported no degraded parse at all, and `--skipped`'s
  disclosure had a hole. The same sample is now checked with the existing UTF-8 validator.
- **Checked.** `test/kotlincheck.sh` runs a fixture with calls in both directions between Kotlin and Java, a constructed
  same-name collision pair (including an `enum class` and a plain class), cross-file calls and imports, with every number
  pinned from a real run and mutation arms. The contributor found no ASan, UBSan or LSan report across 501 real `.kt`
  files from 8 Android/JVM repositories, a 41-file adversarial corpus (merge-conflict markers, mid-edit fragments,
  invalid UTF-8, Unicode, emoji and RTL identifiers, deep nesting), and about 9,500 more `.kt` files across nowinandroid,
  compose-samples, architecture-samples, ktor and Signal-Android. Output was deterministic and well-formed on every one.

### Added — Dart, the 23rd grammar (parser version 88)

Dart (`.dart`) is indexed as a first-class language: definitions, call edges and metrics, from a vendored
tree-sitter-dart grammar. Contributed by **@calvinchengx** ([#75](https://github.com/redhat-et/ripwire/pull/75)), landed
in [#106](https://github.com/redhat-et/ripwire/pull/106) with four maintainer commits on top. On flutter/packages (3,706
`.dart` files) it indexes 71,726 Dart symbols, and none of that corpus's 289 degraded parses is a `.dart` file. The
binaries before and after produce identical bytes on `src/` and on a 1,406-file multi-language corpus, so no other
language moves.

**The tree shape is why this is more than a table row.** tree-sitter-dart makes `function_body` a *sibling* of the
signature, never a child. A definition's span therefore stopped at the signature's closing paren, and every call in the
body was attributed to the nearest enclosing symbol. On the gate's fixture that meant 5 edges where 8 are expected, a
method's call landing on its class, and three top-level edges gone. The Dart arm adopts the following body for the byte
extent, the row extent and complexity. The call query is adapted from upstream rather than copied, so the cascade
`this..add(1)..reset()` is two call edges and the receiver is not one.

**A latent bug it exposed, fixed for every language.** Six per-language arrays took their extent from the last
enumerator written out by hand (`std::size_t( Lang::Elixir ) + 1`) instead of `kLangCount`, so appending a language
dropped it silently. With the two `--skipped` tallies reverted, a corpus of two `.cpp` and two `.dart` files prints
`indexed="4"` and a single `cpp` row, and nothing says a row is missing. The same landing registered Dart in two more
places where the honesty contract applies:
- `--nonlocal-state` had printed no `unanalyzed_langs=` on a corpus that was half Dart;
- `--lint` printed `count="1"` beside `applicable="0"` on naming rules that do fire on Dart names.

**Stated floors.**
- Named constructors and factories index under the class name, so a `C.seeded(1)` call site is unresolved rather than
  wrong.
- `noSuchMethod` dispatch names its callee at run time and is not an edge.
- `part` / `part of` is not resolved.

ASan/UBSan is clean over a 6,554-file Dart corpus, and a libFuzzer run of 109,431 executions produced no crash, leak or
timeout. Gate: `test/dartcheck.sh`, red against a pre-Dart binary and against a binary with the span arm alone disabled.

### Added — initial Hermes and OpenClaw support

`skills/install.sh` gains `--hermes` and `--openclaw`, and `ripwire wrap` prints a setup recipe for `hermes` and
`openclaw`. **This is initial support.** CI checks what the installers write on disk. For Hermes, **@ashutoshsinghpr7**
also ran the installer and the MCP registration against a real Hermes install when support landed; the maintainers have
not re-verified it since. OpenClaw has not been verified against a real install. If you use either,
[#69 (Hermes)](https://github.com/redhat-et/ripwire/issues/69) and
[#68 (OpenClaw)](https://github.com/redhat-et/ripwire/issues/68) ask for exactly that check.

**Hermes.**
- **Install.** `--hermes` deploys 17 skills into `${HERMES_HOME:-~/.hermes}/skills`: the 16 flat user-facing skills,
  plus the Hermes-native `ripwire-repo-map` skill from `skills/hermes/`. The release one-liner activates them when that
  home exists.
- **MCP.** `ripwire wrap hermes` prints the `hermes mcp add` registration. In the live run it connected and discovered
  31 tools.
- **No hook yet.** `--hermes --hook` is refused with exit 2. Hermes has a `pre_tool_call` slot, but ripwire's nudge hook
  still switches on Claude Code's tool names, so the installer says the port has not landed instead of printing a hook
  line it cannot honour.
- **Credit.** The installer mode, the release-installer branch and the `wrap` recipe are **@AnkitArya**'s
  ([#51](https://github.com/redhat-et/ripwire/pull/51)). They landed in
  [#76](https://github.com/redhat-et/ripwire/pull/76), which adds a gate arm checking that `wrap hermes` names the flag and
  directory the installer really uses. The Hermes-native skill is **@ashutoshsinghpr7**'s
  ([#46](https://github.com/redhat-et/ripwire/pull/46)), as is the widening of both skill-vetting sweeps so that a skill
  in a subdirectory cannot escape them.

**OpenClaw.** Agent support in `src/wrap.h` used to live in five hand-maintained lists that nothing forced to agree. It
is now one table, `kAgentTargets`, and OpenClaw is a row in it
([75ed8d3a](https://github.com/redhat-et/ripwire/commit/75ed8d3ac9e155618acf6317aa88a084e4f207b5)). Dispatch, usage
text, the skills line, `--all` detection and the README block all read from that table.
- **Skills root.** OpenClaw's is `~/.agents/skills`, which it reads only while its state directory is the default
  `~/.openclaw`. The recipe prints that caveat.
- **Context file.** It is `~/.openclaw/workspace/AGENTS.md`, not the repository's `AGENTS.md`.
- **No hook.** OpenClaw has no shell hook slot, so `--openclaw --hook` is now refused with exit 2 instead of being
  silently ignored ([#51](https://github.com/redhat-et/ripwire/pull/51)).
- **`wrap claude` changed too:** it now leads with the CLI, as `codex` and `opencode` do.
- **Gate.** `test/agenttablecheck.sh` iterates the table, so the next row is covered without editing the gate.

How to install and remove both is in `INSTALL.md` ([#121](https://github.com/redhat-et/ripwire/pull/121)).

### Added — derailed C-family parses disclose their guesses (`extent_suspect=`), and a member-macro re-parse repairs the commonest derailment (parser version 90, cache format 20)

**The problem.** A function-like macro invoked without `;` as the last member of a class or struct, such as
`EXC_NAME(Foo)` right before `};`, sends tree-sitter-cpp's error recovery off course. The earlier structs dissolve into
an ERROR region, and the last struct's body swallows what follows. The same shape derails tree-sitter-c and
tree-sitter-objc. On memgraph, one file had 472 of its 487 definitions misfiled. A 14-line function,
`PrintFuncSignature`, was reported with `cx=749 ccx=920` and ranked #4 in `--hotspots`, and nothing on the row said
anything was wrong.

**The detector.** `src/extentsuspect.h` makes one linear pass per file over spans that are already sorted. A definition
a derailed parse filed in the wrong place carries `extent_suspect=`, naming the rules that fired:
- `name`: a name outside its own definition's signature;
- `head` (C family): a definition in another definition's return-type position, before its name;
- `scope` (C++): filed under `C::` while lying inside a different class;
- `error`: a class whose body holds an error inside an ERROR region, and what it contains.

Map, `--for`, `--expand` and `--json` rows carry the attribute. The header carries `extent_suspect_syms=`, and
`--skipped` gets per-file rows plus `extent_suspect_files=`. Each is absent at zero, and its legend line appears only on
output that carries it. `--hotspots` leaves flagged functions out of its ranking instead of ranking a number the tool
itself calls an artifact. It says so with `extent_suspect_syms=` on the row and a fourth partition bucket,
`unranked_extent_suspect=`, so the partition still sums to `files=`.

**The re-parse.** `src/macroreparse.h` touches only a C, C++ (including CUDA and Metal) or ObjC file whose first parse
holds error bytes. It blanks ALL-CAPS function-like macro invocations that sit alone on a line as class, struct or union
members, keeping newlines and byte offsets. It re-parses the blanked text and adopts the new tree only if that tree holds
strictly fewer error bytes. A blanked invocation stays a `role=type` use of the macro name, so `--uses` is unchanged.
Disclosure: `why=macro-blanked` and `macro_blanked=N` on the `--skipped` row, and `macro_blanked_files=` on the map,
`--json` and `--skipped` headers, absent at zero.

**Measured** on memgraph, main `096e3544` against the change:

| | before | after |
| --- | --- | --- |
| `PrintFuncSignature` | a method, `cx=749 ccx=920 loc=5479` | a free function, `cx=3 ccx=2 loc=15` |
| `mg_procedure_impl.cpp` in `--hotspots` | ccx 1871, top function 920 | ccx 960, top function 40, 0 flagged |
| degraded-parse files | 307 | 289 |
| extent-suspect definitions | — (no detector) | 241 in 9 files (detector alone: 1,613 in 31) |
| re-parsed files | — | 24 |
| cold CPU, 5 alternating runs | 8.114 s | 8.108 s |

On an llvm-project checkout, extent-suspect definitions go from 1,650 to 1,483, and 24 files are re-parsed. A file that
is not re-parsed keeps every definition, scope and complexity; only graph knock-on effects, such as caller counts and
rank, move.

**Limits, stated.**
- Only the ALL-CAPS class-body shape is repaired. Lowercase and namespace-scope macro runs still derail, and the detector
  keeps flagging them: on memgraph 241 flags remain, 93 of them in `eval.hpp`.
- A partial repair is still adopted when it holds fewer error bytes. `err=` describes the adopted parse, so it can rise
  while `err_ratio` falls: on `mg_procedure_impl.cpp` it goes from 1 to 50 nodes while error bytes fall from 271,971 to
  376.
- `--match`, `--lint` and `--slice` parse files themselves, so they still see the first parse.
- The `name` and `scope` rules have no real-world trigger today; they are guards, pinned by unit cases.
- This repository's own map always carries the new legend lines, because the fixtures live in the tree (about +430
  `est_tokens` on ripwire itself). Corpora with nothing flagged are unaffected.

`kParserVer` goes 88 → 90 and `kCacheVersion` 18 → 20, because the per-file cache record gains a field. Gates:
`test/extentcheck.sh` (55 checks) and `test/macroreparsecheck.sh` (103 checks), both red on their pre-change binaries
([#135](https://github.com/redhat-et/ripwire/pull/135)).

### Added — `INSTALL.md`: every install route, and how to remove all of it

A new `INSTALL.md` gathers every way to install ripwire:
- the prebuilt one-liner and its variables;
- building from source, and `./install.sh`;
- activating skills for Claude Code, Codex, Hermes, OpenClaw or any directory;
- the optional advisory hooks;
- the MCP server via `ripwire wrap <agent>`;
- checking and upgrading.

It ends with how to uninstall, which **@luisdavim** asked for in
[#111](https://github.com/redhat-et/ripwire/issues/111). The uninstall section covers:
- the binary and staged files;
- the `ripwire-*` skill links;
- ripwire's hook entries;
- MCP registrations, per agent;
- pasted rules blocks;
- the cache;
- the per-repository files ripwire writes only on request.

Every path comes from the code. The uninstall snippets were extracted from the page itself and run against a sandboxed
`HOME` with synthetic installs, and all 15 checks passed. They cover both what must be removed and what must be kept,
such as an unrelated binary, another tool's hook and non-hook settings keys. A `.bak` is written before each config edit,
and a second run is a no-op ([#121](https://github.com/redhat-et/ripwire/pull/121)).

### Added — `--help` in two tiers: one line per flag, every disclosure one call away

`--help` now prints one line per row, saying what exists and roughly what it does, in **4,473 tokens instead of
46,385** (10.4×). Nothing is deleted:
- `--help=<flag>` returns that row's every disclosure;
- `--help=<section>` returns one family at full detail;
- `--help=all` returns the whole catalog exactly as before.

The evidence made this a split rather than a trim. A third-party evaluation (callstack/agent-device #2400) measured
ripwire spending about 10% more tokens than grep-and-read and traced the cost to the per-call legend. The fix,
`--legend=compact`, was already documented, but 92% of the way down a 1,597-line document. Asking for the one row that
answers a question now costs 90 tokens. `test/helpbudgetcheck.sh` holds tier 1 to a token ceiling and proves every
advertised row is still retrievable from tier 2, so the ceiling cannot be met by deleting content
([#92](https://github.com/redhat-et/ripwire/pull/92)). Before the split, the `--legend` entry was rewritten to lead with
what the full legend costs, a fixed ~3 KB, and `test/legendcostcheck.sh` reads that floor out of `--help` and measures
against it ([8c20e108](https://github.com/redhat-et/ripwire/commit/8c20e108)).

### Added — `.rst`, `.adoc`, `.org` and `.mdx` reach `--recall` (parser version 85)

These extensions were not indexed at all, so a `--recall` over a repository that documents itself in reStructuredText
or AsciiDoc returned nothing and, correctly but unhelpfully, said zero. They now reach `--recall`, `--for` and
`--handoff` on the markdown grammar tier. Gate: `test/textdocscheck.sh`
([#80](https://github.com/redhat-et/ripwire/pull/80)).

### Changed — `--recall` serves ranked passages, not document prefixes

`--recall` scored a document's markdown sections by relevance, then put them back in document order and let the byte
budget cut from the front. On a document larger than its share of the budget, the best section could be unreachable at
every ceiling: on a 616 KB `docs/COMMANDS.md`, the `--field-affinity` section at line 3570 of 4755 ranked #1 and was
served at none of 1,500, 4,000, 12,000 or 40,000 tokens, while the table of contents at the front of the file was.
Sections are now own-prose units that tile the document, the allowance is spent in rank order one whole unit at a time,
and the disclosure reports what was served: `[sections: S of R selected (N in doc) ... dropped_by_budget=D]`, with
`lines=` naming exactly the ranges in the body. An enclosing section no longer outranks the subsection that holds the
answer, because a unit's score is scaled by its own-prose evidence over the strongest own-prose evidence in its subtree.

Measured on a frozen 1.88 MB corpus: answer reachability went from 5 of 14 to 9 of 14, natural-language-first from 43
to 79 at 1,600 tokens, and query-term coverage rose by 58, 56 and 40 at 4,000, 8,000 and 16,000 tokens. Budget
monotonicity holds within a document over 1,380 ceilings with 0 shrinks, but not across documents, and the surfaces
that claimed otherwise now say so. Gate: `test/recallpassagecheck.sh`, written before the fix
([30b72ec0](https://github.com/redhat-et/ripwire/commit/30b72ec0)).

### Changed — one header of SIMD string kernels, and the quadratic child walks gone

For every invocation below, output is byte-identical before and after; the verbs whose output this round changes on
purpose are in their own entries. Main's binary (source `9356cf23`) was measured against the merged tip of the round,
with the same argv and interleaved arms. CPU is user+sys, the median over n pairs, on a shared machine at load 7–14:

| corpus | invocation | before (CPU s) | after (CPU s) | Δ median | n |
| --- | --- | ---: | ---: | ---: | ---: |
| llvm-project | cold map `--no-cache` | 194.14 | 155.60 | −19.9% | 1 |
| go | warm `--pack-task` | 8.13 | 5.88 | −27.6% | 5 |
| go | warm `--lint` | 18.43 | 15.18 | −17.7% | 5 |
| rocksdb | warm `--lint` | 6.77 | 5.60 | −17.3% | 5 |
| rocksdb | warm `--pack-task` | 0.68 | 0.60 | −10.9% | 5 |
| rocksdb | cold map `--no-cache` | 7.96 | 7.42 | −6.7% | 5 |
| ripwire (own tree) | warm `--pack-task` | 0.45 | 0.38 | −15.5% | 5 |
| ripwire (own tree) | warm `--lint` | 4.21 | 3.91 | −7.3% | 5 |

A warm map, `--for` and `--grep` are within noise; their floors are the serial resolve loop and file opens.

**The O(C²) child walks.** An indexed child walk over a tree-sitter node restarts the vendored iterator on every call, so
the loop is quadratic in the number of children. It only bites on wide, flat child lists, which C/C++ include guards
and comment floods produce, which is why the llvm-project cold parse moved most. `collectPreprocDeadRanges` and the other
23 quadratic walks move to one cursor helper, `src/infra/tschildren.h`, with 18 isolation arms proven red first at
11–125× ([#127](https://github.com/redhat-et/ripwire/pull/127)). [#130](https://github.com/redhat-et/ripwire/pull/130)
converts 22 more, each proven quadratic on the pre-change binary first at 13×–126× its control under a 16,000-comment
flood. Three loops stay indexed, with the reason written at the loop, and 156 generated fixture × verb pairs plus the 21
committed ones are byte-identical.

**One header of string kernels.** `src/infra/strkern.h` holds nibble-table byte classification, an A–Z fold, and byte,
byte-set and 3-byte finds, each with a NEON path, an AVX2 path and a scalar twin. The query tokenizer is rewritten on it
as mask algebra, proven against verbatim copies of the old walkers, beside a BM25 head-mask index; that is the
`--pack-task` row. The XML and JSON escapers copy clean runs between the bytes a 256-bit set finds (escaper share 4.6% →
2.0% and 6.3% → 2.6%). A SIMD scan for `--grep` was measured and refused: that verb is bound by file opens, and the scan
is 0.4% of busy samples.

**Lookups hoisted out of the per-node path.** 199 `ts_node_child_by_field_name` sites now read a per-grammar `TSFieldId`
table, checked on 1,189,205 enumerated (node, field) pairs. The `#match?` predicate's regex is compiled once per query,
not once per match, which is the `--lint` row.

The techniques are credited in `docs/LINEAGE.md`, which now folds 49 repositories and 70 papers, among them Langdale &
Lemire (VLDB J. 2019) for nibble-table classification, Daniel Lemire's 2023-07-13 blog code, StringZilla and Tempesta
fast_str. The kernel tests are a doctest target, `ripwire_test_strkern`.

### Changed — `--quality-delta` dials each kind separately

On 12 landed commits, `--quality-delta` had gated all 12, with a true-positive share of 2%. Each kind now has its own
rule:
- `churn="self"` is informational; what gates is two committed rewrites inside the window.
- Dead-code sees header files, where 96.8% of this repository's `src/` lines live, and excludes language-invoked symbols
  instead.
- Verbosity counts code lines.
- Complexity and verbosity gate on a threshold crossing or on growth of at least 25%.
- New api-surface symbols become a count, `api-new-surface=`.

On the same 12 commits, gating went from 12 of 12 to 8 of 12, the true-positive share rose from 2% to 12% with 0 wrong
rows, and the synthetic regressions caught rose from 5 to 7. The legend gains the `api-new-surface=` count and the churn
facets' gating rule ([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Changed — `--handoff` shows more, and three listing verbs page instead of cutting

Caps are blow-up guards on the way to one complete answer, and none of this lowers a value to shrink a byte count.
- **`--handoff`** shows up to 50 symbols per code file and 12 per prose file, where it showed 6. Containment rises from
  16% to 54%, and the change only adds rows.
- **`--doc-drift`, `--flags`/`--flip` and `--situ`** disclose their cuts and page. Answer rows never page, so `--situ`'s
  25-row cap on tests-to-run is retired: every row is listed, and no cut is disclosed because none is made. The gate has
  33 checks, 24 of them red before the change.
- **The cap sweep was re-derived** once six honesty defects in its harness were fixed: 64 of 151 answering rows, where
  59 of 195 had been published ([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Changed — `--expand` lists up to 100 sibling names, and every cap is listed in `docs/LIMITS.md`

A body's `sibs=` list on `--expand` was capped at 8 names. On this repository the median file holds 4 symbols but p99
holds 85, and symbols concentrate in large files, so the cap fired on 68.5% of bodies and hid 89.3% of sibling names. The
cap is now 100, above p99: 15.8% of bodies are cut, 56.2% of sibling names are visible where 10.7% were, and a
single-symbol `--expand` answer grows 36%. `sibs=` reaches only `--expand`, so `--for` and `--pack-task` are
byte-identical at every cap value tested. The README's `--pack-signatures` figure moves as a consequence (top-50 71.0% →
81.8%), because `--expand`'s bodies are that ratio's denominator; the cap was chosen on recall grounds and the figure
re-derived afterwards ([3367d537](https://github.com/redhat-et/ripwire/commit/3367d537)).

That cap is why caps now have an inventory. `docs/LIMITS.md` lists every cap in `src/` with its value, its site and
whether its file discloses a cut when it fires. It is generated by `docs/limits_build.py`, and `test/limitstablecheck.sh`
fails when it drifts. It began at 120 caps across 51 files (3367d537).
[#108](https://github.com/redhat-et/ripwire/pull/108) added the INDEXING/OUTPUT column, the hyperparameter register,
`docs/TUNING.md` and the `bench/capsweep` harness. [#123](https://github.com/redhat-et/ripwire/pull/123) pins each cap by
what it is rather than the line it sits on, so a comment above a cap no longer reddens CI.
[#127](https://github.com/redhat-et/ripwire/pull/127) adds a BOUNDARY class, and
[#128](https://github.com/redhat-et/ripwire/pull/128) gives the per-file tables their own `## Caps, by file` heading;
they had been filed under "Not caps". On main the register counts 208 caps across 83 files.

### Changed — faster ingest and graph building: the per-node dispatch, the include closure, three loop hoists

These build on the cone memo in the Fixed entries below. Every result here is an interleaved A/B, and output is
byte-identical before and after.

**The per-AST-node `strcmp` dispatch goes inline.** The ingest walk chooses a branch with chains of about forty
`std::strcmp` calls against `ts_node_type()`, once per AST node. `strcmp` is an external symbol that LTO cannot inline,
and on macOS each call also hops two dyld stubs. Sized before any change, `strcmp` was this share of busy samples:

| corpus | `strcmp` share of busy samples |
| --- | --- |
| rust-analyzer | 12.31% |
| go | 10.76% |
| llvm-project | 10.56% |
| django | 9.31% |
| rails | 6.14% |

`rw::kindIs` (`src/infra/nodekind.h`) is the same compare, unrolled inline against a literal, and it replaces `strcmp` at
569 call sites. On llvm-project `strcmp` is now 0.23% of busy samples.
- **Why not SIMD.** On llvm-project, 92.96% of 4,861,917,534 compares decide at byte 0, and clang compiles the chain to a
  shared-prefix decision tree that uses no vector registers.
- **The claim.** As a range over llvm-project, django, go and this repository: **cold CPU 1–7% lower, cold wall 0.3–8%
  lower**, with all 32 statistics in the same direction.
- **Same output.** Byte-identical on seven corpora. `test/argvdiffcheck.sh` finds 640 of 642 vectors identical; the
  other two differ only in `--version`'s `built_from=`.
- **Gate.** `test/nodekindcheck.sh` checks `kindIs` against `strcmp` on 1,348,096 enumerated pairs, and uses a guard page
  to catch any read past the NUL ([#107](https://github.com/redhat-et/ripwire/pull/107)).

**The include closure's sort goes radix, above 128 elements.** On rails, 38.7 ms of the ~62 ms transitive include
closure (`buildGraph/2b`) was one `std::sort`. With radix above a crossover of 128:

| on rails | before | after |
| --- | --- | --- |
| `buildGraph/2b` | 65.21 ms | 35.01 ms (−46%) |
| `buildGraph` | 223.0 ms | 186.7 ms (−16%) |
| whole `--callers=main` run | | 7.8% and 8.5% faster at the median, two independent A/Bs |

Five control corpora stay within ±1.7%. The threshold is what makes the change safe: without it, the same conversion
regresses django 7.9×, a private C++ tree 7.7× and rust-analyzer 4.7×. Three more sites were refused with numbers.
django's `implementors` would be 2.87× slower, because its records arrive already sorted, which `std::sort` detects and
radix cannot. A `std::unique` that removed 0 duplicates in 24,216 calls is gone
([#97](https://github.com/redhat-et/ripwire/pull/97)).

**Three loop hoists; two candidates refuted.**
- The CHA-lite ancestor closure is memoised: −13.2% warm on rust-analyzer.
- `lexicalNormalize` builds one string: −6.0% on rails.
- The shadow guard asks its cheap question first: −26% on that phase.

A candidate-spray optimisation was 53% of scan volume and 0% of wall, so it was not built, and another candidate
measured inside the noise. After the cone fix, no single phase dominates on any corpus, and which phase is largest
depends on the corpus's language. `bench/PROFILE.md` carries the six-corpus table
([#96](https://github.com/redhat-et/ripwire/pull/96)).

**timsort is vendored and routed nowhere.** It was measured against `std::sort`, radix, pdqsort, an `is_sorted` guard and
`std::stable_sort`, on the real id sets of three call sites across seven corpora, and was not recommended for any of
them:
- on presorted input, a three-line `is_sorted` guard measured 0.35× where timsort measured 0.58×;
- on scattered input, timsort measured 1.71×, 6.0× slower than radix.

It ships in `src/infra/` for parity with the portable layer it belongs to. The measurement is in its header, and a gate
checks that no call site uses it ([#93](https://github.com/redhat-et/ripwire/pull/93)).

### Changed — `est_tokens` measured against a real tokenizer

`est_tokens` had been checked for being present, positive and deterministic, but never for being accurate. It is now
measured: 25 invocations on 2 corpora, counted with `o200k_base` and `cl100k_base`, which agree to within 1.4%. Three
findings are published in `docs/EVALS.md`:

- **Only 9 of 25 invocations print a price at all.** The sixteen that do not include every navigation verb. One
  `--edit-check` emitted 99,006 real tokens priced at nothing.
- **The signed error runs −18.4% to +41.7%**, with a median of +16–18%. It follows document shape, not corpus language:
  real bytes per token run from 2.44 on dense signature rows to 4.66 on legend prose. So no extra `kTokenCalib` row can
  fix it.
- **`--token-budget=N` delivers 48–82% of N.** The budget is a ceiling on the estimate, and at binding budgets the
  estimate over-reads by 25–42%.

`kTokenCalib` is unchanged on purpose. A single rate cannot correct a +40% bundle and a −16% body at once, and the
per-span charge that could is a change of its own. What landed is the instrument for that change:
`test/tokenbudgetcheck.sh` #18 holds every pinned invocation inside a measured band and the set's error under a 30%
ceiling. A comment in `src/serialize.h` saying the estimate "never systematically under-reads" was false on two corpora
and is gone. `--legend=compact` is a wash or a small loss on `--for`, whose budget refills the bytes the legend frees
([#79](https://github.com/redhat-et/ripwire/pull/79)).

### Changed — one emitter for formatted output, and `--version` says which one it compiled in

`src/infra/emit.h` is now the one place the formatted-output path is chosen: `std::print` where the standard library
defines `__cpp_lib_print` (libstdc++ 14 and later; libc++ at a macOS 14 or later deployment target), and `std::format`
plus `fputs` where it does not, so every toolchain still builds. `--version` prints the choice as `emit=`, and every CI
and release leg asserts `emit=std::print` off the binary it built. Behind it, `src/` no longer holds a single
`std::printf`, `std::fprintf`, `std::snprintf` or `std::sprintf` call site: 1,526 became 0, converted in batches against
a byte-parity fence that was widened before anything was converted
([88a5503b](https://github.com/redhat-et/ripwire/commit/88a5503b),
[25d901cd](https://github.com/redhat-et/ripwire/commit/25d901cd)).

### Changed — Shotgun Surgery is named where ripwire already measures it

Fowler's Shotgun Surgery, one change that touches many modules, has two measurable forms. The historical one is change
coupling, which `--cochange` mines and `--situ` and `--pr-context` turn into a check; the name now appears on the
`--cochange` and `--situ` help entries, the MCP `cochange` and `situational_awareness` descriptions, the README and four
skills. The static one, Lanza & Marinescu's CM×CC detection strategy, was prototyped on the call graph on two corpora and
not built: its top flags were stable hubs, and per-file static fan-in tracked how widely edits actually scatter at
Spearman +0.158 and +0.163. The shipped `--situ` co-change rule, backtested against prior history only, scores
precision@8 of 0.352 and 0.427 on the same two corpora. The tables are in `docs/EVALS.md` and re-derive from
`bench/shotgun/` ([8dfd7380](https://github.com/redhat-et/ripwire/commit/8dfd7380)).

### Changed — skill descriptions get their routing triggers and stop rules back

Six skill descriptions get back discovery triggers that had been cut to fit a 320-character per-description ceiling, and
four one-sentence stop rules return to the frontmatter. The 320 was a design number, not a client limit: Codex rejects a
description over 1,024 characters, and Claude Code caps an entry at 1,536. `test/skilldescbudgetcheck.sh` now fails only
a description over 1,024 characters and keeps the 5,400-character ceiling on the set
([#112](https://github.com/redhat-et/ripwire/pull/112)).

The quality-bar description also stops promising that `--quality-delta` "exits non-zero on new debt". Exit 2 fires only
when pre-existing code got materially worse, and new-symbol rows never gate, so a clean exit is not a verdict on new code
([#114](https://github.com/redhat-et/ripwire/pull/114)).

### Changed — the README and the docs

- **The goal.** The README states what the tool is for: one question, one complete answer, with honest limits and token
  budgets as the two stair-steps toward it. It is worded so it does not promise a hard cap the tool deliberately exceeds
  with `over_ceiling="1"` ([#88](https://github.com/redhat-et/ripwire/pull/88)).
- **The top of the page.** It leads with what a stranger can check in ten seconds. The four negations are a local badge,
  `docs/assets/no-deps.svg`, rather than images fetched from a badge service. The H1 says "Fewer Tokens", and the tagline
  under it is bold text rather than a second heading. The hero keeps the Trendshift badge; the paddle-out wave moves to
  the presentation deck ([#82](https://github.com/redhat-et/ripwire/pull/82),
  [#90](https://github.com/redhat-et/ripwire/pull/90), [#103](https://github.com/redhat-et/ripwire/pull/103),
  [#113](https://github.com/redhat-et/ripwire/pull/113), [#119](https://github.com/redhat-et/ripwire/pull/119),
  [#133](https://github.com/redhat-et/ripwire/pull/133)).
- **The banner** reads "shaped in '76, finned last month, every guess says how many it chose from, see the rip before
  you're in it", and ends on "Paddle out with a map." The lineage line claims both halves of the ledger: fifty years of
  software-engineering results, and research from last month. The 5.0% token row now carries the strict-satisfaction
  caveat beside it instead of 1,150 lines away, and `test/readmedriftcheck.sh` arm (H) holds the lineage summary's counts
  to the ledger (ca3ce335, ef6168b1, a46a514d, 61d84eef, 441e35cf, 64c81d47).
- **The task example's 4.3K figure** is described as what one run produced, not an enforced budget, since the example
  passes no budget flag. Contributed by **@PollyBot13** ([#54](https://github.com/redhat-et/ripwire/pull/54)).
- **The lineage ledger** gains three rows (tgrep, codeburn, markitdown), going from 43 to 46 repositories, with a gate
  arm requiring every copy of that count in the README to agree ([#86](https://github.com/redhat-et/ripwire/pull/86)). The
  string-kernel credits in #127 take it to 49 repositories and 70 papers.
- **The head-to-head tables say what they predate.** An italic note beside both Round 4 tables records that they were
  measured on 2026-08-08, before the performance work that ships in 0.6.0, and names two of the figures that have moved
  since: llvm-project's cold parse, on 182,555 files, from 194.1 s to 155.6 s of CPU, and `--pack-task` on a Go
  repository from 8.13 s to 5.88 s. No number in the tables changes; they still show what was measured that day
  ([#141](https://github.com/redhat-et/ripwire/pull/141)).
- **The README links `INSTALL.md` again.** The sentence under the quick-install block naming every install route was
  lost when #127's merge took a branch side that predated it, and main had not linked the page since. It goes back in
  the same place ([#141](https://github.com/redhat-et/ripwire/pull/141)).
- **Adding a language, for contributors.** `prompts/add-a-language.md` is derived from the diff of the Elixir landing
  rather than from memory. It starts by measuring the parse rate on a real corpus before any code is written, and it ends
  with the traps earlier PRs actually hit (7780e4d3, d582d0de).
- **Three places where the docs contradicted the repository** ([#131](https://github.com/redhat-et/ripwire/pull/131)):
  - `THIRD_PARTY.md` gains the MIT attribution row the vendored `tree-sitter-markdown` shipped without, and a gate arm
    now derives the required rows from the directories under `third_party/deps/`;
  - `INSTALL.md` says Hermes was run live by a contributor when it landed, and OpenClaw has not been;
  - `docs/ARCHITECTURE.md` said PageRank's power iteration is parallelized; it is single-threaded, and its fixed row
    blocks exist for determinism, not parallelism.

### Changed — CI, the gate harness and internals, with no change to output

None of this changes the binary's output.

**CI.**
- macOS legs shard four ways like every other leg, which halves the gates per macOS job. A run grows from 26 checks to
  30 ([#110](https://github.com/redhat-et/ripwire/pull/110)).
- The HEAD comparison binary is built once per job, in its own step, never inside a gate's time budget, where a parallel
  `cmake` build under contention had been killed at 900 s and again at 1200 s
  ([#118](https://github.com/redhat-et/ripwire/pull/118)).
- A declared gate budget is now a floor. Under CI's 4× budget scale, 15 of 18 declared budgets had been smaller than what
  an undeclared gate got ([#109](https://github.com/redhat-et/ripwire/pull/109)).
- Every non-Ubuntu apt source is removed before `apt-get update`, after a vendor source took down every Linux leg for the
  second time ([#99](https://github.com/redhat-et/ripwire/pull/99)).
- The advisory clang-tidy step lints a real parse. `version.h` was not generated before it ran, so the translation unit
  that includes nearly every header failed to parse and 64 diagnostics were hidden. One of them is the file-handle leak
  fixed below ([#120](https://github.com/redhat-et/ripwire/pull/120)).
- Its `bugprone-easily-swappable-parameters` options are set to reveal rather than silence: of the 209 rows the check
  reports at upstream defaults, 208 are genuine, and the two options add 18 more genuine rows while silencing none
  ([#124](https://github.com/redhat-et/ripwire/pull/124)). Eight of the flagged functions, among them the whole-file
  readers, then stop filling an out-parameter and return what they produce; the flagged sites drop from 237 to 229, and a
  36-case byte-for-byte differential is identical ([#132](https://github.com/redhat-et/ripwire/pull/132)).
- `test/*.sh` is marked `linguist-detectable=false`. The gate scripts had come within 5% of the C++ source's byte count
  (8,921,478 against 9,398,027), and a few dozen more gates would have relabelled the repository's language as Shell
  ([f2589419](https://github.com/redhat-et/ripwire/commit/f2589419)).

**The gate harness.**
- The published gate count is generated from `test/regression.sh` by `docs/gatecount_build.py`. Two lanes that each add a
  gate both write N+1, and git merges that cleanly against a loop of N+2; it collided seven times in one night
  ([#104](https://github.com/redhat-et/ripwire/pull/104)).
- `test/pargates.py` watches the checkout while gates run. It samples `git status` every 0.25 s and fails the run on any
  new file a gate leaves in the tree, naming the gates in flight, and it says the count is a floor. A transient probe file
  had been flipping stamped determinism arms by marking builds `+dirty`; the writer is fixed, and `CONTRIBUTING.md` states
  the rule ([4c10be9d](https://github.com/redhat-et/ripwire/commit/4c10be9d)).
- Gates run with `PYTHONDONTWRITEBYTECODE=1`. A gitignored `__pycache__/` had changed what the crawl counts
  (`corpus_pruned_dirs=` 3 → 4), which made a paging gate nondeterministic
  ([#122](https://github.com/redhat-et/ripwire/pull/122)).
- Gates check out commits as private shared clones rather than with `git worktree add`, so a gate killed with SIGKILL
  leaves nothing registered in the shared `.git` ([#125](https://github.com/redhat-et/ripwire/pull/125)).
- A timed-out gate is stopped whole. `test/pargates.py` used to SIGKILL only the gate's `bash`, and 5 of 6 probe processes
  outlived the timeout. Each gate now leads its own process group, which gets TERM and then KILL after a 10 s grace, and a
  Ctrl-C or SIGTERM to pargates stops every running gate the same way
  ([#129](https://github.com/redhat-et/ripwire/pull/129)).
- The installer gates clear inherited agent-home variables before setting up their fixtures, so a gate run from inside an
  agent session no longer writes into that agent's real home. Contributed by **@PollyBot13** (#55, landed as fed2e2b1 and
  d05af44e, with a5c95aa6 on top); `test/agenttablecheck.sh` got the same fix for `XDG_CONFIG_HOME` (1fdf70d3).
- Four gates that could fail for reasons outside what they check now fail only as themselves: a gate whose command died
  no longer reports a missing feature ([#94](https://github.com/redhat-et/ripwire/pull/94)); a partition arm that ties
  skips with its numbers instead of failing (cb32e0dd); a truncated pipeline no longer reads as a missing attribute
  (321ee839); and the skill-eval sweep counts directories that contain a `SKILL.md`, not every directory under
  `skills/` (5e96a6a5).
- `scripts/optremarks.py --hot` covers the 14 headers the ingest split moved work into. It had been reading 0.20% of the
  ingest translation unit ([#98](https://github.com/redhat-et/ripwire/pull/98)).

### Fixed — the macOS x86-64 release binary is built for its own architecture

`cmake/PortableFlags.cmake` picked its flags from `CMAKE_SYSTEM_PROCESSOR`, which CMake takes from the build host. The
release job builds the macOS x86-64 binary on an arm64 runner, so every x86-64 compile line got `-mcpu=apple-m1` and no
`-march`. Releases through v0.5.0 therefore most likely shipped a baseline x86-64 macOS binary; no release log shows the
flags, so that is an inference. With the Xcode pinned after v0.5.0 the same flag is a hard compiler error, so the 0.6.0
macOS x86-64 job, and with it the whole release, would have failed.

Flags now follow `CMAKE_OSX_ARCHITECTURES` when it names exactly one architecture, so the macOS x86-64 binary gets
`-march=x86-64-v3` like Linux, and a build tree naming more than one architecture stops at configure ("ripwire builds one
architecture per build tree"). The job moves to a `macos-26` runner, whose Rosetta can run x86-64-v3 code for PGO
training, with Xcode 26.6 and `MACOSX_DEPLOYMENT_TARGET=14.0` pinned; without the pin the move would silently have raised
the minimum macOS to 26. A new release step reads `minos` back off the binary. Gates: `test/portablebuildcheck.sh` arms
#2d–#2h ([#137](https://github.com/redhat-et/ripwire/pull/137)).

### Fixed — the installer names an x86-64 CPU below v3 instead of reporting a version mismatch

On a CPU below x86-64-v3, `scripts/install.sh` downloaded the binary and ran `--version` to verify it; the binary died
with SIGILL inside a pipeline whose status came from `head`, and the user was told
`release vX contains ripwire <unknown> — refusing version mismatch`, which never names the requirement.
- **Before downloading**, on x86-64 and for 0.6.0 and later, the installer reads the CPU flags (`/proc/cpuinfo` on Linux,
  the `sysctl` feature keys on an Intel Mac). Below v3 it stops, lists the missing features and points to a source build
  with `./install.sh`, which builds for the local CPU. It never blocks when the flags cannot be read, under Rosetta, for
  0.5.x and older, or with `RIPWIRE_SKIP_CPU_CHECK=1`, which covers a VM that hides flags its host still executes.
- **After downloading**, the verification run's exit code is read. Exit 132 on x86-64 names the v3 requirement and the
  source-build route, and under Rosetta suggests a native arm64 shell. Any other failure, such as a glibc loader error,
  is shown with the binary's own output. "Version mismatch" is reported only when the binary ran and printed a different
  version.
- `INSTALL.md` states the requirement and the new variable. Gate: `test/releaseinstallcheck.sh` section G, 12 arms, five
  of them red on main ([#138](https://github.com/redhat-et/ripwire/pull/138)).

### Fixed — a `std::`-qualified C++ call binds only a definition inside namespace `std`

A call written `std::X(...)` bound to the repository's lone in-repo definition named `X`, at full confidence and with no
`amb=` or `prov=` marker. On memgraph, `SafeString::move` became map row #1 with 2,107 false callers from `std::move`. In
ripwire's own graph, `std::min`, `std::max` and `std::sort` bound `fastmath` and `svector` members.

A call whose written qualifier is `std`, `::std` or a standard-library inline ABI namespace (`__1 __2 __8 __Cr __cxx11
__ndk1`, tabled with sources in `src/externalnames.h`) now keeps only candidates scoped inside `std`. Otherwise it is
counted through the existing external path, `external=`, and gets no edge. Only an exact `qualifier::name` pin exempts a
site; include-based narrowing does not. Unqualified `move(x)`, ADL, using-directives and namespace aliases behave as
before, and the rule is deliberately not generalised to other qualifiers.

| `--no-cache` | before | after |
| --- | --- | --- |
| memgraph `--callers=SafeString::move` | 2,107 | 3 |
| memgraph edges / ambiguous / external | 177,280 / 39,771 / 7,404 | 174,787 / 39,606 / 12,370 |
| ripwire (main `096e3544`) edges / ambiguous / external | 20,857 / 7,626 / 1,003 | 20,413 / 7,528 / 2,498 |
| ripwire `--callers=min` / `max` / `sort` | 131 / 67 / 7 | 5 / 14 / 2 |

`unresolved=` and map wall time are unchanged. Of the three memgraph callers left, two are `SafeString` unit tests and one
is a `std::ranges::move`, the first gap below.

**Known gaps, disclosed.**
- Nested std namespaces (`std::ranges::`, `std::chrono::`) arrive as their last segment only, which cannot be told apart
  from a user namespace.
- In ObjC++, the grammar parses `std::move( x )` as an error node plus a bare `move( x )`, so the qualifier is gone before
  resolution. The gate pins this behaviour.
- A declaration-only `namespace std { void f(); }` would still receive edges. This is not gated.
- `external=` now also counts refused `std::` calls, so it reads higher than before.

No cache or parser version moves: the change is resolution-only, and a warm run on a cache written by the old binary
equals `--no-cache`. Gate: `test/stdqualcheck.sh`, 35 checks. On the pre-fix binary 19 fail, and the 16 that pass are
controls ([#134](https://github.com/redhat-et/ripwire/pull/134)).

### Fixed — the cache evicted its own working root, and every root minted two key families

One llvm-project root needs 1.76 GB of cache, and the cache sweep holds the whole cache to 2 GB. The sweep was evicting
that root's own rich blob, so a repeated same-argv `--for` on llvm-project took 274 s of CPU; with the blob kept it takes
26 s. Eviction now pins every family of the working root, and an eviction is disclosed on stderr only when one happens.
Separately, the lean/rich cache-key builder hashed the root with a truncated FNV basis while the git-metadata families
used the real one, so every root minted two key families. There is one root key for all seven families now, which is why
blobs from older builds are clean misses (see the upgrade notes) ([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Fixed — `--help-task` no longer answers "how does <word>" with a symbol

`--help-task` no longer mints a symbol from a "how does <word>…" question, and JSON keys never resolve as symbols.
Harmful recommendations fell from 13 of 25 to 0, and precision rose from 0.797 to 1.000. The skills' stop rules are gated
as present and load-bearing, the router names all 16 skills, and the MCP answer gains `no_route`
([#127](https://github.com/redhat-et/ripwire/pull/127)).

### Fixed — the confident zero: three outside reports, three causes (cache format 18)

Three reports filed on 2026-09-08 described one symptom: a number that reads as authoritative and is not. They turned out
to have three causes, so each got its own fix. A single "blind spot" attribute would have been a false claim on two of
the three.

- **Callers in a file no grammar reads gave `count="0"`, undisclosed.** Reported by **@snrmwg**
  ([#66](https://github.com/redhat-et/ripwire/issues/66)). Every graph verb's root now carries `graph_unindexed=`, folded
  from the same list the map header prints and absent at zero. ripwire also stops reporting its own cache blob as an
  unread language when that file sits inside the crawl root; that had made one query answer differently cold and warm.
- **A header-qualified selector gave `reaches="0"` for seven real callers.** Reported by **@mariadb-KyleHutchinson**
  ([#63](https://github.com/redhat-et/ripwire/issues/63)). `Foo.h:name` resolved to bodyless declarations, which carry no
  edges. A selector that resolves only to declarations now widens to the definitions they stand for, matched on scope and
  name, never on name alone. `docs/EVALS.md` had published "Blast-radius calls returning an empty radius for a symbol
  with real callers: ripwire 0". That sentence is now scoped to the corpora it measured, only one of which was C++.
- **A call inside `#if 0` was served as a live call site.** Reported by **@mariadb-KyleHutchinson**
  ([#62](https://github.com/redhat-et/ripwire/issues/62)). This is an over-count, which breaks the promise of
  `counts_floor="1"` that the true count is at least the reported one. The dead-range rule `--slice` already used moved
  to `src/preprocdead.h`, and the call graph now reads the same implementation, so the two cannot disagree about which
  lines exist. Only literal `#if 0`/`#if 1` counts; `#ifdef X` and `#if EXPR` stay live. The edge is dropped, not flagged,
  because a flagged row still counts.

`kCacheVersion` goes 17 → 18: this changes which references are extracted, so a version-17 blob would replay edges this
build does not produce. Gate: `test/blindspotcheck.sh`, written red first
([#72](https://github.com/redhat-et/ripwire/pull/72)).

### Fixed — `--for --detail` named a `max_tokens` ceiling it did not apply

On a `--for --detail` run, `--max-tokens=N` budgeted the bodies only. Signatures, the header, the legend and the symbol
table were never charged, yet the root printed `max_tokens="N"` regardless. Reported by **@YogevKr**
([#61](https://github.com/redhat-et/ripwire/issues/61)): at `--max-tokens=300` the answer cost 2,640 estimated tokens,
8.8× the ceiling it named, with no `over_ceiling`.

The fix is disclosure, not enforcement, which is what the issue asked for. Thirty small functions is the complete
answer, and trimming it to fit 300 would serve the caller less while looking more obedient. The reproduction now reads
`max_tokens="300" est_tokens="3589" over_ceiling="1"`, and `--help` states what `--max-tokens` bounds on that path and
what it does not ([#77](https://github.com/redhat-et/ripwire/pull/77)).

### Fixed — a budgeted `--for` shipped past its allowance with no ladder rung fired

`--for`'s ceiling ladder priced the header it was about to emit, but not the two pieces spliced on afterwards: the root
`over_ceiling="1"` and the legend clause that defines it, 70 bytes between them. `est_tokens` prices markup at 2.50
bytes per token while the allowance is sized at 2.714, so any bundle in that band carried 70 bytes the ladder never saw,
and a bundle the ladder had fitted within 70 bytes of the allowance shipped past it. It was latent, not new: the
pre-fix binary, on the repository's own `src/`, overshot at 14 of 111 budgets.

The post-ladder splices and the `est_tokens` fixpoint now move inside the shape the ladder prices, so a shape fits only
when the old reserve test passes **and** the finished header plus every other emitted byte fits the allowance. The first
half is the old test verbatim, so a bundle that was already inside its allowance picks the same shape: over 1,971
invocations across three trees, the flag combinations and the MCP `for` twin, 1,918 are byte-identical to the pre-fix
binary. All 53 that move were past their allowance with no rung fired — 29 now fit, and 24 land on the ladder's
disclosed last rung, which is **larger** than what shipped before, because it carries the overflow disclosure the old
path dropped. `--pack-task` and `--from-trace` keep the fixed-payload form of the ladder and are unchanged by
construction. Gate: `test/estchargecheck.sh` #11 A7 and its new 52-budget sweep, red on the parent commit
([7caf968f](https://github.com/redhat-et/ripwire/commit/7caf968f),
[3d98f84d](https://github.com/redhat-et/ripwire/commit/3d98f84d), in
[#135](https://github.com/redhat-et/ripwire/pull/135)).

### Fixed — caps that cut an answer now say so where they fire

A cap that cuts output silently makes an answer look complete. Each cap below now discloses only when it fires, so an
answer the cap did not touch is byte-identical to before. No cap value moved.

- **`--grep` and `--verify` matched lines** are cut at 512 bytes, and a 512-byte source line used to print the same
  payload as a truncated 50 KB minified line. The row now carries `line_bytes="N"`, the whole line's length. The payload
  itself stays raw file bytes, because `--and`/`--not` read the same line and `--at=` must reproduce it
  ([#100](https://github.com/redhat-et/ripwire/pull/100)).
- **Signatures** cut at 240 bytes now end in `…`, through the same truncator the other three signature cuts already use.
  This affects `--pack-signatures`, `--for`'s `<sigs>`, `<calls>` callee rows and `--lego`
  ([#100](https://github.com/redhat-et/ripwire/pull/100)).
- **A default `--for` named no ceiling.** Its 7,500-byte payload budget applies to every run, but only an explicit
  `--token-budget` was ever named. A trimmed default bundle now carries `budget_bytes="7500"` on its root, in the JSON
  dialect and in the MCP `for` verb ([#100](https://github.com/redhat-et/ripwire/pull/100)).
- **Several listings disclose their own cuts** ([#108](https://github.com/redhat-et/ripwire/pull/108)):
  - `--from-trace` discloses its name-ladder cut (`name_ladder_capped`), and `--handoff` its per-file symbol cut
    (`syms_capped`).
  - The expand and sibling lifts say when they re-ranked, and a malformed `RIPWIRE_EXPAND` or `RIPWIRE_SIBLIFT` is
    reported instead of being read silently as off.
  - The seven mention caps and three co-boost caps disclose on `--for`, `--pack-task` and MCP. Across a 195-invocation
    sweep, only four `--for` invocations changed (+106 B, where `doc_mentions_capped="1"` fired), and their ranked rows
    were identical once that attribute was stripped.
- **`--edit-check`** pages its context rows only. Flagged callers and their `sites_l=` never page, the verdict is computed
  before any window, and the root carries `est_tokens=`. A gate arm proves the verdict byte-identical at
  `--limit=1000000` ([#108](https://github.com/redhat-et/ripwire/pull/108)).

One cap was refuted rather than changed. `kSliceRdMaxIter` (64) cannot fire, because each slot of the reaching-definitions
lattice stabilises on the second round. Instrumented, the highest iteration reached was 1, over 4,528 loop fixpoints in
this tree's `src/` and on adversarial C and Python fixtures ([#100](https://github.com/redhat-et/ripwire/pull/100)).
Gate: `test/capdisclosurecheck.sh`, whose nine disclosure arms fail on the parent commit while every crossing and silence
arm passes.

### Fixed — a cut callee listing kept the lowest node ids, not the rows the question was about

A body's `<calls>` listing keeps at most sixteen callee rows. On `--for`'s bodies, `--pack-task`'s `<bodies>` and
`--from-trace`'s rank-1 body, the sixteen kept were the sixteen lowest node ids. The disclosure,
`<calls total="22" shown="14" capped="1">`, was honest about the count and silent about the choice.

A cut listing is now ordered by the query's rank, with ties broken by id:
- **The measured case.** On this repository, `--pack-task="merge scout conflict"` used to keep 13 of
  `computeMergeScout`'s 22 callees, six of them STL noise, with the merge-scout functions last. It now keeps 14, with
  those functions first.
- **`--from-trace`** ranks a callee that is itself a frame of the same trace ahead of the rest, so the edge the trace
  walked survives the cut.
- **Unchanged.** `--expand`, `--around` and `--exemplar` have no query, so they keep node-id order, byte-identical.

Gate: `test/callsrankordercheck.sh` ([#95](https://github.com/redhat-et/ripwire/pull/95)).

### Fixed — `--regex` anchors match per line, and a regex can no longer kill the run

`--regex` handed a whole file to one iterator, so `^` matched only at offset 0 and `$` only at end of file, in a verb
whose every answer is a single line. On llvm-project, `--regex='^#include'` returned 1,487 hits where a line-oriented scan
returns 289,646. Anchors now match per line, as `grep`, `rg` and editors read them. The scan is also faster on that corpus
(3.40 s against 4.48 s warm).

Disclosed narrowing: a match can no longer span lines, which `[\s\S]*` could do before. That is `rg`'s default contract
too.

- **Why not `std::regex::multiline`.** It is the obvious fix and is not used. Apple libc++ reads one byte before the
  buffer when matching at offset 0, and a 40-line standalone with no ripwire code in it faulted on 74 of this
  repository's ~130 headers.
- **A bad regex no longer ends the run.** A `std::regex_error` thrown mid-scan by catastrophic backtracking used to reach
  `std::terminate`. That file now degrades, and the scan continues.
- **`corpus_pruned_dirs=` on the `--grep` root** names the built-in directory denylist, which grep had never disclosed. On
  this repository `--grep='malloc('` served 33 hits with `complete="1"` where `rg` found 78, and the 45 missing lines
  were all under `third_party/`.

Gate: `test/grepanchorcheck.sh` ([#85](https://github.com/redhat-et/ripwire/pull/85)).

### Fixed — `--grep` no longer reads gitignored files the indexer skips

`--grep` and `--regex` also scan text files whose extension the indexer does not handle. That set was recorded before the
ignore rules were consulted, so a file that was both gitignored and of an unindexed extension was read and served. In the
measured case, that was four hits from a `.cpp.bak` that the repository's own `.gitignore` names. The crawl now consults
the ignore verdict before recording such a file, and `--no-ignore` restores it. On the reporting corpus,
`unindexed_files_scanned` went from 409 to 52. `docs/ARCHITECTURE.md` had still said `.gitignore` is not consulted; that
paragraph is corrected. Gate: `test/grepignorecheck.sh` ([#87](https://github.com/redhat-et/ripwire/pull/87)).

### Fixed — a revision reaches git only as a resolved commit (`--since`, `--merge-scout`, `--pr-context`)

Three verbs resolved a caller's revision with their own copy of the `rev-parse` probe. None of the copies held the whole
rule the shared resolver states: refuse a value that begins with `-` before git is asked, and trust only a bare 40- or
64-hex answer. All three now call `gitResolveCommitSha`. This is defence in depth, not a reachable exploit today, but two
of the gaps gave wrong answers at exit 0:

- **`--since`.** For `--since='^HEAD~3'`, `rev-parse --verify` answers `^<sha>` with status 0, so the run stamped
  `window="^HEAD~3" commits="0"` and exited 0. A date value beginning with `-` passed the date check and reached git's
  argv. Both now refuse, and `git log` receives the resolved commit instead of the caller's string
  ([#115](https://github.com/redhat-et/ripwire/pull/115)).
- **`--merge-scout`.** `--merge-scout=^HEAD~1` printed an empty `ok="0"` arm at exit 0. It now refuses with exit 1 and
  names the ref ([#116](https://github.com/redhat-et/ripwire/pull/116)).
- **`--pr-context`.** `--pr-context=--output=FILE` reached git as an argv entry and was stopped only by git's own
  `rev-parse`. ripwire now refuses it before git is asked ([#117](https://github.com/redhat-et/ripwire/pull/117)).

Valid refs give byte-identical output. The gates `test/sincecheck.sh`, `test/mergescoutcheck.sh` and
`test/prrefsafecheck.sh` log every git argv entry through a PATH shim, and each is red on the base binary.

### Fixed — a repository's hook-form `core.fsmonitor` no longer runs under ripwire's git calls

A repository can configure git to run an arbitrary command on git operations, and ripwire shells out to git during a
crawl. A hook-form `core.fsmonitor` in the crawl root would therefore have run under ripwire. It is now neutralised for
ripwire's own git children and disclosed on stderr and in `--doctor`. Gate: `test/githardencheck.sh`
([#80](https://github.com/redhat-et/ripwire/pull/80)).

### Fixed — JavaScript and TypeScript default imports resolve by what the module exports (parser version 83)

`import save from './storage.js'` bound to whichever function happened to be spelled `save`. It now binds to what
`storage.js` exports as default, with `prov="import"`:
- default declarations, local identifier defaults and `export { local as default }` are all covered;
- the existing lexical-shadow and module-ambiguity handling is reused;
- an anonymous default expression stays unresolved;
- conflicting default exports cannot pick a function just because it is the only function-shaped symbol.

Contributed by **@PollyBot13** ([#56](https://github.com/redhat-et/ripwire/pull/56)). The gate covers TS, TSX, MTS, CTS,
JS, JSX, MJS and CJS, with a same-spelled decoy in each arm. The version is 83 because #57 had already spent 82; the
record shape is unchanged.

### Fixed — an 8-bit counter overflow in four vendored grammar scanners (parser version 87)

Markdown's external scanner added a `size_t` column count into a `uint8_t`. One Rails guide, whose pipe-table row is
padded to 301 columns, made the ASan build exit 134 on that file alone. On the plain build the damage was a wrong parse at
exit 0, and only at widths just past a wrap. At 256 or 257 columns:
- an indented `# Buried` became a heading;
- a fence of that many marks never opened, so its body leaked out as live markdown.

Markdown's counters now saturate at 255, which every threshold they are compared against reads the same way as a larger
true value. The Rust, Lua and C# scanners take an explicit cast instead. Their counters close a token by matching the
opening count, and at 255, 256, 257 and 300 the output recovered identically in all three.

Output is byte-identical over 3,538 real `.md`/`.rs`/`.lua`/`.cs` files, but a constructed 256-column line does move, so
the parser version moves too. Gate: `test/vendorpatchcheck.sh` arm I, with every width pinned at exactly 256
([#102](https://github.com/redhat-et/ripwire/pull/102)).

### Fixed — the vendored YAML scanner's failure status survives an unsigned `char` (parser version 92)

tree-sitter-yaml returns its scan status through four functions declared plain `char`, and one of the values it returns
is `SCN_FAIL`, `#define`d `(-1)`. **`char` is unsigned on aarch64 Linux**, which is where the `linux-arm64` release
asset is built, so there the `-1` came back as 255, with two consequences:

- **A silent parse difference, in every build type the release ships.** The three `case SCN_FAIL:` labels never matched
  255, so a malformed `%`-escape in a tag or a `%TAG` prefix was swallowed into the token instead of ending it.
  `a: !<tag:x%zz> b` parses as `ERROR` under a signed `char` and as a clean tagged scalar under an unsigned one — the
  same bytes, a different tree, decided by the CPU the binary was built for. At the product level, a ripwire built
  `-funsigned-char` minted a key the signed build does not.
- **A sanitizer abort on ordinary YAML.** `scn_pln_cnt` reaches its `return SCN_FAIL;` on a plain `key: value` line, so
  G1's implicit-conversion check stops the run there. All three `test/yamlfix` files abort, which means an aarch64 Linux
  ASan build dies on the first YAML file it crawls.

CI could not see either symptom: both sanitizer legs have a signed `char`, and there is no aarch64 Linux leg.

The fix backports upstream's own change, **a1c4812a**, which no tagged release of the grammar contains yet: the three
`#define`s become an enum whose negative member forces a signed type, and the four functions return it. Its added and
removed lines are identical to upstream's, with only the vendor-patch markers ours. A cast was rejected because it
silences the sanitizer while still never matching `case SCN_FAIL:`.

Every `char` in the grammar sources was audited, not only the two functions the report named, and the rest of the family
was swept: a detector for negative returns through plain `char`, run over all 18 vendored `scanner.c` files plus the
Kotlin scanner, finds YAML only. On a signed-`char` host the default map, `--json` and `--skipped` are byte-identical
before and after, over the repository root, five fixture directories and the generated YAML corpora. Gate:
`test/vendorpatchcheck.sh` arm K builds the vendored grammar twice, once `-fsigned-char` and once `-funsigned-char`,
and asserts identical trees for ten fixtures — one per audited site, plus a control that reaches no failure path — and
that the unsigned build parses all of them and every `test/yamlfix` file clean under the implicit-conversion sanitizer.
On unpatched main five of the ten trees differ and twelve inputs abort under the sanitizer — nine fixtures, only the
control clean, and all three `test/yamlfix` files. `kParserVer` goes 91 → 92, because the extraction of real input changes
wherever `char` is unsigned and a cache blob cannot tell the two architectures apart; `kCacheVersion` stays 20
([#140](https://github.com/redhat-et/ripwire/pull/140)).

### Fixed — `--help=all` said `--situ` self-budgets through `--token-budget`, which `--situ` refuses

The `--top-k` paragraph listed `--situ` among the verbs that self-budget via `--token-budget`. Passing the two together
exits 1, and the refusal's own roster of honouring verbs does not name `--situ`; `src/situ.h` reads neither the token
budget, the max-tokens value nor `--top-k`. The sentence sent an agent to a flag that fails. Only `--situ` is removed
from it; `--pack-task`, `--from-trace` and `--run-trace` are in the refusal's roster and keep their place.
`docs/COMMANDS.md` mirrors the sentence and is generated, so it was regenerated through the repository's own recipe;
that also drops `--top-k` from `--situ`'s derived "Shaped by" list, which is the true statement
([#140](https://github.com/redhat-et/ripwire/pull/140)).

### Fixed — `CLAUDE_CONFIG_DIR` is respected

Every path that located Claude Code's config directory read `$HOME/.claude` and ignored `CLAUDE_CONFIG_DIR`, the variable
Claude Code itself honours. The installers, `skills/install.sh --hook`, `--scan-skills`, `ripwire wrap`'s detection and
`--doctor --agent=claude` now follow `${CLAUDE_CONFIG_DIR:-~/.claude}`, the pattern `CODEX_HOME`, `AGENTS_HOME` and
`HERMES_HOME` already use. Unset behaves as before, and set-but-empty counts as unset.

Contributed by **@s0undt3ch** ([#101](https://github.com/redhat-et/ripwire/pull/101)), who found six sites. Review found a
seventh, in `--doctor`: with the variable set, the installer deployed into the relocated home and reported success, and
`--doctor --agent=claude` then reported `claude-skills ok="0"` and told the user to re-run the installer that had just
worked. `test/claudeconfigdircheck.sh` is a census over executable code rather than a list of known sites, so an eighth
site would go red on the commit that adds it ([#105](https://github.com/redhat-et/ripwire/pull/105)).

### Fixed — `--edit-check`'s tests-to-run receipt gives the answer `--affected` gives

The receipt walked its own path instead of the one `--affected` serves, so the same change could get two different
answers depending on which verb was asked. It now routes through `--affected`'s answer, emits the same evidence tiers and
carries `order="evidence"`. `--pack-task` keeps its deliberately different row set, with the reason stated in the source.
The divergence surfaced while digging into two reports by **@YogevKr**
([#59](https://github.com/redhat-et/ripwire/issues/59), [#60](https://github.com/redhat-et/ripwire/issues/60)). This
change closes neither report; both remain open.

In the same change, a published capture whose `--at=` seed had drifted onto a different function (right shape, wrong
symbol, exit 0) is regenerated. Captures now derive each seed from source, and a gate arm requires every published seed
to resolve to the symbol its demo is about ([#89](https://github.com/redhat-et/ripwire/pull/89)).

### Fixed — two defects clang-tidy found once it could parse the tree

- **A file-handle leak.** `readWholeFile` skipped `fclose` on a short read. The reader is shared by the git-config probe,
  which runs at startup and per request under `--mcp`, and by the notebook reader.
- **Unchecked calibration variables.** The `RIPWIRE_*` ranking calibration variables were read with `atof`/`atoi`. `nan`
  passed through the clamp into every BM25 score, `8x` read as 8, and `notanumber` read as 0 and was clamped to the floor:
  three rankings nobody configured, each at exit 0. A value must now parse as one whole finite token; otherwise the
  default is used and one stderr line names the variable.

Both fixes are in [#120](https://github.com/redhat-et/ripwire/pull/120).

### Fixed — a call the resolver declined to guess at no longer reads as "no caller exists" (`declined=`, `declined_calls=`)

Tier 3 of the name-based resolver refuses a call whose candidates are two or more same-language definitions, none
in the caller's file or directory, and that no qualifier or receiver rule pins. That rule stands: guessing among
cross-directory same-named definitions is how false edges are born. But the refusal was silent — no edge, no `amb=`,
and `ambiguous=`/`unresolved=`/`external=` unmoved — so `--callers` on either definition answered `count="0"` about
a call the resolver had seen, and nothing said how often. At merge, on the `--no-cache` default map, it was 22.2% of
memgraph's call references (65,516 of 295,086) and 4.6% of ripwire's own (6,263 of 135,449); on the branch base it was
8.6% of retrofit's and 0.15% of llvm `lib/Support`'s.

The decline is now counted and shown, and no edge moves:

- The map header carries `declined=N` (JSON `"declined":N`), absent at zero; its legend entry appears only on a map
  that carries the attribute.
- `--callers`, `--callees` and `--impact` carry `declined_calls="K"` in XML, `--json` and `--format=columnar`, as do
  their MCP twins `find_referencing_symbols`, `find_symbol` and `impact`: declined calls that could have meant the
  selector's definitions (callers), that those definitions make (callees), or that could reach SYM or its radius
  (impact), counted once per call. Absent at zero, defined in the legend when present.
- `--pin-census` ends with a conservation line, `# dispositions calls=N …`: every call reference lands in exactly one
  of bound, self, external, unresolved, undefined, other_root, qualified_external, declined, file_scope or
  unaccounted, and `calls=` is re-derived from the references. A resolver exit that names no bucket lands in
  `unaccounted` and raises a degrade alert on plain builds, so the next silent `continue` is caught, not shipped.

Measured on the `--no-cache` default map, the base binary against the change. memgraph and ripwire were re-measured at
merge, on a tree that already carries the `std::`-qualified call guard; retrofit and llvm `lib/Support` are from the
branch base (5c808487), where each map's byte diff is exactly the new `declined=N` plus one legend comment (+245 to
+248 B) and `edges=`, `ambiguous=`, `unresolved=`, `locality_pinned=` and `external=` are identical on every corpus. At
merge, `edges=`, `ambiguous=`, `unresolved=` and `locality_pinned=` are unchanged everywhere.

| corpus | call references | `declined=` | share |
| --- | ---: | ---: | ---: |
| memgraph (at merge) | 295,086 | 65,516 | 22.2% |
| ripwire (at merge) | 135,449 | 6,263 | 4.6% |
| retrofit (branch base) | 29,983 | 2,587 | 8.6% |
| llvm `lib/Support` (branch base) | 20,425 | 30 | 0.15% |

memgraph peak RSS 621 → 630 MB (+1.5%, the candidate index behind `declined_calls=`); wall time unchanged (0.76 s →
0.75 s). A cache written by the pre-change binary reads back warm to output byte-identical with `--no-cache`, so no
cache or parser version moves. Gate `test/declinecheck.sh` covers 17 languages and was red on the pre-change binary
(50 FAIL / 38 PASS as first committed); `test/resolverhonestycheck.sh` F5 now requires the decline to be disclosed,
not merely edge-free.

The at-merge rows are lower than the branch base's (66,015 of memgraph's calls, 7,279 of 134,739 on ripwire's
5c808487 tree) because the `std::`-qualified call guard refuses some `std::` sites before they reach tier 3. The
`# dispositions` line balances with `unaccounted=0` on both; the guard's refusals count as `external`, and
`test/declinecheck.sh` runs the guard's own fixture (`test/stdqualfix`) to keep them there.

### Fixed — the super-linear warm floor under every graph-building verb (`--grep`, `--callers`, the map)

On llvm-project (182,555 files, warm cache) a `--grep` for an absent literal took 159.7 s, `--callers=main`
152.9 s and the default map 248 s, while the same crawl + cache load + model build without the graph took
3.8 s. Profiled to one operation: the resolver rebuilt a receiver type's inheritance cone (two BFS walks
with quadratic dedup) on every still-ambiguous receiver-typed call — 86,667 rebuilds for 2,984 distinct
types, 143 s of the 154 s run. `ChaConeMemo` (`src/graph.h`) computes each cone once with the identical
walk and cap; warm `--grep` is now 9.2 s, `--callers` 8.6 s, the map 10 s, and default maps are byte-identical
before and after on go and llvm. Gate `test/chaconecheck.sh`; the phase tables are in `bench/PROFILE.md`
and the evidence chain in `docs/EVALS.md` (2026-09-09).

### Fixed — a Ruby receiver's lazy bit is order-blind, and a deep constant chain no longer overflows the stack (parser version 86)

Two defects in the receiver round (parser version 84, the entry below; its branch numbered it 83), both found by
review after the merge and both reproduced before they were fixed. Contributed by **@andriytyurnikov**
([#78](https://github.com/redhat-et/ripwire/pull/78), landed in [#91](https://github.com/redhat-et/ripwire/pull/91)).

**A load-time site below a lazy one was lost.** The receiver dedupe keeps one `Include` per (file, innermost
open, written name), and the first occurrence in source order carried the lazy bit. A `Helper.fmt` inside a
method written *above* the same `Helper.fmt` at class-body level therefore left the directive lazy; resolve.h's
pair rule — one load-time directive makes the pair load-time — never saw the load-time site, and the
structure dropped a real dependency. Two files that differ only in the order of those two lines read `ccd="3"
shape="vertical"` with a god file one way and `ccd="2" shape="horizontal" lazy_edges="1"` the other. The lazy
bit is now the AND over every occurrence: the first site still carries the byte, and a later load-time site
clears the bit on the retained record (`captureIncludes`, `seenReceivers` now maps to the record's index).

**A 5000-segment chain killed the run.** `rubyIsConstantChain` recursed once per segment of a left-nested
`scope_resolution`, and the depth bound in `captureIncludes` sits *after* `directiveTargetOf`, so a generated
`A::A::…::A.call` of 5 000 segments overflowed a parse worker's stack — SIGBUS, exit 138, no output, measured
on macOS; 2 000 survived. The check is a loop now. Nothing else on the path recurses per segment: the walk is
an explicit stack, the resolver splits the text.

**`--help` said `lazy="1"` was TS/JS only.** It has read Ruby closures and autoloads since parser version 84;
the `--impact` line now says so, and `docs/COMMANDS.md` is regenerated from it.

Measured (`--deps --limit=100000`, parser version 83 → 86, the same four corpora as the receiver round; the
gems are Rails 7.2.3.2, the apps are the same two):

| corpus | ccd | nccd | shape | lazy_edges | bytes |
| --- | --- | --- | --- | --- | --- |
| activesupport `lib/` (282) | 15 299 → 15 299 | 7.59 → 7.59 | tangled | 945 → 935 | 75 970 → 75 988 |
| activerecord `lib/` (395) | 4 088 → 4 325 | 1.36 → 1.44 | vertical | 1 026 → 1 023 | 114 745 → 114 763 |
| a Rails app, 4683 files / 3532 `.rb` | 13 170 → 13 172 | 0.32 → 0.32 | horizontal | 5 632 → 5 630 | 750 913 → 750 915 |
| a second Rails app, 1967 / 1895 `.rb` | 6 382 → 6 382 | 0.34 → 0.34 | horizontal | 1 830 → 1 830 | 363 733 → 363 750 |

Read together: the pairs that flip are the ones written lazy-first and load-time-second in one body — ten on
activesupport, three on activerecord, two on the first app, none on the second — and on activerecord three of
them sit on a spine (ccd +237). No shape moves. Wall time unchanged. Cold == warm on activerecord and the
first app; two `--no-cache` runs identical on all four.

**Record shape unchanged**, so cache format 18 holds; the extraction identity moved (a cached lazy bit could be
wrong), so cached Ruby files re-parse once. `kIngestParserVerMirror` moves in the same diff. The version is 86,
not 85: main spent 85 on the plain-text prose tier before this landed, and a collision is resolved by
re-bumping over the tip, never by keeping the fork's value.

Gate: `test/rubyrecvcheck.sh` gains `lib/app/eager_after_lazy.rb` (18 fixture files; ccd 20 → 22, helper.rb
afferent 2 → 3, a row arm with no `lazy_edges=`, the `--impact=Helper` importer tier) and a deep-chain arm that
generates a 150 000-segment receiver at gate time and expects one directive and exit 0. Written red first: six
arms fail against the pre-fix binary — the eager-after-lazy importer reads `lazy="1"`, health reads
`ccd="21" lazy_edges="10"`, the deep chain exits 138. ASan/UBSan clean on both fixtures, the deep chain, and
the cache round-trip. Re-pins with reasons in-file: `qschemetrip.hash` (parser mirror), `printf_parity.manifest`
(`help` and `impact` bytes — the `--impact` import-tier legend moved with the `--help` line).

### Added — a Ruby constant receiver is a dependency (parser version 84)

Round two of the Ruby constant work. Parser version 82 gave the declarative spellings — `class X < Base`,
include/extend/prepend, `autoload :Name`. This round adds the one a Zeitwerk application actually depends
through: a **constant receiver** — `User.find`, `App::Mailer.deliver`, `Struct.new`. The autoloader loads
lib/app/user.rb on that first reference, and nothing else in the file says so.

Contributed by **@andriytyurnikov** ([#65](https://github.com/redhat-et/ripwire/pull/65)). The round was measured and
gated on its branch as parser version 83 and shipped as 84, because the JavaScript and TypeScript default-import fix had
taken 83 first; the version numbers in this entry's tables and gate notes are the branch's.

Four decisions, each stated in `test/rubyrecvcheck.sh`'s header rather than asked:

1. **What counts.** A `call` whose receiver is a constant or a constant chain (`A::B::C`, `::A::B`), spelled
   as written. A chain whose head is not a constant — `repo::Finder`, `self.class`, an identifier, an ivar —
   is nothing (`rubyIsConstantChain`; the round-one reader accepts any scope-resolution text and is right
   for the positions the grammar already restricts to constants, a receiver is not one). A constant used as an
   **argument** (`raise Errors::Boom`, `validates_with Foo`) or as a rescue class is **not** a receiver: a
   disclosed floor of this round.
2. **Dedupe at extraction**, per (file, innermost class/module open, written name). Zeitwerk loads a
   constant once per process, on its first reference; the second `User.find` in the same body is not a new
   dependency. The first occurrence in source order carries the byte and therefore the lazy bit. The nesting
   is in the key: `User` under `module Admin` and `User` under the enclosing module may be two constants, and
   the fixture has that file. `Time` and `::Time` are two spellings, two directives. The declarative shapes
   stay one directive per occurrence — each is a statement. Measured with the Prism prototype: distinct
   (file, nesting, name) is 61 % of raw receiver sites on activesupport, 67 % on activerecord, 56 % and 53 %
   on the two Rails apps.
3. **Lazy inside a closure.** A receiver inside a `method`, `singleton_method`, `lambda`, `block` or `do_block`
   is `lazy="1"` — it runs when and if that closure runs, the parser-72 TS/JS function-body rule on Ruby's
   own closure kinds (`kRubyClosureContainers`). A receiver at class-body or file level runs at load. A
   `do`-block passed to a class-level macro (`included do`, `after_commit do`) is lazy under this rule even
   when the callee runs it at load: the tool cannot see the callee, and a block is a closure it may or may
   not run. `--impact`'s importer tier says `lazy="1"` only when every edge from that importer is lazy.
4. **Resolution is round one's, unchanged.** Module.nesting innermost-first then Object, `::` absolute,
   wrapper opens define nothing, genuine reopenings fan out, a same-file reference is shown and dropped as a
   self-include. An out-of-tree receiver (`Time`, `Struct`, `Object`) is a shown `<inc t=>` row with no edge —
   the posture every Python `import os` row already has.

**The Ruby walk now descends every node.** A receiver is an expression — under an assignment, an argument
list, a lambda, a binary, a string interpolation — so the statement-level container allowlist Ruby had through
parser version 82 (19 kinds) would have needed ~40 and every kind it missed would have been a receiver
silently dropped, a floor the tool could not disclose because it could not see it. The full descent is the
cost the reference pass already pays once per Ruby file. The depth bound (256) still degrades loudly.
`--deps --limit=100000 --no-cache` wall time on a 4683-file Rails app: 1.04 s → 0.92 s (noise); on
activerecord `lib/` 0.21 s → 0.18 s.

**Structure versus use — the decision this round adds, and it reaches TS/JS too.** With receivers counted
like every other edge, a Ruby codebase is one strongly-connected core at the file level: models name each
other, base classes name their subclasses through registries, and the cone of a controller is most of the
application. Measured before the cut, `--deps --limit=100000` on a 4683-file Rails app went ccd
12 740 → 1 407 232, nccd 0.31 → 33.74, and every Ruby corpus read `shape="tangled"`. That is a true fact
about runtime references and a useless one for a lens: a reading that is the same everywhere is not a
reading. So a **lazy edge** — a (from, to) pair every one of whose directives is written inside a closure
(a Ruby method/lambda/block, a TS/JS function body) or is a Ruby `autoload` — is a **use**, not a load-time
dependency, and the two views now say different things on purpose:

- **Use** — `--impact`'s importer tier (`lazy="1"`), the file's own `<inc t=>` rows, call-resolution
  narrowing, `--expand`'s siblings and `--cochange`'s static-coupling test all keep every edge. "Who uses
  `User`?" is answered by all 197 files that call it.
- **Structure** — `--deps`, `--arch` and `--report` measure the load-time graph: `afferent=`, `instab=`,
  `transitive=`, godfiles, stabledeps, cycles, ccd/acd/nccd and `shape=` leave lazy pairs out
  (`graph.h::resolveStructuralIncludeAdj`; one load-time directive makes the whole pair load-time, the
  parser-72 `recordLazyPair` rule). The cut is disclosed where it is made: `<health lazy_edges=N>` counts the
  distinct pairs left out and a file row carries `lazy_edges=N` for its own, both absent when 0 — so a corpus
  with no lazy directive is byte-identical to before. A lazy edge is not an unresolved one: the unresolved
  row has neither `lazy_edges=` nor an importer; the lazy row has both.

This changes one TS/JS number: a `require()` inside a function body (parser version 72) was already
`lazy="1"` in the importer tier and is now also out of `--deps`' structure. On this repo's own fixtures no
gate pinned it inside the cone. `--deps --limit=100000`, parser version 82 → 83 (`files=` is the listing's
own denominator: files with a row; `<godfiles total=>` the uncapped load-time importee count):

| corpus | files= | ccd | acd | nccd | shape | importees | lazy_edges | `--deps` bytes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| activesupport 7.2.3.2 `lib/` (282) | 206 → 241 | 10 450 → 15 299 | 37.2 → 54.4 | 5.19 → 7.59 | tangled → tangled | 241 → 201 | 945 | 55 483 → 75 970 |
| activerecord 7.2.3.2 `lib/` (395) | 300 → 368 | 2 714 → 4 088 | 6.9 → 10.4 | 0.90 → 1.36 | horizontal → vertical | 385 → 310 | 1 026 | 71 474 → 114 745 |
| a Rails app, 4683 files / 3532 `.rb` | 2 296 → 3 245 | 12 740 → 13 170 | 3.3 → 3.4 | 0.31 → 0.32 | horizontal → horizontal | 385 → 414 | 5 632 | 378 473 → 750 913 |
| a second Rails app, 1957 files / 1895 `.rb` | 1 072 → 1 455 | 6 289 → 6 382 | 3.3 → 3.4 | 0.33 → 0.34 | horizontal → horizontal | 189 → 197 | 1 830 | 173 606 → 363 733 |

Read the two halves together: on the Rails apps the structure barely moves (class-body receivers are few)
while `lazy_edges` says how large the runtime layer the structure leaves out is — 5 632 pairs on the first
app, where the importer tier now names them all. On the gems the structure grows because a gem does depend at
load time through class-body receivers (`ActiveSupport.on_load`, `Concern`), and importees FALL (241 → 201,
385 → 310): a file whose only importers call it from inside methods is no longer a god file, it is a file
`--impact` lists. The uncapped `<inc t=>` listing on activerecord carries 2 228 rows over 1 188 distinct
targets, the most frequent being `ActiveSupport::Concern` (57, out of tree, shown, no edge).

**Default map.** Byte-identical on a Ruby-free corpus (this repo's `src/`, modulo version stamps). On Ruby
corpora the ranking moves a little (activesupport `est_tokens` 15 745 → 15 688, `pr_iters` 56 → 54) because
include edges narrow ambiguous call resolution and there are more of them; no `id=` row moves — `scope` is
still the immediate enclosing name.

**Record shape unchanged.** A receiver is an `Include` with `isSymbolic` and `byte` (both parser version 82),
so cache format 17 holds and only the extraction identity moved: cached Ruby files re-parse once. Cold and
warm caches agree on activerecord and the 4683-file app (gated on the fixture).

**Round one's gate moved two arms, honestly.** `test/rubyconstfix`'s `dynamic.rb` (`include
Object.const_get(:Trackable)`) now has a row — the `Object` receiver, not the include, and the arm asserts
exactly that; `point.rb` (`Point = Struct.new`) has a `Struct` row with `afferent="0"` — the alias is still
not indexed, the floor note stands.

Gate: `test/rubyrecvcheck.sh` + `test/rubyrecvfix/` (17 files — dedupe across seven receiver sites, two
nestings of one name in one file, four laziness levels, lexical versus absolute, the Object-level fallback
for a module-less script, a self-include, five non-constant receiver shapes, the Struct alias floor, the
argument/rescue floor, a same-basename decoy, the structure-versus-use cut — ccd 20 over 17 files with
`lazy_edges="9"`, App::User with four lazy importers and no `--deps` row, a lazy row told from an unresolved
one — root-spelling parity, determinism, warm == cold, well-formedness). Written red first: 14 arms fail
against the parser-version-82 binary and 7 more against the receiver build before the cut; every mutation
control and floor arm passes there. 558 → 559 gate scripts.

### Added — Ruby constant references are dependencies (parser version 82, cache format 17)

A Zeitwerk application spells almost none of its dependencies with `require`: a controller depends on a
model by **naming the constant**, and a Rails gem declares half its structure with `autoload :Name`. Parser
version 81 gave Ruby `require`/`require_relative`/`load`; this round adds the constant spellings, so the
file graph `--deps`/`--arch`/`--impact`/`--cochange` see is the one Ruby actually has:

| Spelling | Directive | Resolution |
| --- | --- | --- |
| `class X < Base` | the superclass constant | index, lexical rule (below) |
| `include M` / `extend M` / `prepend M` | one directive per constant argument | index, lexical rule |
| `autoload :Name` (ActiveSupport::Autoload) | the constant | index, lexical rule; `isLazy` |
| `autoload :Name, "path"` (Kernel#autoload) | the **path**, as one directive — never the constant beside it | the load-path rule, as a `require`; `isLazy` |

**The rule is Ruby's own, not a convention.** Every `class`/`module` open in the corpus is recorded with its
name as written (`Base`, `App::Audited`, `::Top`) and its byte span (`ConstOpen`, `src/model.h`). An open's
nesting is its enclosing opens by span containment — the same containment that attributes a call to its
def — and its fully-qualified constant follows: `::X` is absolute; a compact `class A::B` inside `module X`
names `X::A::B` when the tree opens `X::A` anywhere, else `::A::B` (Module.nesting first, then Object). A
reference `Name::Sub` at nesting `[A, A::B]` is looked up as `A::B::Name::Sub`, `A::Name::Sub`,
`Name::Sub`; first hit wins. A superclass carries its class's own start byte, so it resolves in the
**enclosing** scope, exactly as Ruby evaluates it. Constant targets are never probed as paths
(`Include::isSymbolic`): `require "Foo"` is legal Ruby, and on a case-insensitive filesystem a path probe for
`Trackable` lands on `lib/trackable.rb` — the fixture's decoy pins it.

**Two kinds of "defined in many files", told apart structurally.** `module App` is opened by every file under
`lib/app/`. An open whose body holds nested opens and **nothing else** is a *namespace wrapper*: it nests,
but it defines nothing of `App` and is not a definer in the index (`ConstOpen::namespaceOnly`, read off the
body's children — comments are extras and are skipped; an EMPTY open defines). A reopening **with** a body — a
monkey patch, a decorator, a `core_ext` — is a real second definer, and a reference then edges to **every**
definer: change any of them and the constant changes, which is what `--deps` measures. That is multiplicity
(every answer is right), deliberately distinct from the specifier ambiguity every other Step-A degrades on
(`require "shared"` answered by two files: exactly one is right, and this tool cannot tell which). Only the
latter resolves to nothing. Measured with a Prism prototype of the same lexical rule on a 3532-file Rails
app: 124 constants were "multiply defined" by opens, **5** by bodies, and treating wrappers as definers was
what made 246 superclass references ambiguous there (0 after).

**Measured** (`--deps --limit=100000 --no-cache`, both binaries from this tree; `importees` is the
uncapped `<godfiles total=>` — files with at least one incoming edge — and `edge-bearing` is `<deps files=>`):

| corpus | ccd | acd | nccd | shape | importees | edge-bearing files |
| --- | --- | --- | --- | --- | --- | --- |
| activesupport 7.2.3.2 `lib/` (282 files) | 3658 → 10450 | 13.0 → 37.2 | 1.82 → 5.19 | vertical → tangled | 194 → 241 | 194 → 206 |
| activerecord 7.2.3.2 `lib/` (395) | 947 → 2714 | 2.4 → 6.9 | 0.31 → 0.90 | horizontal | 214 → 385 | 108 → 300 |
| a Rails app, 4683 files / 3532 `.rb` | 5638 → 12740 | 1.5 → 3.3 | 0.14 → 0.31 | horizontal | 103 → 385 | 1154 → 2296 |
| a second Rails app, 1957 / 1895 `.rb` | 5483 → 6258 | 2.9 → 3.3 | 0.29 → 0.33 | horizontal | 80 → 189 | 619 → 1066 |

ActiveSupport turning `tangled` is `core_ext`: `String` is reopened with a body in 15 files, so every
`< String` and `include`-of-a-patched-module depends on all of them — true, and the point of `core_ext`.
The **default map** is byte-identical to the pre-change binary on four Ruby-free corpora (this repository
and three others) and moves on Ruby ones only through the call graph's same-include tier: ActiveSupport
`edges=` 3729 → 3715, `ambiguous=` 409 → 406; ActiveRecord 8397 → 8298, 1284 → 1105.

**Floors, each pinned by an arm of `test/rubyconstcheck.sh`.** The ancestor half of Ruby's lookup (a
constant inherited from a superclass or an included module) is not walked. `Point = Struct.new(…)` is an
alias, not an open — `queries/ruby/tags.scm` skips CamelCase assignments and so does the index. `include
Object.const_get(:X)`, `autoload :X, some_path`, `require some_variable` capture nothing. Constant
**receivers** (`User.find`) are not this round: they are the bulk of a Zeitwerk app's edges and move every
Ruby denominator again, so they land as their own change with their own table.

**Record shape.** `Include` gains `isSymbolic` and `byte`; the per-file cache record gains the `ConstOpen`
family after `routeUses` — `kCacheVersion` 16 → 17 (a format change; the parser-version bump re-ingests
every cache anyway, so no extra cost). `Symbol::scope` stays the *immediate* enclosing name by design; the
fully-qualified constant lives only where it is needed. `--impact`'s importer tier reports `lazy="1"` for
an `autoload`, as it does for a function-body `require()`.

**Expired floor.** `test/rubyrequirecheck.sh` arm 3(c) pinned "`autoload :Late, "lib/helper"` is not
captured" since parser version 81. It now is (12 directives on that fixture, not 11; `lib/helper.rb`
afferent 2 → 3), and the arm was inverted rather than deleted so the expiry is on the record.

Gate: `test/rubyconstcheck.sh` + `test/rubyconstfix/` (30 files — nesting, compact and absolute names,
lexical shadowing, the three mixin verbs, `autoload` plain / in `eager_autoload do` / in `autoload_under
do` / with a path, a monkey-patched in-tree class, a patched core class, a namespace with 23 wrapper opens
and one real body, a wrapper-only reopen, out-of-tree constants, a same-basename decoy, a same-file
reference, two sites sharing an innermost open but not a nesting chain — `module A; module B` versus the
compact `module A::B`, where only the first can see `A::Helper` — root-spelling parity, determinism,
warm == cold, well-formedness). The chain pair was added after review: the resolver's memo was keyed on
the innermost open alone, so whichever site was visited first fixed the other's answer, and cold and warm
caches visit the sites in different orders — the fixture gave the helper two importers cold and none warm.
The memo is now keyed on the whole chain. Written red first: 24 arms
fail against the parser-version-81 binary, every mutation-control and floor arm passes there. 557 → 558
gate scripts.

Contributed by **@andriytyurnikov** ([#57](https://github.com/redhat-et/ripwire/pull/57)).

## [0.5.0] — 2026-09-07

**The first release carrying outside contributions.** Three people who do not work on this project
wrote fixes that are in this binary — Michael Freeman, PollyBot13 and Andriy Tyurnikov — and three
more found things it got wrong: Cort Fritz, stalep and Jan Mangs. All six are named below, beside
what they found. That is what this number is for.

### Added — Elixir, as a first-class indexed language

A vendored tree-sitter grammar and call-graph extraction, with protocol implementations indexed as
their own definitions. Contributed by **Michael Freeman**
([#43](https://github.com/redhat-et/ripwire/pull/43)), rebased onto main's tip — the extraction
identity is 78, not the 83 the fork carried — and extended with two gaps the fork could not see from
where it sat. The import edges are described in their own section below.

### Added — `<recent>` answers "what changed", not "what churns"

`--rank-by=churn-decay` emits a file-level `<recent>` block ordered by newest commit first rather
than by heaviest weight. A question about what changed recently was being answered with what changes
most often, which is a different question. The MCP instructions carry the deferral hint.

### Added — tests-to-run rows in evidence order

A changed test file comes first, then its stem partner, then graph hops, and each row says *why* it
is there. A test file that is itself in the diff is an obligation on its own evidence. The silent
zero on that surface is fixed: an empty result now says so.

### Fixed — named JavaScript and TypeScript import aliases

`import { a as b }` resolved to the wrong symbol, and the refusal path deleted edges that were
correct. Contributed by **PollyBot13**
([#45](https://github.com/redhat-et/ripwire/pull/45)). The refusal now reports which of the three
things it knew rather than collapsing them into one message.

### Fixed — five languages were invisible to the unanalyzed-language disclosure

`filesByLang` was sized with a hardcoded `16` while the `Lang` enum had grown to 21, so TOML, YAML,
PHP, Lua and Elixir were dropped from the count silently — and two of them were named in
`kUnanalyzedLangs`, meaning the lens promised to declare them and could not. Found by **Cort Fritz**
on his own fork. The array is now sized by `kLangCount`, with a `static_assert` that fails the build
if the enum outgrows it again. **A disclosure surface that under-reports is worse than one that is
absent**, which is why this is the fix in this release that mattered most.

### Fixed — the MCP tool schema a strict client refuses

One tool declared a union type that stricter MCP clients reject outright, taking the whole server
down with it ([#48](https://github.com/redhat-et/ripwire/issues/48), reported by **stalep** against
opencode with `@ai-sdk/google-vertex`). Gated by `test/mcpstrictschemacheck.sh`, written red against
the binary that had the bug.

### Fixed — twenty first-run defects a stranger hits and a maintainer never does

`PATH` not printed on install, a borrowed query in the quickstart, shallow clones mishandled, two
inverted `--doctor` verdicts, lock-file litter, sidecars that did not say what they dropped, an empty
map that read as an answer, and an upgrade path that left a binary which could not run and reported
success. Found by auditing the install as somebody who had never run it.

### Changed — the README leads with the proof

The ten-moments token table and the graphs now sit under the install block: **300 words to the first
piece of evidence instead of 1,009**. Twenty-six prose blocks moved behind `<details>`, each with a
summary carrying its own number, so the page makes the same case whether or not anything is clicked.
Nothing was removed — the full read is longer than before, because the summaries are additive.

### Changed — Graft folded into the lineage ledger as the 42nd repository

A registered head-to-head against Graft 0.17.0 ran, its losses were converted into code, and it was
re-run: 14 of 30, with the placebo arm at 13-12-5. **The stop condition fired, so no ranking claim is
published from that round.** What shipped is the two fixes it produced — tests-to-run in evidence
order, and `<recent>`.

### Changed — CI shards its gate suite across runners

Each release leg's gates split across runner jobs, so the workflow's wall clock is one shard rather
than one suite. Main runs are no longer cancelled by the next push.


### Changed — every skill description rewritten under the client budget, and one skill folded away

Reported and **measured** by [@jmangs](https://github.com/jmangs) in #49: Codex silently shortens skill
descriptions to fit its context budget, keeping the first ~350 characters of each. All eighteen ripwire
descriptions were over that budget — **18,455 characters authored, 6,300 retained, 12,155 discarded**,
fifteen of them cut mid-token. What the truncation removed was the routing boundaries: the "NOT for X,
that's skill Y" clauses, the secondary triggers, the misuse warnings. His diagnosis is the one this round
acted on, and it is worth quoting: the shortened descriptions "do not become literally identical — the
problem is semantic: related skills lose the clauses that distinguish them."

That reframed the task. Eighteen skills whose boundaries need a thousand characters each to explain are
eighteen skills whose boundaries are not carrying their own weight; the budget did not create the routing
problem, it exposed it by deleting the prose that was compensating. So the round asked what set of skills
has boundaries an agent can tell apart *in* 350 characters, rather than how to compress the existing ones.

Pre-registered before any description was touched (`docs/EVALS.md`), with a truncation-aware A/B whose
baseline was today's descriptions **truncated** — the thing users actually have — not today's full text.
The registered set-total ceiling was amended 4,800 → 5,400 and a third blind rater added, both **before**
measurement rather than after. Three LLM raters, sealed held-out set. The result was a **REJECT on the
registered band**, published as such; the parts that stood were kept, including folding
`ripwire-efficient` into `ripwire-orient` — the one boundary all three raters independently could not
distinguish. `test/skilldescbudgetcheck.sh` now pins every description under the budget, with a
binary-backed arm reading the binary's own skill discovery, so this cannot drift back silently.

### Added — Bash, Lua, Ruby and Elixir get import/dependency edges (parser version 81)

Four languages that emitted **no dependency record on any tree** now emit one per directive. Each spells a
real file dependency, and each spells it as an ordinary CALL rather than a reserved statement — which is
why `directiveTargetOf` had no branch for any of them, and why `lintrules.h::dependencyCapable` called all
four incapable. That was a true statement about this extractor and a false one about the languages.

| Language | Directives captured | Resolution rule |
| --- | --- | --- |
| Bash | `source FILE`, `. FILE` | the argument IS the path — no convention to model. A `$VAR`/`$( … )` anchor is reduced to its literal tail and probed against the includer's directory and every ancestor, unique-or-degrade |
| Lua | `require "a.b"` | package.path's dotted convention (`a.b` → `a/b.lua`, or the package form `a/b/init.lua`), probed from the requiring file upward and under the `src/` and `lua/` source roots |
| Ruby | `require_relative`, `require`, `load` | a leading dot means file-relative (the extractor normalizes `require_relative "x"` to `./x`); a bare specifier is searched against the crawl root plus `lib/`, `app/`, `test/`, `spec/` |
| Elixir | `alias`, `import`, `require`, `use` | the corpus's OWN `defmodule` index, not a `MyApp.Foo` → `lib/my_app/foo.ex` path convention — so umbrella layouts and generated paths resolve, and a module two files define resolves to neither |

Every rule is unique-or-degrade: two candidate files answering one specifier resolve to **neither**. There
is no basename fallback anywhere in this, which is the one shortcut that would have made all four look
better on a benchmark and been wrong invisibly.

**Measured on this repository** (`ripwire . --deps`): 29 `source` directives across 28 gate scripts, 26 of
them resolved. The 3 that do not are `. /dev/stdin <<EOF`, an absolute path outside the crawl — shown as a
target row with no edge, never dropped. All 29 specifiers in this tree are `$ROOT/…`, so a literal-only
resolver would have resolved zero of them.

**Disclosed floors.** A shell specifier whose FILENAME is variable (`"$1"`, `"$d/$n.sh"`) cannot be
resolved by anything short of running the script: it is captured, displayed, and produces no edge. Ruby's
`autoload :Foo, "path"` is not captured (its path is argument two). An Elixir `alias A.B.C` also binds the
local name `C`, so a later `C.f()` means `A.B.C.f` — the FILE edge lands, the NAME alias does **not** narrow
call resolution, because the call's receiver is not kept by `queries/elixir/tags.scm`. Quoted Elixir AST
(`quote do … end`) is descended into, so an `alias` inside a macro template is captured: the same
union-over-arms posture the preprocessor tables take, a spurious edge rather than a missing one.

### Changed — the dependency denominator moved, and now says so

Making four languages dependency-capable changes **five denominators and one predicate**: `--deps`'s
`dep_files=`/`ccd`/`acd`/`nccd`, `--arch`'s `propagation_cost`, and `--cochange`'s pair filter. Any number
recorded against an older build on a corpus holding Bash, Ruby, Lua or Elixir has moved. On this repository
`dep_files` went 758 → 1392 and `nccd` 0.68 → 0.39.

`--deps` therefore publishes **`<health dep_langs=>`** — the capable language set, derived from the
predicate itself so it cannot drift from what it documents. A `dep_files=` number is only comparable across
builds when `dep_langs=` matches, and until now the set behind it existed only in a source comment.

**`--cochange`'s `surprising=` is now a PAIR question.** It was "both sides dependency-capable", which
agreed with the truth only while `.sh` was incapable. The moment a shell script became capable, that form
would have declared `test/foo.sh` ↔ `src/bar.h` a pair whose missing static dependency is *evidence* — and
no `source` can name a header. Measured before the change: of 153 `dep_capable="0"` rows in this repo's top
400, the per-file form would have turned 88 capable and **75 of those are cross-dialect** pairs that would
have read as hidden architectural debt. The predicate now also requires a shared dependency dialect, which
additionally fixes 22 pre-existing over-claims of the same shape (`.js`↔`.h`, `.py`↔`.h`, `.py`↔`.cpp`).

**Markdown stays excluded, now on the record.** Markdown *does* mint doc→doc link edges — `[B](b.md)` is a
real edge and the map shows it — so "no import syntax" was never the reason. It is excluded because `--deps`
and `--arch` measure change amplification, and a README linking twelve design docs is not twelve files of
it: docs are read, not compiled. JSON/TOML/YAML have no file-level import at all.

**Fixed while building this:** the root-relative probe every unknown-anchor rule needs was anchored at an
empty base, which is the crawl root only when the root was written as `.`. The same tree scanned as
`ripwire /abs/path` resolved 13 of 29 `source` directives where `ripwire .` resolved 26. Probing the
includer's ancestor chain instead is root-spelling independent, and each new gate asserts the two spellings
produce identical edges.

Five new gates: `test/bashsourcecheck.sh`, `test/luarequirecheck.sh`, `test/rubyrequirecheck.sh`,
`test/eliximportcheck.sh`, `test/deplangscheck.sh` (550 → 555). `test/luacheck.sh` §2 was **inverted** — it
used to assert `<deps files="0">` on a Lua corpus, which is the assertion that would have kept this defect.

### Fixed — Ruby: definitions carry their enclosing class/module, and `def name=` is indexed and called

Landed from PR #47 (Andriy Tyurnikov), rebased onto the Elixir and ES-import work. Two Ruby extraction
defects, plus one resolver defect that turned out not to be Ruby's at all.

**A Ruby `def` had no scope.** `src/ingest_sidecap.h` set a definition's `scope` for C++, Python and Rust
only, so no Ruby row ever carried an `id=`: a `Scope::name` selector (`--expand=B::initialize`,
`--callers=A::helper`) could not address a Ruby method, same-named methods in different classes of one file
folded into a single `overloads=N` row, and `--edit-check=Widget::resize` answered "symbol not found".
(PR #47 also listed `editcheck.h`'s implicit-receiver exemption as a dead branch the scope revives. It does
revive it, and it is still inert: Ruby has no implicit receiver parameter to exempt, and the caller test
short-circuits on `arityExact == 0` — which `cc_paramArityExact` gives every Ruby definition, since its
language gate does not list Ruby. Measured `incompatible="0"` scoped and unscoped, before and after. The
comment there now says so rather than implying a recovered signal.) `rubyEnclosingScopeOf` (`src/ingest_names.h`) records
the nearest enclosing `class`/`module`: it walks THROUGH `class << self`, skips the definition's own node
(a `class Widget` inside `module Outer` scopes to `Outer`, never to itself) and takes the last segment of a
`class Foo::Bar` name, matching the contract C++'s `qualifierOf` already keeps. A top-level `def` still has
no scope and no `id=` — a file is not a scope.

**`def name=(v)` was never indexed, and `obj.name = v` called the getter.** tree-sitter-ruby names a setter
with a `(setter)` node, which `queries/ruby/tags.scm`'s method pattern did not accept. And `obj.name = v`
parses as `(assignment left: (call method: (identifier)))` — the same `(call)` shape as the read
`obj.name` — so the call rule captured a reference to `name` and the resolver handed a WRITE to the getter:
a false edge, not a floor. The setter is now named `name=` on both sides: the definition from the
`(setter)` node's own text, the call site by reading the assignment parent (`rubyCallIsAssignmentTarget`).
`self.name = v` inside the class pins to `Class::name=` through Rule 1, and `--callers=name=` answers.

Three resolver-side changes ride along so the new scope adds precision without losing edges: Ruby call
receivers are classified (`src/ingest_binds.h` — `self.m` is `ThisObj`, `x.m` is `NamedVar`, a receiver-less
`m(args)` stays bare); Rule 1 (`src/resolve.h`) treats a bare Ruby paren call as the implicit-self send it
is, so `helper(2)` inside `class A` pins to `A::helper` as a FACT rather than as a disclosed locality guess
(`lpin=`); and the S6-C locality tie-break (`src/graph.h`) no longer lets the caller's own definition win.

**The tie-break fix is not Ruby's, and is disclosed as such.** A candidate that IS the caller matched itself
on every locality segment, won alone, and was then dropped at emission as a self-loop — the site produced no
edge at all, silently. Ruby's facade idiom surfaced it, but the shape is language-agnostic: the same fixture
in PYTHON goes from `edges=0` to an honest 2-way split with `amb="1"` (`test/lpincheck.sh` arm (I), the
language-agnostic pin — revert that one line and it goes red before any Ruby gate does). Measured across
eight Ruby-FREE corpora (rocksdb, duckdb, ugrep, django, ccxt, mlflow, cpython and one large
ObjC++ tree —
`--no-cache --top-k=100000`, every row and every edge compared): the change is **edge-ADDITIVE, 0 edges lost
anywhere**, `symbols=`, `unresolved=` and `external=` unchanged, `edges=` +0.02% (ccxt) to +0.33% (rocksdb),
and `locality_pinned=` up where an edge that used to vanish is now emitted as a disclosed guess (rocksdb
141 → 587, duckdb 171 → 575, cpython 556 → 709, the ObjC++ tree 100 → 237). A control binary carrying
other change with only that line reverted is BYTE-IDENTICAL to the pre-merge tip on all eleven Ruby-free
corpora — so nothing else in this change moves any other language.

Measured on Ruby 2.6's own stdlib (833 `.rb` files, `--no-cache --top-k=100000`, byte-identical across runs,
`xmllint --noout` clean): `symbols=` 14220 → 14476 (250 setter rows, 253 definitions, where none were
indexed before); rows carrying `id=` 97 → 13191; rows carrying `overloads=` 649 → 194; call edges naming a
setter 0 → 534; `ambiguous=` 5872 → 5544; `edges=` 29077 → 28840 — a NET DROP, because a write against a
setter the tree does not define no longer invents an edge to the getter. **The `id=` attribute is what a
scoped row costs**: the full map's `est_tokens` rose 504107 → 816226 on that corpus and the default 200-row
map's 8796 → 12313 (+40%), the same price Python already pays. Non-Ruby corpora pay ~1% (rocksdb 14652 →
14826).

**Stated floors, each pinned by a gate arm so it stays a decision.** `rubyCallIsAssignmentTarget` reads a
plain `(assignment)` only, so a compound `w.count += 1` and a conditional `w.count ||= 1` (both
`operator_assignment`: they read AND write, and one capture carries one name) and a multiple assignment
`a.count, b.count = 1, 2` (a `left_assignment_list`, one level deeper) all keep the getter edge only.
`attr_accessor` / `attr_writer` / `attr_reader` generate their methods at load time and define nothing in
the source text, so they are not symbols and a write against one resolves to an honest NOTHING — unchanged
by this work, and now asserted. And the tie-break fix is the tie-break only: one layer up, tier 1 admits
same-FILE candidates and stops if any exist, so a caller that is the only same-file candidate is still
selected alone and still dropped to nothing (`def prerelease=; set.prerelease = v; end` in one file with the
real `prerelease=` in another). Widening tier 1 past the caller would mint a cross-file edge the same-file
tier already outranked, so the honest nothing stands.

`kParserVer` 79 → 80 with `quality.h`'s `kIngestParserVerMirror` in the same commit (the fork carried 79,
which the Elixir and ES-import bumps had already taken — re-bumped to the next free number over the merged
tip, per the rule in `src/ingest_cache.h`); `kCacheVersion` stays 16, no record shape moved. Gates:
`test/rubyscopecheck.sh` (scope shapes, the `Scope::name` selector, the overload split, facade delegation,
Rule 1 pins, a hoist mutation, determinism), `test/rubysettercheck.sh` (definitions, write vs read edges,
the explicit `w.name=(4)` and chained `w.inner.name = 5` spellings, four stated floors, `--callers` on both
names, a write-to-read mutation, determinism) and `test/lpincheck.sh` arm (I). Both new gates were run
against the PRE-fix binary and fail there (18 and 12 failing assertions), which is what makes them evidence.


## [0.4.0] — 2026-09-06

**This section spans everything since 0.2.2, not since the last tag.** v0.3.0 through v0.3.8 were cut
and published as release binaries without changelog sections of their own; rather than reconstruct nine
retrospective entries from the log, the work they carried is recorded here, in the release that first
documents it. The tags remain valid — they are what `scripts/install.sh` served while they were latest.

### Added — `--plan-lanes` now recommends a Codex model and reasoning effort per lane

Every lane carries an advisory `execution` object with a current Codex model, reasoning effort, the
deterministic policy rule that selected them, and the complete structural signals used by that rule.
The recommendation labels itself `basis="structural-only"`; partial test evidence, name-based call-graph
resolution, and truncated evidence are disclosed as in-band caveats for the orchestrator to override.
The additive JSON field keeps the top-level schema at `v: 1` and versions its policy independently as
`codex-lane/v1`.

### Changed — `.gitignore` is honoured by default; `--no-ignore` restores the old walk

ripwire is named for ripgrep, whose defining default is that ignored files are not searched. The crawl
walked them. In a git work tree it now consults git's own ignore rules and skips what the repository
already declared uninteresting — `node_modules/`, `.venv/`, `target/`, `build/`, `dist/`, whatever the
repo says — and **`--no-ignore` restores the previous behaviour exactly**.

Measured on this repository's own root with no `--exclude`, three checkouts under a gitignored
`bench/external/`: `files=` 8,674 → **1,522**, cold 2.81 s → **0.52 s**, warm 0.63 s → **0.10 s**, and
the result agrees to the file with the hand-written `--exclude=bench/external` the tool used to need.
The ignore lookup is one `git ls-files ... --directory` per root: 0.020 s (ugrep), 0.030 s (rocksdb),
0.150 s (duckdb), 0.032 s (this root) — `bench/PROFILE.md` carries the ledger.

Nothing is dropped silently. The map header states `ignored_files=` (files the rules covered, exact)
and `ignored_dirs=` (subtrees they pruned — the walk stopped there, so their contents are UNKNOWN, not
zero); both are ABSENT when the rules dropped nothing, so a tree with nothing ignored is byte-identical
to what it produced before. `--skipped` rows the ignored set and names the mode in `ignore_mode=`.
`--exclude` composes on top, and a multi-root run applies the rules per root.

Four situations keep the full walk, and `--skipped`'s `ignore_mode=` says which applied: `git` (rules
consulted), `off` (`--no-ignore`), `unavailable` (no git work tree at this root, or no git binary), and
`root-ignored` — the root is ITSELF inside an ignored subtree (`ripwire build/` in a repo that ignores
`build/`), where honouring the rules literally would hand back an empty map for a directory you pointed
at on purpose. A tracked file that happens to match a `.gitignore` pattern stays indexed, because git
ignores nothing it tracks.

### Changed — one warm cache per tree, and a narrower run no longer throws the wider one's work away

The warm-by-default cache keys on the tree's path and the verb class, and deliberately not on
`--exclude` or `--max-file-size`: one blob per tree, shared by every configuration you run against it.
That sharing had a hole. A run with an `--exclude` deserialised the WHOLE blob — including the records
for the files it had just excluded — and then, if anything had changed, rewrote the blob with only its
own file set. The next run without that `--exclude` found those files missing and re-parsed them from
scratch. Alternating `ripwire .` with `ripwire . --exclude=vendored` therefore paid a cold parse in one
direction and a superset deserialise in the other, every time.

The blob now carries a record offset table, so a run reads only the records for the files it actually
crawled, and a save carries over — byte for byte — the records for files it did not. The cache only ever
grows toward the union of the configurations that share it, so switching between them is free in both
directions.

Measured on a 31,000-file tree (1,000 files kept, 30,000 excluded), comparing `d8fa59c` with this
change. A warm excluded run: **0.06–0.09 s → 0.01 s**, now indistinguishable from that configuration
having its own private `--cache=PATH` blob. The run after a changed excluded run: **30,000 files
re-parsed in 0.96 s → 0 files re-parsed in 0.27 s**. The costs, both real: the table adds **3.3%** to the
blob (32 bytes per file), and a save that has to carry 30,000 records over takes 0.13–0.40 s where the
old truncating save took 0.02 s — which is the trade, because the truncation is what made the next run
cost 0.96 s. Full ledger in `bench/PROFILE.md`; the bands, including the earlier attempt at this that was
measured and reverted, in `docs/EVALS.md` under "The auto-cache key ignores `--exclude`".

Cache blobs from earlier versions are rejected and rebuilt on the next run, as with every format change:
no action needed, one cold parse. `RIPWIRE_CACHE_STATS=1` gains `cached_records=` and `blob_entries=`.
New gate: `test/cacheoffsetcheck.sh`.

### Added — `--slice` reaching definitions are flow-sensitive inside one definition (C-family, Python)

Every use row of `--slice=SYM:VAR` (and the MCP `slice` verb) now carries `rd=` — the lines of the defs
that reach it — computed by one structural pass over the definition's statement tree: a def is killed by
the next unconditional def of its binding on every path, defs join at `if`/`elif`/`else`, `switch` (cases
fall through, no `default` keeps the no-case path), a loop's back-edge (fixpoint), `try` handlers and
`finally`, `for`/`while ... else`, `match` and a build-dependent `#ifdef`; `return`/`break`/`continue`/
`throw`/`raise` end their path. The root says which rule is in force — `reach="cfg"` for C/C++/ObjC and
Python, `reach="linear"` (source order, nothing joins) for JS/TS, Go, Java, Rust until their control
tables are fixture-verified. `--slice-flow` and `--since` read the same reach table, so the rows, the flow
walk and the dependence diff can never disagree about an edge. The unit is the statement (uses read the
entering state, defs apply after); every construct the walk does not branch on — `?:`, short-circuit,
conditional expression/comprehension, lambda/closure/nested def/class bodies, `goto`, `global`/`nonlocal`,
the try handler's entry, aliases — is named in the legend instead of guessed. Registered and measured in
`docs/EVALS.md` ("Flow-sensitive slice in the small"): 0 wrong of 85 hand-written sentinel use rows across
53 functions, and the 57-commit `--since` labelled set unchanged at 35/35 and 22/22. Gate:
`test/sliceflowsenscheck.sh`.
### Fixed — `--expand` no longer takes minutes on a file whose lines are hundreds of kilobytes

Secret redaction (`redactSecrets`, on by default at every body-emission seam) was quadratic in LINE
length. Its low-precision `[A-Za-z0-9+/=_\-]{32,}` rule re-derived three position-independent values at
every cursor: the enclosing line's boundaries, that line's credential-keyword verdict, and — through a
greedy `regex_search` anchored at the cursor — the whole character-class run it sits in. Ordinary source
has ~100-byte lines and never noticed. A minified or vendored bundle is nothing but huge lines, and
`--expand` hands one to this path whole while pricing its whole-file candidate.

Measured on babel's `.yarn/releases/yarn-3.1.0.cjs` (2,196,921 bytes over 768 lines): a single `--expand`
selector burned 196.7 s of CPU without finishing under a manual timeout, and an unattended run was killed
at 1,343.9 s of user CPU with a still-empty output file. It now answers in 0.46 s warm. On a
self-contained 20 KB-single-line fixture, 23.02 s → 0.017 s. Each of the three values is now computed
once per line or per run, which makes the sweep linear.

This is an output no-op — same matches, same gate verdicts, same bytes — verified byte-identical on
stdout, stderr and exit code against the pre-change binary over 24 corpora (20 of them external
multi-language snapshots) × 5 verb shapes. New gate: `test/redactfixcheck.sh`. Ledger row and the
`sample(1)` breakdown in `bench/PROFILE.md`.

## [0.2.2] — 2026-08-09

### Fixed — a local variable that shadows a function name no longer steals that function's use-sites

`--uses` attributed a local's read/write sites to a same-named function (13 false sites on one
measured query). A local binding now claims its own scope, and a `using ns::name;` re-export emits
the `role="import"` row it never produced. Measured against a `scip-clang` oracle on this
repository, site-level precision/recall moved 0.9046/0.9285 → 0.9136/0.9412, with the worst
motivating query going 0.6579 → 0.9615 and three others reaching 1.0000. The suppression took three
refutation rounds to get right, and the third found a **recall loss the first cut introduced**: a
genuine call appearing ABOVE the shadowing local vanished entirely, because the suppression span
started at the enclosing block rather than at the declaration point. It now begins at the end of the
complete declarator, C++ [basic.scope.pdecl]. Fixture corpora, per-round verdicts and the verifier
history: `bench/fixround/RESULTS.md`.

### Fixed — five more shapes that invented or destroyed references

A declared name no longer leaks as a read of the symbol it shadows under a defaulted parameter, a
parameter pack, or an attributed declarator. A bare-identifier assignment (`x = y;`) mints a
function-pointer binding only when the file's own declarations allow it, and a class-typed copy no
longer does — closing a bug that was **losing real call edges**, not merely adding false rows: a
bogus binding tombstoned a genuine same-named file-scope binding corpus-wide. Zero call-edge loss
verified on two corpora (10,742 edges here, 39,741 on a 2,376-file ObjC++ tree, byte-identical
before and after); 59 false `--uses` sites removed with zero sites gained. One deliberate behaviour
change is disclosed in the count-floor legend: a variable whose function-pointer typedef lives in a
HEADER is now missed, because same-file alias evidence cannot distinguish it from a value copy.

### Changed — `--uses` states that a bare type mention is not a use-site

The role list is the whole vocabulary. Naming a symbol as a type in a signature, a declaration or a
template argument contributes no row, so a caller that only names it as a type is absent from the
count. Previously true and unstated; now stated in the legend. A `role="type"` reference class
remains the fix rather than the disclosure, and is recorded as such.

### Added — the oracle-scored reference-precision receipt

`bench/headtohead/r9-2026-08-09/` publishes the round behind the README's silent-miss claim: 68
answers scored against a `scip-clang` index, six imperfect, four self-flagged, and the two unflagged
traced to files the oracle could not see. It reports the comparison in both directions — an
LSP-backed tool is more precise, by ~1.5 points after these fixes, with recall now equal — along
with the protocol asymmetry that inflates one of our own rows and four limits that travel with the
numbers, including that the corpus is this repository.

### Changed — the held-out recall lane now scores a frozen doc corpus

`bench/recalleval/`'s recall lane no longer measures the live repository's docs: it unpacks
`snapshot.mdpack` — every tracked `*.md` at the commit pinned in `snapshot.lock` — into a temp root
and scores that, so its recall/MRR floors trip only on a ranker regression. The change closes a
standing defect: the lane's floor had been ratcheted 85→83→78→69 in five days purely by corpus
composition (documents joining, or even just growing, moved BM25 length normalization), with ranker
neutrality proven at every step — the forensic record is `test/recallevalcheck.sh`'s header. The
live tree keeps its own signal: a `recall_livepol` probe re-runs the same queries against the live
root and reports pollution@5 (ceiling 16% unchanged). Frozen bars: lenient recall@5 76.2% baseline /
floor 71; lenient MRR 0.619 baseline / floor 0.57. Corpus integrity is a content hash verified as
the gate's first check; refreshes happen only in deliberate recalibration commits
(`bench/recalleval/make_snapshot.py --freeze`). Method and bars: `docs/EVALS.md`.

### Fixed — nested JS/TS closures no longer inherit the enclosing function's metrics

Cross-codebase validation on webpack found a systematic extraction bug: a named const-closure
nested inside another function's scope (`const f = (..) => {..}` inside a function body) reported
the ENCLOSING function's loc/cx/ccx/nest/params instead of its own. In webpack's
`lib/html/syntax.js`, all eight closures inside the ~3400-line `tokenize` arrow reported identical
loc=3439 cx=487 params=3; the same happened under anonymous enclosers
(`module.exports = (..) => {..}` in `lib/util/deterministicGrouping.js`). Root cause: the tags-pass
body-climb (built for C++'s `function_declarator` → `function_definition` hop) adopted the first
ancestor owning a `body` field — for a nested closure that ancestor is the *enclosing*
`arrow_function`, whose whole span the closure then stole; `statement_block` was missing from the
climb's scope-stop list, so only nested (not top-level) defs escaped upward. The climb now refuses
any ancestor whose body *contains* the definition — a grammar-agnostic containment stop. Call-edge
attribution rides the same spans, so calls in the encloser's body now attribute to the encloser
instead of the last span-stealing closure. On webpack, unambiguously individually-scoped `nest>=4`
rows went from ~18% to 98% (django's healthy Python baseline: 89%). `kParserVer` 41 → 42 (cached
spans carry the bug). Gate: `test/jsnestedcheck.sh` on `test/jsnestedfix/` — hand-counted
loc/cx/params/nest for both shapes, JS and a byte-identical TS twin.

### Added — `--skipped`: itemize the header's `skipped_oversize=` count

The map header has long disclosed *how many* otherwise-indexable files the crawl dropped for
exceeding a size ceiling (`skipped_oversize=N`, absent when zero) — but nothing anywhere named
*which* files, so a reader could know the corpus was truncated without being able to say what was
absent from it. `--skipped` names them: one `<f p= bytes= limit=/>` row per dropped file, path-sorted,
where `limit=` is the ceiling that dropped the row — `--max-file-size`'s value, or the fixed 256 KB
`.json` config ceiling that flag does not raise; the root element repeats both effective
ceilings so a zero-row report still states its bounds. The accounting invariant is unchanged and now
itemizable: `files=` + `oversize=` = the population the crawl considered, at every `--max-file-size`.
Multi-root workspaces list rows under the same `<label>/./<rel>` spelling every other surface emits.

Scope is deliberate: the parse-time binary-sniff and read-failure skips are *not* listed, because
those files keep their `fileId` and stay inside `files=` (present with zero symbols) — they are not
absent from the accounting this verb itemizes. The default map is byte-identical (G5: purely
additive; the header count was already there). Read-only; exit 0 always. Gate:
`test/skippedcheck.sh`.

### Added — `--dmm`: the Delta Maintainability Model, one comparable number per change

`--quality-delta` reports *which kinds* of debt a change added. It has no scale, so it cannot answer
"was this change better than the last one?" — `--dmm` is that scale: one scalar in `[0,1]` per commit
or per working diff, trendable across commits and comparable across authors.

```
<dmm base="2edbb46cfd9d…" target="working-tree" available="1" combine="pooled"
     size_metric="physical-loc" dmm="0.436" good="462" bad="597"
     base_units="4759" base_volume="86331" target_units="4780" target_volume="86684">
  <p k="size"        dmm="0.184" good="65"  bad="288" d_low="65"  d_high="288"/>
  <p k="complexity"  dmm="0.499" good="176" bad="177" d_low="176" d_high="177"/>
  <p k="interfacing" dmm="0.626" good="221" bad="132" d_low="221" d_high="132"/>
```

A *unit* is a function or method definition with a body; its *volume* is its line span. Per property a
unit is **low risk** iff `loc <= 15` (size), cyclomatic `cx <= 5` (complexity), `params <= 2`
(interfacing). `good` is low-risk volume **added** plus high-risk volume **removed**; `bad` is the
reverse; `dmm = good/(good+bad)`. **Deleting a god function scores 1.000; growing one scores 0.000.**
The three sub-scores ship alongside the combined one because they are separately actionable — a low
`size` with a healthy `interfacing` says *split the function*, not *change the signature*.

Three spellings: bare `--dmm` compares the **working tree** against `git HEAD` (what `--quality-delta`
compares); `--dmm=REV` scores one commit against its **first parent**, the per-commit scalar; and
`--dmm=A..B` scores tree B against tree A. Multi-root workspaces refuse — pooling two histories into
one ratio would mean nothing.

**It is a delta, never a level, and that is the whole design.** A unit you edit without changing its
size, complexity or parameter count sits in the same bin with the same volume on both sides and
contributes exactly zero to both `good` and `bad`. You are not punished for touching pre-existing bad
code, because a gate that punishes touching a mess is a gate people route around. For the same reason
the verb has no threshold, renders no verdict, and always exits 0.

**`dmm="UNAVAILABLE"` is not a score.** When `good + bad` is 0 — a rename, a literal edit, a comment
reflow — the change is outside what the model measures, and the report says so in `reason=` rather
than picking the flattering default. It is never 1.000 and never 0.000. The same token appears per
property: a commit that only adds parameters leaves `size` and `complexity` UNAVAILABLE while
`interfacing` is measured.

**Lineage, and the one deviation.** The model is di Biase, Rastogi, Bruntink & van Deursen, TechDebt
2019 (SIG). The three risk thresholds and the exact good/bad asymmetry are PyDriller's
`deltamaintainability` reference implementation, read out of `pydriller/domain/commit.py` rather than
re-derived from the paper's prose — including the 0/0 case, whose `None` is where UNAVAILABLE comes
from. The deviation is disclosed on every report as `size_metric="physical-loc"`: PyDriller's volume
is lizard's non-comment `nloc`, ripwire's is the definition's physical line span, so a heavily
commented unit crosses the size threshold here earlier. The combined score is labelled
`combine="pooled"` because the paper publishes the three properties separately and no aggregate.

Gate: `test/dmmcheck.sh` — a hand-built git repository whose every commit has a pencil-derivable
answer (delete-only-high-risk → 1.000, grow-a-god-unit → 0.000, a 4-good-vs-4-bad mix → 0.500, a
literal-only edit → UNAVAILABLE), both sides of all three thresholds pinned (15 vs 16 lines, cx 5 vs
6, 2 vs 3 params), plus the root-commit, non-git, refusal, determinism, well-formedness, legend and
additivity arms.

### Added — `--nonlocal-state`: the mutable state a function can reach, reads and writes kept apart

A new lens: for every function and method, the non-local **mutable** state it — or anything in its
transitive callee closure — reads and writes, as two separate sets, with the site or the callee that
explains each one. A *cell* is a file- or namespace-scope variable, a function-local `static` (local
in name only), or a Python module global; a `const`/`constexpr`/`consteval` declaration is not a cell,
so a large `writes=` is genuinely shared mutable state and not a table of constants.

```
<fn p="src/infra/profilePmc.h:288" n="ensure_global_init" writes="2" reads="3"
    direct_writes="1" direct_reads="3" cells_total="3">
  <cell n="g_perf" p="src/infra/profilePmc.h:284" dir="rw" at="src/infra/profilePmc.h:339" at_dir="rw"/>
```

`writes=`/`reads=` fold in the callee closure, `direct_*` is what the body does itself, and each cell
child carries `dir=r|w|rw` plus either `at=` (a use site here, with `at_dir=` for what *this* body does
— it can be narrower than `dir=`) or `via=` (the nearest callee that touches it). Rows are ordered
most writes first; pages with `--limit`/`--offset`.

**Direction is the point, and it is not new.** Henry & Kafura's 1981 information-flow metric already
separated what a procedure reads from what it writes; folding them into one number discards the half
that is a hazard for everyone else. The lineage is recorded in full in
[`docs/LINEAGE.md`](docs/LINEAGE.md) — Fowler's **Global Data** / **Mutable Data** smells (2018), which
name this hazard and ship no metric; **Marinescu's ATFD** (ICSM 2004), the closest existing number and
one-hop, per-class, Java and direction-blind; **QMOOD DAM** and **MOOD AHF/MHF** (Bansiya & Davis, TSE
2002), which count *declared visibility* and therefore score a class with private fields and leaked
mutable internals as perfectly encapsulated; **Potanin, Noble & Biddle 2004**, the only published
*measurement* of externally reachable state, which is dynamic, Java-only and tooled with something
unmaintained; and **Meyers & Binkley** (TOSEM 2007), whose slice-based coupling already puts globals in
its output set, so the delta — per function rather than per variable, over the call graph rather than a
dependence graph — is argued in the source header rather than asserted. **The folklore term "action at
a distance" is deliberately not used**: it has zero academic presence and naming the feature after it
would have been the one indefensible choice available.

**It is unsound, and every count says so.** `counts_floor="1"` is on the root. The analysis cannot see
an indirect call (function pointer, virtual, callback, macro-generated call site), a write through a
pointer or reference that aliases a cell without naming it, a cell named only inside a macro, or
reflection-like dispatch — each of those makes the count too low. In the other direction, a local that
*shadows* a cell's name is charged to the cell unless ingest recorded a type binding for it. The
report's own legend names all of these where the reader meets them.

**Scope, stated rather than implied.** It covers **C++, ObjC and Python** — the languages for which the
index carries read/write use sites at all (`captureUses`, `src/ingest.cpp`). Every other indexed
language is named on the root as `unanalyzed_langs=` with a file count, because a Go or Rust corpus
would otherwise report a confident, wrong zero. Widening the lens means widening `captureUses` first,
with its own gate; adding a declaration rule alone would not do it, and the source header says so.

Gate: `test/nonlocalstatecheck.sh` (12 arms) — a hand-derived golden over a two-language fixture, a
mutation control that turns one cell `const` and must go red, plus determinism, direction, provenance,
paging, additivity and XML well-formedness.

### Added — `--field-affinity[=STRUCT]`, the cache-locality lens (advice only, and validated)

Which fields are **read together but declared far apart**. Every shipping struct-layout tool answers
"where are the holes?" — pahole, clang-analyzer `optin.performance.Padding`, PVS-Studio V802, Go
`fieldalignment`, `-Wpadded`. None answers this one. The verb builds a static field **co-access
affinity graph** (one observation per indexed C-family function body) and diffs it against the declared
field order and 64-byte cache-line geometry, reusing `--layout`'s LP64 offset model rather than
re-deriving it. Bare form ranks every aggregate in the repository by separation cost; `=STRUCT` narrows
the report.

**Almost none of this is new, and the output says so in its own legend.** The affinity graph, the
points-to-free static access enumeration (`<function, struct type>`, an approximation its authors
conceded), the separation weight `wt(fi,fj) = (block − dist)/block` reproduced verbatim, and
hardware-counter validation of layout work are all Chilimbi, Davidson & Larus, *Cache-Conscious
Structure Definition*, **PLDI 1999**. The advice-instead-of-transform posture and per-field counter
attribution are Hundt, Mannarswamy & Chakrabarti, **CGO 2006**. What is new is narrow and is
engineering: a *source-level, no-debug-info, whole-repo-ranking* delivery — pahole needs DWARF, Hundt's
was one proprietary compiler on a dead architecture, `lshaz` is Linux-x86-only and answers the inverse
(false-sharing) question.

**Exactly two findings fire**, both with a direction defensible in one sentence: `split-line` (two
fields co-accessed by ≥2 distinct functions at `wt == 0.00`, so no field order can put them on one line)
and `straddle` (one co-accessed field crossing a line boundary). **Pack-tighter and sort-by-size advice
is deliberately absent** — the Go team excludes its own `fieldalignment` analyzer from `vet` and `gopls`
because the diagnostics "very rarely indicate a significant problem" and tight packing can induce false
sharing. There is no rewrite mode and the verb never exits non-zero: five compiler attempts at automatic
field layout are dead (GCC `-fipa-struct-reorg`, LLVM heap SRA, esan, StructFieldCacheAnalysis,
Qualcomm's AoS→SoA RFC), every one that died on soundness died because a *compiler* must prove a pointer
points at a pool of that struct. Advice cannot miscompile.

Limits, in every header rather than in a footnote: `counts_floor="1"` (`fns=` counts distinct indexed
functions, never dynamic frequency; `w=` is a fan-in reachability *proxy*), `model="lp64-approx"` (a
definition `--layout` marks `modeled="0"` contributes its affinity graph and no geometry finding), only
dot/arrow member syntax is counted, and a field name declared by two aggregates is **refused** and
tallied in `amb_skipped=` rather than guessed.

**The validation half is real, and it refuted the hypothesis in one regime.**
`bench/bench_field_ab.cpp` builds the two layouts the lens compares and measures them through
`prof::pmc` — ripwire's existing counter backend. On an Apple M5 Pro, 64 MB per arm, five repeats per
stride: the flagged layout is 4–41 % **slower** at strides 9/1025/4097, mixed at 129, and ~2× **faster**
under a fully sequential sweep — where the packed arm moves *less* data and still costs more time,
because a single 64 B touch per 256 B element is a sparser stream than two. Hardware counters were
**UNAVAILABLE** in that run (kperf needs root on macOS) and the harness says so rather than implying
confirmation, so the *mechanism* claim remains unconfirmed. `docs/FIELDAFFINITY.md` records all of it,
including the honest reading of the lens's own #1 result on ripwire's source (`MainDispatch` — real
static separation cost, almost certainly nil dynamic cost, which is limit (1) visible in the top row).
Gate: `test/fieldaffinitycheck.sh` over `test/fieldaffinityfix/`, whose every offset is hand-computed in
the fixture's own comments.

### Measured — `--ensemble`'s four families are near-orthogonal; one of them cannot carry a gate

A calibration pass over **nine trees (five independent, 27 889 eligible functions)** spanning C, C++,
ObjC/ObjC++, Metal, Rust, Swift, Python, TypeScript and Bash. No behaviour changed: the new
`bench/ensemblecal/` harness reads `--ensemble`, `--readability` and `--metrics` and computes
nothing of its own. Full numbers, per corpus and pooled, in [`docs/EVALS.md`](docs/EVALS.md) §9.

- **The ensemble premise holds.** Largest cross-family correlation anywhere: **φ = +0.278**; pooled
  over the independent corpora no pair exceeds **+0.168** and the largest overlap between any two
  families is Jaccard 0.119. The four families are not one signal wearing four hats.
- **`historical` is disqualified from gating, on measurement.** Across three commit ladders (148 /
  792 / 1 620 first-parent commits) its flagged set has mean consecutive Jaccard **0.800–0.862** and
  endpoint Jaccard **0.426–0.546**, against 0.920–1.000 for the other three.
- **Three named presets, derived from that**: `lenient` = all four families, `fam ≥ 1` (32.22%
  pooled); `default` = all four, `fam ≥ 2` (4.39%); `strict` = structural + lexical + confusion,
  `fam ≥ 2` (2.34%) — strict is a *selection*, not a higher K, and its output set is both smaller and
  measurably steadier than `fam ≥ 3` over all four.
- **Two honesty defects found and recorded, not fixed here.** The `confusion` family is gated to
  C/C++/ObjC but does not declare itself unavailable on a corpus with no C-family file (it fires 0 of
  4 068 on a Rust tree while still counting inside `of=`); and the "worst decile" ordinal cut is
  capped at 40 rows, so its realized width is **0.23%–8.81%**, not 10%.

### Added — `--cochange` grows the three things the papers behind it already had

`--cochange`'s `surprising="1"` predicate is an independent implementation of published work, now
cited in [`docs/LINEAGE.md`](docs/LINEAGE.md) §2 (Wong/Cai/Kim/Dalton, ICSE 2011 — the Clio tool;
Mo/Cai/Kazman/Xiao, IEEE TSE 2019; Gall/Hajek/Jazayeri, ICSM 1998; Code Maat in §3a). Reading those
against the shipped predicate produced three additions:

- **`recur=` and `sub_windows=` on every row.** Clio does not report a discrepancy the first time it
  appears — it mines frequent patterns over the last five releases and reports only recurring ones.
  ripwire mined one window, in which a one-week refactor sprint and an eighteen-month structural
  defect both score `together=4`. The window is now cut into equal-**commit-count** sub-windows
  (equal time would make the number a function of when the team took holiday) and `recur=` counts how
  many contain a joint commit. `--cochange-recur=K` filters on it and the header publishes
  `min_recur=` so a shortened list is explained. Measured on a 1,648-commit, 2,718-file C++/ObjC++
  corpus: `recur>=2` removes **45%** of the surprising pairs (253 → 140) and `recur>=3` removes
  **81%** (253 → 47).
- **`--cochange-groups`.** Mo's Modularity Violation Group is the minimal set of *groups* covering the
  violating pairs, not a pair list — "X co-changes with {A,B,C}, none of which it depends on" is one
  row that names the file to fix. Same corpus: 253 pair rows collapse to **65 groups** (3.9 pairs per
  group). The cover is greedy and says so (`cover="greedy"`); minimum set cover is NP-hard, so
  `groups=` is an upper bound on the minimum, never the minimum.
- **`conf_ab=` / `conf_ba=` / `driver=`, and `conf_rev=` on the per-file form.** Clio's confidence is
  asymmetric — `conf = frq(x1 ∪ x2)/frq(x1)` — so "A always drags B" is distinguishable from the
  reverse. ripwire's `deg=` divides by the quieter file, which is exactly the *larger* of the two
  directions with the direction discarded; both are now emitted, `deg=` is documented as their max,
  and `driver=` names the antecedent of the stronger rule. A tie emits no `driver=`.

Calibration is published with the feature rather than after it. Clio reports 66% precision on Hadoop
Common and 40% on Eclipse JDT; ripwire's measurable analogue on the corpus above is a **yield** of
59.8% (flagged pairs over dependency-capable candidate pairs), which is not the same quantity — see
[`docs/EVALS.md`](docs/EVALS.md) §7 for what was measured, what was not, and the upper bound on
precision it supports. **Correction, still pre-release:** that 59.8% was measured on an index with a
capture gap (guard-wrapped `#include`/`#import` never seen), fixed in `ba82324` (`kParserVer` 40); the
re-measured yield on the same corpus is 52.2%, with the composition-derived precision ceiling moving
from ≤67.6% to ≤64.3% — now inside Clio's 40–66% band rather than a hair above its top. `docs/EVALS.md`
§7 carries both figures and the full re-derivation; this entry is left as originally written except for
this note, per the project's own rule against silently overwriting a published number.

Gate: `test/cochangecliocheck.sh` (29 arms over a scripted 24-commit fixture repo whose oversized base
commit also proves the 30-file bulk cap still fires).

## [0.2.1] — 2026-08-05

Linux portability patch. The v0.2.0 Linux archives were built on `ubuntu-24.04` and required
`GLIBCXX_3.4.31`, so they died on RHEL 9 and older (verified on ubi9). The Linux release legs now
build inside AlmaLinux-8-based `manylinux_2_28` containers with Red Hat gcc-toolset 14 — newer
libstdc++ symbols link statically (the devtoolset model), so **one binary per arch covers
RHEL/Alma/Rocky 8+, CentOS Stream, Fedora, Ubuntu 20.04+, and Debian 11+** (glibc 2.28 floor;
verified on ubi8, ubi9, ubuntu:22.04, ubuntu:24.04). A new `smoke-rhel` CI job runs the packaged
tarball on a RHEL 9 (ubi9) userland and gates publish. Also: `bench/representative_perfgate.sh`
byte counting is now GNU-portable (`stat -f %z` is BSD-only and zeroed the corpus-shape preflight
on every Linux CI leg). No library or CLI behavior changes.
### Added

- **Optimization-remarks build and triage** — `-DRIPWIRE_OPT_REMARKS=ON` (a separate tree; refused by
  name inside `build/` and `asan/`) collects clang's `-Rpass*` remarks plus a YAML opt-record, and
  `scripts/optremarks.sh` / `scripts/optremarks.py` turn it into a ranked report. `docs/OPTREMARKS.md`
  carries the full triage of the first pass over `src/`, and `skills/ripwire-opt-remarks/` carries the
  remark→fix patterns that survived it. New gate: `test/optremarkscheck.sh`.
- **`-DRIPWIRE_LTO`, now ON by default** — link-time optimization. The first change the remarks pass
  justified: 397 of 636 distinct `inline/NoDefinition` sites in `src/ingest.cpp` name a tree-sitter C
  accessor, inside the two phases that are ~31% of a cold run, and no source edit can reach a
  cross-TU definition. Measured on this repository as corpus (937 files, Apple Silicon) across four
  independent interleaved A/Bs of 9/21/21/31 runs per arm: **cold 1–6% faster, warm 0–3%**, with
  every cold statistic in every run favouring LTO and one run's warm min going the other way — the
  per-run table is in `docs/OPTREMARKS.md` F1, and the range is the claim, not its best row. Output
  is byte-identical and the determinism gate passes on the LTO tree. It costs link time — a rebuild
  after touching `src/main.cpp` goes 34 s → 89 s — which is not a reason to decline a faster binary;
  `-DRIPWIRE_LTO=OFF` restores the fast edit loop. **Note:** `option()` never overwrites an existing
  cache entry, so a build tree configured before this change keeps `RIPWIRE_LTO:BOOL=OFF`; delete the
  tree to pick the new default up.
- **`-DRIPWIRE_PGO=generate|use` and `scripts/pgobuild.sh`** — profile-guided optimization, and the answer to the remark classes LTO cannot touch: `inline/TooCostly` and
  `loop-vectorize/VectorizationNotBeneficial` are the cost model guessing at hotness, and a profile
  replaces the guess with counts. **Cold 14–25% faster than a non-LTO build (6–16% over the shipped
  LTO default), warm 5–10%**, measured on this
  repository *and* on a ~2000-file C++ tree that appears in no training run — six interleaved A/Bs,
  two corpora, two independently built PGO binaries, every statistic favouring PGO. Output is
  byte-identical on both corpora; the determinism gate passes three times on the PGO tree. `pgobuild.sh` runs instrument → train → merge →
  rebuild as one command. Honest G3 tension, stated in `docs/OPTREMARKS.md` F2: this is two configures
  and a training run against a one-build-step guardrail. The `.profdata` is deliberately not committed
  (a stale committed profile is a clang warning, not an error), and `RIPWIRE_PGO=use` **fails the
  configure** when the profile is missing rather than silently producing an ordinary binary.

## [0.2.0] — 2026-08-04

The first binary release: portable archives for macOS arm64/x64 and Linux arm64/x64, each with a
SHA-256 file, built by `.github/workflows/release.yml` on the tag push. Includes everything from the
asset-less `v0.1.0` tag plus the language definition-shape rounds (TypeScript, JavaScript, Python,
Swift, CUDA memory-space capture), the 2026-08-04 audit hardening (cache isolation, honest
lint/doc-drift behavior, transitive test reachability, skill routing, Codex plugin/CLI setup), and
the Codex CLI benchmark harness under `bench/agentloop/`.

### Added — retrieval and ranking

- **`--for=TASK`, the task lens** — ranked signatures + metrics framed for reuse, matching doc
  comments and bodies rather than names alone.
- **Query-shape routing, on by default.** A deterministic, confidence-gated router picks name-exact
  BM25 when the query *names* a symbol (identifier syntax, or every content word is a symbol name)
  and subtoken+body BM25 otherwise, and prints which it chose and why in the header. `--no-route`
  restores the single-ranker behavior.
- **Query-mention anchoring, on by default.** A file, dotted module, or `Type.method` literally named
  in the task text — even inside a URL — is lifted to just below the top hit, and the header names
  what anchored. Byte-identical output when the text names nothing indexed. Disable per run with
  `--no-mention-boost`, or everywhere with `RIPWIRE_NO_MENTION=1`.
- **Doc-mention surfacing on `--for` / `--pack-task`, on by default.** A markdown document that names
  one of the task's top-resolved symbols in backticks is lifted into the bundle, ranked strictly
  below that symbol's own score — closing the case where the design note explains a symbol but shares
  no vocabulary with the query. Bounded (top-8 anchors, 2 docs per anchor, 6 docs total) and
  downweighted (0.55× the anchor's score) so code still dominates a code-shaped query. Byte-identical
  when nothing resolved has a mentioning document. Opt out with `--no-doc-mention` or
  `RIPWIRE_NO_DOC_MENTION=1`. Reuses the existing doc↔code edges `--mentions=SYM` already exposed —
  no new parser, no cache-format change.
- **`--adaptive`** cuts a result set at its relevance cliff (largest relative score gap) instead of a
  fixed *k*, with a floor of 5 and the existing top-K as the ceiling; the header reports what it kept.
- **`--recall=TASK`** returns the most relevant *documents* in full — memory notes, plans, designs,
  READMEs — with the header disclosing the true relevant count, what was shown, and every cut.
- **`--pack-task="TASK"`** — ranking, top bodies, caller signatures, notes and tests-to-run in one
  bundle under one budget.
- **`--exemplar`** returns the repository's best-in-class instance of what you are about to write,
  chosen by *role* (lowest cognitive complexity under a hard ceiling, then tested, then highest
  fan-in) rather than text similarity.
- **`--detail=N`** spends body tokens only on the top-N ranked symbols and emits signatures for the
  rest, in one call.
- **`--pack-signatures`** emits body-elided declaration skeletons. See `docs/EVALS.md` for the
  measured byte reduction, its root-neutralisation methodology, and the honest counterexample.

### Added — navigation and the call graph

- **`--callers` / `--callees` / `--uses` / `--impact` / `--around` / `--path` / `--connect`** — 1-hop
  in-edges, 1-hop out-edges, every statically resolvable use site (call/read/write/import/extends),
  the transitive blast radius, the ego graph, a directed shortest path, and the minimal connecting
  subgraph over 2..16 symbols (which finds the shared-caller join a directed path cannot).
- **`--graph-query=EXPR`** — a small closed expression language over the symbol graph: sources
  (`name("X")`, `all`), filters (`kind`, `cx`, `fanin`, `file`), bounded `callers`/`callees` closure,
  and `and`/`or`/`not` joins.
- **`--grep` / `--regex` / `--match`** — literal search, regex search, and tree-sitter structural
  (shape) queries, each reported with its enclosing symbol.
- **`--from-trace=FILE`** (`-` for stdin) maps a stack trace, sanitizer report, or compiler error onto
  indexed symbols, ranked innermost-first, with the innermost in-corpus symbol's body included.
- **`--external-surface`** lists names referenced but never defined in-corpus. A name called from
  several languages gets one row per language rather than a merged count, because the referencing
  file's language is what the row reports.

### Added — change safety and review

- **`--affected` / `--situ` / `--test-gate`** as one family: plumbing (changed files or a changed
  symbol → the tests that reach them), the mid-task report (blast radius + tests + co-change
  partners + hotspot alert), and the pre-PR gate (tests to run + the untested blast radius, exit 4
  if either obligation is non-empty).
- **`--exercises=TESTFILE`** is the inverse: the non-test symbols a test file transitively calls into.
- **`--edit-check=SYM`** — did this symbol's contract (parameters, publicness) change against HEAD,
  and which callers are now provably incompatible?
- **`--pr-context[=BASEREF]`** — per-file blast radius, tests to run, and hotspot flags for a diff.
- **`--merge-scout=REF1,REF2,…`** — pairwise conflict sites (same-symbol vs same-file) plus a
  suggested landing order.
- **`--quality-delta`** reports only what a change made *worse*, across ten measured failure modes,
  comparing against git HEAD. `--quality-ack` records a reviewed exception; `--ack-only=KIND` scopes
  the acknowledgement.
- **`--plan-lanes=N --task="GOAL"`** predicts, before a line is written, which parallel work lanes
  would collide. Deterministic JSON on stdout: per-lane file and symbol claims, blast radius, the
  tests each lane must run, and a landing order sorted fewest-conflicts-first. Conflict pairs are
  classified `conflicts`, `same_file_risk`, or `contract_touch`.
  - It **exits 0 even when conflicts are predicted** — conflicts are output, not a failure signal.
    Do not wire the exit code as a CI conflict gate.
  - Pre-hoc: no ref to resolve, no second ingest. ~0.1 s warm *(measured on this repository)*.
  - Read-only. The tool never writes the plan; redirecting stdout is the entire write path.
  - Lane claims are keyed on `(path, scope, name)`, not on symbol `id`. Rows still carry `id` for
    addressability, but it is `null` where it would be ambiguous, with `id_addressable` and
    `id_collides_with` stating the residual ambiguity. *(Measured on this repository: 343 `id` values
    name more than one symbol — 29.3% of symbol rows, 1426 colliding across files.)*

### Added — cross-branch archaeology

- **`--stray-content[=SUBSTR]`** — for each local ref, the lines its own divergent work authored that
  the live line does not have, with a `merged` / `superseded` / `unmerged` verdict. **`superseded` is
  the case `git cherry` structurally cannot see**: cherry compares commit ancestry, so a fix the live
  line re-implemented differently stays "unmerged" forever. Evidence is the *deletion site* — both
  sides diff the same base, so "ref R deleted base line L" and "HEAD deleted base line L" compare
  exactly, with no fuzzy matching. A pure-addition file falls back to a high-bar similarity lane, and
  every file row prints its raw `del=` / `redone=` / `sim=` numbers so the verdict is auditable.
- **`--whereis=SYM`** — which ref's tree defines or mentions a symbol, HEAD first, scanning each ref's
  full tree, with `on-head="0"` naming the case the verb exists for.
- **`--eval-stray=FILE`** — labelled verdict-accuracy evaluation (TSV `ref<TAB>verdict`), exit 3 on
  any regressed case. A confusion table rather than a ranked-set metric, because a verdict verb
  classifies. Supersession thresholds were chosen against hand-labelled branches, so changing one is
  an experiment rather than a guess.
- Both cross-branch verbs are keyed by **blob sha**. Branches off one trunk share nearly all blobs,
  and every byte-level fact is a pure function of blob content, so blobs stream through one
  `git cat-file --batch` per run and are reduced to fixed-size facts on arrival — peak memory is
  bounded by the facts, not by the trees. *(Measured on a 35-branch repository: `--whereis` read 4,445
  distinct blobs where HEAD's tree alone holds 2,897 — 35 refs for 1.53× one tree, 1.6 s.
  `--stray-content` is diff-scoped: 443 blobs, 2.2 s.)* Both use only `cat-file`, `diff`, `ls-tree`
  and `merge-base` — read-only by construction.

### Added — dark code and feature flags

- **`--flags[=SUBSTR]`** — one report over what is built but not switched on: `#ifndef`/`#define`
  header gates, CMake `option()`s, and `getenv()` reads, with kind, default, guarded regions and LOC,
  and read sites, dark entries first. *(On the motivating private repository it named 94 dark gates
  of 102.)*
  - When a name is both a header gate and a CMake option, **the CMake default wins** — it is what the
    build actually passes — and the losing definition is shown as an `<also>` row, so the
    contradiction is surfaced rather than silently resolved.
  - Alias chains resolve (`#define F_WALLS F_ALL`): a child inherits its master's default and rolls
    its guarded size up, so a master switch shows its alias count instead of a misleading `loc="0"`.
- **`--flags --flip=NAME`** answers the follow-up: if this one gate flips, what becomes live and what
  covers it? Reports the code that becomes live (`#if` regions **and** C++ branch sites), the hosts,
  downstream and dependent symbols, the tests reaching those hosts, and **`untested`** — the hosts no
  test reaches. Flipping works in both alias directions, and three-level chains resolve correctly.
  - **Value-style gates are followed, not just preprocessor regions.** A gate consumed as
    `inline constexpr bool kWalls = FLAG != 0;` and then guarded with `if constexpr` guards a C++
    *branch*, not an `#if` region; such a gate previously reported `regions="0"` and a naive flip
    analysis would have answered "nothing lights up". *(Measured on the motivating repository: one
    gate family with 11 aliases and 0 regions yields 43 branch sites across 11 host symbols, verified
    row-for-row against an independent whole-word grep.)*
  - Flip semantics are stated per gate kind. A CMake gate becomes a `-DNAME=1` compile definition, so
    its C++ radius matches the compile case — but it also steers the build graph (adding whole
    translation units), and those sites are reported as build rows and **explicitly not followed**.
    An environment gate is marked `runtime="1"`: with no delimited region, its hosts are the symbols
    that consult the variable.

### Added — documentation drift

- **`--doc-drift[=SUBSTR]`** verifies the *checkable* anchors in every markdown file against the live
  index and reports only what no longer holds. Four anchor kinds: `file:line` references (split into
  `missing-file`, `past-eof`, and `line-moved` with `got=` naming the symbol now at that line),
  backticked symbol mentions (`undefined`), `= N` constants (`const-value`), and `[N]` array extents
  (`array-extent`).
  - **Precision is the design constraint and every lane deliberately under-reports.** A name counts as
    stale only if it occurs nowhere in any non-markdown file as an identifier token, and the presence
    corpus is the index *plus* build files, shaders and config — so a shader function or a CMake
    `option()` is never reported missing. A mention must share its line with a name the repository
    does define; a foreign-scoped mention is never treated as ours; a number is compared only against
    a declaration-shaped literal the corpus binds uniquely; fenced code blocks are treated as
    illustrations. *(Measured while tightening on this repository: the naive version emitted 329 rows,
    roughly 90% of the mention lane being library names and hypothetical examples; the shipped rules
    bring it to 110.)*
  - **`checked + unchecked == anchors` always holds**, and every declined check is named and explained.
  - Stated non-goal: prose, status lines and dates are not checked, and the verb never claims otherwise.

### Added — the git-history oracle

- **`--with-history`** (opt-in, off by default) on `--doc-drift` and `--whereis` answers "was this name
  ever in this repository, and when did it leave?"
  - `--doc-drift --with-history` splits its weakest lane three ways instead of blanket-reporting
    `undefined`: `why="deleted"` with the commit, date and file; `unchecked r="never-in-history"`; and
    `unchecked r="history-no-answer"`.
  - `--whereis --with-history` gains a `<fate>` row (`v="never"`, or `v="removed"` with commit, date
    and path) — something a tree scan structurally cannot produce, since a scan can only find content
    some ref still carries.
  - Both emit a row stating exactly what the walk did (`probed=`, `head=`, `commits=`,
    `removed-names=`, and `truncated=` when bounded).
  - **Speed.** `git log -S` has the right semantics but answers one name per process: ~126 s for 247
    candidate names on a 2,965-file application repository (~85 s even rev-range-bounded). The shipped
    probe reproduces those semantics with a single `git log --no-merges -p -U0 --no-renames` walk that
    tokenizes removed lines: **3.0 s** on that repository, **0.83 s** on this one, and O(1) in the
    number of names. `git log -G` was rejected on semantics — it matches diff *text*, so a reindent
    counts — and a `-G` alternation prefilter measured ~183 s, slower than no filter at all.
  - **Precision.** On that 2,965-file repository, 325 `undefined` rows became 80 `deleted` + 243
    `never-in-history` + 2 `history-no-answer` (75% reclassified); total drift 575 → 330, clean docs
    659 → 713. On this repository, 11 → 3 `deleted` + 8 `never-in-history`, drift 119 → 111. Every
    true positive survived, and no other drift lane moved on either repository.
  - **Cost.** Flagless paths are untouched. Under the flag, cold 0.63 s / 3.83 s and warm 0.130 s /
    0.664 s on the two repositories — about +24 ms and +40 ms over default. Results are memoized per
    (repository, HEAD sha); a commit sha is immutable, so the cache cannot go stale. The cached blob
    covers the whole repository, so `--whereis` reuses whatever `--doc-drift` built. Warm output is
    asserted byte-identical to cold.
  - **Stated limits.** It walks HEAD's own history, so a name that only ever lived on an unmerged
    branch reads as *never here* — that is what `--whereis`'s tree scan is for. Merge-only deletions
    are not seen. Evidence is a removed *line*, so a name last removed from a document is cited at
    that document (a code site is preferred when one exists). A repository past the walk bound reports
    `truncated="1"` and answers `unknown`, never `never`; names below the probe's minimum tracked
    length also get `unknown`, enforced at one choke point so absence is never readable as proof.

### Added — languages

- **TypeScript gains three definition shapes that only a real repo produces.** Validated by mapping
  `github.com/openclaw/openclaw` @`1aedd8f3` (24 658 `.ts` files, 261 760 symbols, 2026-08-04) and
  diffing the emitted `n="` set against a ground truth enumerated independently — grep over *blanked*
  source (comments and template literals stripped; that repo embeds Kotlin, Swift and JS fixtures
  inside `String.raw` templates, which otherwise fake thousands of phantom hits), then confirmed at
  AST level with `--match`. Three shapes came back at ~0 % recall, none of them present in any
  fixture: `abstract_method_signature` (76 sites) — an abstract base published its own name and
  nothing a caller could bind to; `public_field_definition` bound to an arrow (287 sites) — the
  bound-method idiom, which is a class's callable surface exactly as `method_definition` is; and a
  declarator whose value is an `as`/`satisfies` cast *wrapping* the arrow (105 sites) — the
  lazy-facade idiom that openclaw's entire public `src/plugin-sdk/` surface is written in, so every
  one of those was an exported API entry point `--for` structurally could not surface. All three now
  extract: +468 symbols and +593 edges on that corpus, **0 removed**, and byte-identical output on
  non-TypeScript trees. Deliberately still out: the object-literal `pair` form of the same syntax
  (>5000 sites there — a `--match` floor — overwhelmingly inline callbacks and mock tables, not a
  navigable surface). Known limits, disclosed in the gate: ambient `declare const/let/var` bindings
  (37 sites) do not extract, and `declare module "x"` / `declare namespace X` *container* names are
  not symbols — their members are, which is what navigation needs. Gate: `test/tsshapecheck.sh`.
- **Known limit, measured and disclosed:** the pinned `tree-sitter-typescript` (v0.23.2) cannot parse
  `typeof import("…")` once it appears in a nested type position — inside a parenthesized type
  (`(typeof import("./m.js").xs)[number]`, 235 sites) or a call's type arguments
  (`importOriginal<typeof import("./m.js")>()`, 2 087 sites, the vitest mock idiom). 1 222 of
  openclaw's 24 658 `.ts` files contain at least one. The *cost* is far smaller than the site count,
  which is the reason this is disclosed rather than paid for with a grammar-pin bump: tree-sitter
  error recovery scopes the loss to the enclosing declaration, so across all 1 222 files the total is
  ~15 definitions out of 261 760 (type-alias recall 1 607/1 614 and function recall 6 805/6 813 *within
  the affected files*). Pinned in both directions by `test/tsshapecheck.sh` §4d — if a future grammar
  bump fixes the parse, that arm fires.
- **CUDA (`.cu`/`.cuh`) is indexed**, parsed with the vendored `tree-sitter-cuda` grammar (v0.21.1,
  a generated superset of tree-sitter-cpp) under the C++ tags — no CUDA-specific query patterns,
  because the grammar aliases `kernel_call_expression` to `call_expression`. *(Measured before
  adopting, 2026-08-04 probe on the fixture now at `test/cudafix/`: under the plain C++ grammar all
  12 definitions survived error recovery, but every `kernel<<<grid, block>>>( … )` launch site
  produced no call reference — `--callers` of a kernel returned 0 — and a `__constant__` module
  table failed to extract. Losing every host→kernel edge is the Metal failure mode over again, which
  is why CUDA gets a real grammar where Metal measurably did not need one.)* `.cu`/`.cuh` map to the
  C++ language, not a language of their own, so dual-compile headers (`#ifdef __CUDACC__`) resolve
  from both the host and device halves. Known limit, disclosed in the gate: a `__constant__ float
  T[64];` module table still does not extract — the shared C++ tags constant pattern keys on
  `const`/`constexpr`, not the `__constant__` qualifier (plain `constexpr` constants in `.cu`/`.cuh`
  do extract). Gate: `test/cudacheck.sh`.
- **Qualified-call resolution across C++, Rust, C#, TypeScript, JavaScript, Java and Objective-C.**
  C++ gained qualified calls of three or more segments and explicit-template calls at any depth (with
  cast exclusion), canonically precise; Rust gained scoped, turbofish and `Self::` calls with a real
  canonical tier and a file-module guard; C# gained the `?.` family; TypeScript, JavaScript and Java
  gained qualified `new`; Objective-C reached field parity. Canonical multi-match now feeds the
  ambiguity accounting rather than being silently resolved, in every language.
- **Go qualified calls are honestly rejected and fenced** rather than half-resolved.
- **Metal Shading Language (`.metal`) is indexed**, parsed with the C++ grammar and C++ tags rather
  than a separate grammar. *(Measured on 45 real shaders, 864 KB, before adopting: ERROR-node byte
  rate 0.811% under the C++ grammar vs 12.3% under the C grammar — 15× worse; real C++ in the same
  repository: 0.000%. All 249 distinct entry points in that corpus are captured: 663 definitions,
  6,283 call references.)* `.metal` maps to the C++ language rather than a language of its own,
  because MSL and its C++/Objective-C++ host share one call namespace through dual-compile headers —
  which is the entire point of indexing shaders. *Known residual, documented rather than hidden:* an
  anonymous `enum : uint { … }` recovers as a named enum, minting 18 junk `t="type"` symbols named
  `uint` across those 45 files, 0.04% of that repository's 47,074-symbol index.
- **Module-level settings constants are first-class ranked `var` symbols in TypeScript, JavaScript,
  Rust, Ruby, Java, C#, C and C++** (the r3 head-to-head's q10 loss — a settings/feature-flag table
  in those languages previously contributed zero rankable symbols, so `--for` structurally could not
  surface it). Scoped to settings-shaped constants, not every literal: module/file/namespace-level
  capture only, gated on SCREAMING_SNAKE names for the convention-based grammars (Rust `const`/
  `static` items are constants by construction and are taken as-is). Python (case-blind module
  assignments, vendored upstream) and Go (CamelCase consts) were already captured and are unchanged
  — the r3 audit's "not extracted at all" reading is corrected in that report's addendum. Gate:
  `test/constcheck.sh`, written red-first against the pre-fix binary (18 red assertions at
  b6068c3).
- The current set: C++, C, Objective-C/Objective-C++, Metal, Python, TypeScript, JavaScript, Java,
  Ruby, Bash, Go, Rust, Swift, C#, plus JSON configuration keys.

### Added — output shaping, honesty and paging

- **`counts_floor="1"`** on `--callers` / `--callees` / `--uses` / `--impact` / `--edit-check` and
  further surfaces. Every such count is a **floor, never a total**: the call graph is extracted from
  source text by name, so dynamic dispatch, callbacks and function pointers, macro-generated call
  sites, and declarations that parse without a call expression contribute no edge. **Read a 0 as
  "none found", never as "none exists".** Each verb's legend also states its counting *unit* — those
  five count distinct (caller, callee) pairs, while `--uses` counts call sites.
- **Generated documents rank last in `--recall` by default.** A document that declares itself
  generated in its first lines, or is both ≥5× the median document's size and mostly fenced quoted
  output, is demoted — a capture that quotes every term otherwise wins every query on lexical match
  alone. It is never dropped: it still wins when nothing else matches, says why on its own line, and
  the header tallies how many were demoted.
- **One paging vocabulary across the verbs that page** — `--limit=N` and `--offset=M`, with the verbs
  that cannot page refusing rather than silently ignoring them.
- **`--token-budget=N` has two documented personalities.** On the default map, `--query` and
  `--recall` it is a CI **gate**: exit 3 if the emitted document's estimated tokens exceed N, with
  nothing of the artifact reaching stdout — only a record naming what was withheld against the budget.
  On `--for`, `--pack-task` and `--from-trace` it **shapes** instead, overriding that lens's own
  default payload budget, always exit 0. The estimate is calibrated against a public tokenizer,
  never exact.
- **`--max-tokens=N` shapes the map to fit** a deliberately conservative byte ceiling and discloses
  both the asked-for N and the honoured byte figure. Because the ceiling and the gate are measured in
  different units, the same N on both flags is not a tautology — and the shaped map says
  `over_ceiling=1` rather than overshooting in silence when even one symbol exceeds the floor.
- **`--order=stable | important-first | important-last`** is the canonical emit-order flag. `stable`
  gives path/ID order for provider KV-cache hits across re-runs; `important-last` puts the
  highest-ranked content at the end for recency-biased readers. Large default maps auto-flip to
  `important-last` past roughly half of a nominal 32K window unless the mode is given explicitly.
- **`--format=columnar` / `--format=candidates` / `--json`** alternate dialects, with an unknown value
  refusing and naming the legal set.
- **Did-you-mean on every selector**, computed as a real edit distance: a `name("X")` literal or a
  `--callers=SYM` that matches no indexed symbol **refuses** with a suggestion. A typo is not a
  `count=0`; a query whose names all resolve but that selects nothing still reports `count="0"`,
  because that is a measurement.
- **`--version` / `-v`** prints the version plus compiler id/version and build type. The version
  string has exactly one source of truth (the CMake project version), and drift between the printed
  and the declared version is gated.
- **`changed="N"` in the `--map-diff` header** — the teleport-seed file count, so a caller can tell a
  real diff run from a clean-tree or no-git degrade without shelling out to git a second time. Reads
  `0` on a clean tree, and is omitted on every other verb so it costs nothing.
- **`est_tokens="N"` on shaped `--for` output** so the delivered bundle's fit is checkable.

### Added — architecture, quality and structure

- **`--metrics`, `--deps`, `--hotspots`, `--clones`, `--cochange`, `--lint`, `--lint-rules=DIR`,
  `--communities`, `--community=ID`, `--zoom`, `--seams`, `--owners`, `--dead-code`, `--report`,
  `--mermaid`, `--tree`, `--html[=FILE]`** — complexity × churn hotspots, duplicate bodies, hidden
  co-change coupling, AST lint with user-supplied rules, call-graph modules and their nested zoom,
  untested cross-module seams, ownership and bus-factor risk, and a self-contained force-directed
  HTML call graph with no CDN.
- **`--color-by=MODE`** sets the initial node-colour lens of the `--html` page — `lang`
  (default), `community` (Louvain module), `cx` (cyclomatic, fixed thresholds), `churn`
  (per-file git commits, 18-month window), or `tested`. The page embeds all five lenses
  and keeps a live selector; when no git history exists the churn legend says so instead
  of painting zeros.
- **`--arch=RULES`** with a committed baseline gates layering violations in CI.
- **Multi-root workspaces**: `ripwire dir1 dir2 [dir3 …]` merges 2..16 checkouts into one labeled
  graph. Cross-root edges are created **only on explicit evidence** — a path-resolved include or
  import, or an FFI binding — so same-name symbols in unrelated repositories stay unlinked. Root order
  on the command line is irrelevant. The single-root verbs (`--quality-delta`, `--test-gate`, the
  eval family, `--arch` baselines, `--pr-context`) stay single-root; run them per root.
- **`--export=cc.json:FILE`** and **`--index-out`** write the index out for reuse; **`--scip=FILE`**
  overlays a precise SCIP index where one exists, and a missing file degrades honestly rather than
  failing.
- **`--batch=FILE`** answers several lookups in one round trip.
- **`--note-add="SYM_or_path: text"`** commits a gotcha to `.ripwire_notes`, auto-surfaced whenever
  `--for` or `--expand` later emits that symbol; `--notes` lists them.
- **`--doctor`** diagnoses a stale binary, a stale cache, or a missing tool.

### Added — MCP server and agent wiring

- **`ripwire wrap <agent>`** prints the recipe to wire the tool into a coding agent as an MCP server.
- **30 MCP verbs**: 15 read verbs, 12 flagship-reflex verbs, and 3 edit verbs. Each is a thin front
  door onto the same computation *and the same renderer* as its CLI sibling — one output shape, two
  surfaces. `find_referencing_symbols` is kept and documented relative to `impact` and `uses` (1-hop
  calls only; `impact` is the full transitive radius, `uses` also catches read/write/import sites).
- **`--scan-skill=FILE` / `--scan-skills=DIR`** scan agent skill files for prompt-injection,
  exfiltration and path-traversal shapes before you install them.

### Added — evaluation instruments

- **A held-out retrieval eval** (`bench/recalleval/`) with a published labeling protocol: every gold
  label was authored by *reading the source*, never by transcribing the ranker's own output, so the
  eval is allowed to say the current ranker is wrong. `--eval`, `--eval-retrieval`, `--eval-stray`
  and `--eval-skills` run the instruments from the binary.
- **A differential argv harness** that replays a large fixed set of command lines against two binaries
  and requires every diff to be provably intended.
- **A Linux hardware-counter backend for the self-profiler** (`-DRIPWIRE_PROFILE=ON` builds only),
  behind the same one-surface contract as the existing Apple Silicon kperf/kpep backend: one
  `perf_event_open` group per thread, **pinned** so the kernel never multiplexes it — a reported delta
  is a raw truth or the column is absent, never a silent scale — read whole in one syscall, and
  `exclude_kernel` so the stock `perf_event_paranoid=2` admits it without root. Where the kernel
  exposes no PMU at all it arms software counters rather than going dark — see the vPMU-less entry
  below — and degrades silently to plain timing only when the kernel offers nothing whatsoever.
  `test/pmccheck.sh` asserts whichever arm (active/inactive) the
  machine can express; see `bench/PROFILE.md` for the availability and validation story.
- See `docs/EVALS.md` for what each instrument measures and every published number's provenance.

### Changed

- **BREAKING (build): the default build is architecture-neutral.** It previously hardcoded
  `-O2 -mcpu=apple-m1 -ffast-math -fno-finite-math-only` unconditionally, which was a hard
  configure/compile failure on any non-Apple-Silicon target — Linux x86-64 and aarch64, Intel macOS,
  any cross build — because clang rejects `-mcpu=apple-m1` as an unknown target CPU. `-mcpu=apple-m1`
  is now applied only when configuring on Apple Silicon; elsewhere the default is plain
  `-O2 -ffast-math -fno-finite-math-only`. `RIPWIRE_NATIVE=ON` (`-march=native`, a dev-machine opt-in)
  is unchanged, as is the PageRank no-reassociation contract and the sanitizer target.
- **x86 SIMD kernels, output-identical.** The `dynamic_map` per-node rank scan and `FixedStr`'s
  `operator==` now compile to SSE on x86_64, alongside the NEON kernels that already existed on
  aarch64 — same count-of-true-lanes contract, no node-layout, width or API change, and a portable
  scalar path everywhere else. `test/dynmapsimdcheck.sh` proves SIMD-vs-scalar parity under the full
  sanitizer set and **fails a scalar-only build on a SIMD architecture**, so the gate cannot pass by
  measuring nothing.
- **x86 radix byte-histogram kernels, output-identical.** The radix sort's contiguous-key histogram
  fast paths (uint32/uint64/float, `src/infra/radixSort.inl`) now compile to SSE2 on x86_64 — the
  same one-wide-load-then-byte-spill shape as the NEON kernels that already existed on aarch64, with
  the IEEE sortable-word flip done in SIMD for float. Same histograms bin-for-bin, scalar path
  everywhere else (including big-endian NEON). *Measured (min-of-15 ns/key, x86_64 via Rosetta 2 on
  an M-series host — a translation proxy, not real x86 silicon — `-O2 -DNDEBUG`, 4K/64K/1M random
  keys):* float 1.44–1.52× over scalar; uint32/uint64 within ±10% (a wash — kept for backend
  uniformity, at no measured cost). An AVX2 variant (32-byte load, same spill) measured *slower*
  than SSE2 under the same proxy (0.86–0.94×) and was not shipped; re-evaluate on real x86 hardware
  before adding it. `test/radixsimdcheck.sh` proves SIMD-vs-scalar parity against an
  independently-formulated histogram oracle under the full sanitizer set, **fails a scalar-only
  build on a SIMD architecture**, and on Apple Silicon runs a second cross-compiled pass under
  Rosetta so the SSE2 kernels are gated on the machines this repo is developed on.
- **sparseCsr math kernels join the x86 port.** The CSR `blockReduceDot` / `scaleVec` / `spmvRow`
  float kernels — NEON-only until now, silently falling back to scalar on x86_64 — compile to SSE2
  (mul+add: SSE2 has no FMA, so x86 rounding differs from arm64 while each platform stays
  bit-stable run-to-run, which is what the determinism contract requires). `test/dynmapsimdcheck.sh`
  grew a third parity arm — an exact-integer regime whose sums are exact in every association
  order, so lane and tail bugs surface as bit-exact mismatches with no tolerance band to hide
  behind, plus a tolerance-band random regime and a known-eigenpair check — and its non-vacuity
  banner now covers these kernels, so a scalar-only x86 build fails instead of passing vacuously.
  Found by sweeping `__ARM_NEON` sites rather than porting from the feature list; the radix-sort
  byte-histogram fast paths are the one remaining NEON-only site (identical behavior either way —
  a perf follow-up, bench-gated).
- **BREAKING (output): canonical symbol IDs corrected.** A parse-recovery artifact published a
  function's *return type* as its class scope. *(Measured on one repository: 80 wrong canonical IDs in
  ordinary C++ corrected, plus 5 newly-correct IDs where the real enclosing namespace took over.)*
  Anything scripted against the old IDs will see different values. Valid C++ never triggered the
  guard, so clean parses are unaffected.
- **BREAKING (caches): parser-version bumps invalidate warm caches.** Several extraction changes moved
  the parser version, so an upgrade costs one cold re-parse. The on-disk record *shape* did not
  change, so the cache format version did not move.
- **Graph shape: C-family `#import` now produces an include edge** — the edge that links a shader to
  its headers. `#pragma`, `#error` and `#warning`, which share the same parse node type, are excluded.
  `#include` and `#import` share one path extractor so they cannot drift apart, and a trailing comment
  on the directive line no longer leaks into the resolved path.
- **`--test-gate` obligations are computed per changed *symbol*, not per changed file.** A change that
  owns one symbol inside a 3,000-line file is no longer charged that whole file's test obligations.
- **Ranking: fixture and generated-content paths are de-prioritized.** A measured change, published
  with its held-out numbers in `docs/EVALS.md`, not a hand-tuned weight.
- **`--map-diff` documentation corrected.** The help text and README claimed it filtered to symbols
  changed against git HEAD. It never did: it emits the **full map, re-ranked with a PageRank teleport
  toward git-changed files**, so every file can still appear and a clean tree is byte-identical to the
  default map. `--pr-context` is the actually-filtered only-changed-files report. *(No code changed;
  expectations do.)*
- **`--detail=N` is now accepted with `--flags`, `--stray-content` and `--whereis`**, where it lifts
  the display cap — the same meaning it has on `--for`. It was previously rejected by the
  companion-flag guard.
- **`--query=TERMS` is relabelled "raw BM25 ranking (debug); use `--for`"** — fully functional, no
  longer presented as the primary retrieval entry point.
- **`--order` supersedes `--stable`, `--most-important-last` and `--no-auto-order`**, which remain
  fully functional as hidden aliases and print a one-line stderr deprecation the first time they are
  used. `--no-stable` is unrelated and untouched.
- **`--pack-top-n` and `--pack-budget-bytes`** behave unchanged but now print a stderr line naming
  `--pack-task` and `--detail` as the superseding one-call flags.
- **`--anchor` and `--cochange-boost` are negative-result experiments** — their own records show no
  confirmed recall lift. Both are dropped from `--help` and refuse with an "experimental" message
  unless `RIPWIRE_DEV=1` is set, keeping them reachable for evaluation work without advertising them
  as supported surface.
- **MCP tool count grew to 30**; the `flags` verb gained an optional `symbol` argument for the flip
  view, deliberately an argument on the existing verb rather than a new verb.
- **`install.sh` no longer hardcodes a Homebrew prefix**, which was wrong on Intel macOS and on any
  machine without Homebrew. It detects `brew --prefix` when brew is on `PATH`, honours an explicit
  install-prefix override, and otherwise falls back to `~/.local`. *(Existing installs may land in a
  different prefix than before.)*
- **Corrected performance claims.** A frequently-quoted "75× warm re-runs" was the incremental cache's
  *parse-phase* figure quoted without that qualifier; end-to-end warm command latency measures
  **8.2×** *(large private C++ corpus, 2,340 files; historical private corpus, not publicly
  reproducible; measured 2026-07-22)*. An unlabelled "`--edit-check` ~26 ms" was corpus-specific; the
  labelled figures are **43 ms at 592 files** and **114 ms at 2,340 files**.

### Fixed

- **The self-profiler's Linux counter backend no longer goes dark on vPMU-less machines** — which is
  most cloud VMs and CI boxes (`src/infra/profilePmc.h`; visible only under `-DRIPWIRE_PROFILE=ON`).
  Two defects, found and fixed live on an x86 Xeon VM whose kernel refuses every hardware event with
  `ENOENT`: (1) the documented per-event graceful skip did not apply to the group *leader* — if the
  first event (`cycles`) failed to open, the whole backend went inactive even when later events would
  have opened; leadership now falls to the first event that actually opens. (2) The event table was
  hardware-only, so a PMU-less kernel had nothing to offer; two `PERF_TYPE_SOFTWARE` rows —
  `task-clock` (on-CPU ns) and `page-faults` — now trail the table. They cost no hardware counter
  slot on bare metal and keep per-scope counter columns alive on VMs, under their own names, never as
  a stand-in for hardware counts. The over-budget shrink loop also now drops the last *PMU-consuming*
  event rather than blindly the last row (dropping a software event can never make a pinned group
  fit). Gate: `test/pmccheck.sh`'s inactive arm now additionally proves the kernel offered no counter
  at all — the arm that used to pass vacuously on VMs fails on the old code and exercises the live
  path on the new. *(Measured on the 2-vCPU VM: single-thread scopes' `task-clock` agrees with the
  independent wall column to 0.05–1.6%, and the parse pool's wall-vs-task-clock gap put a number on
  CPU oversubscription — ~36% of the parse phase's wall time was spent off-CPU.)*
- **Rust whole-impl span** — an `impl` block's span covered the whole block, minting phantom clone
  reports.
- **Merge-aware churn.** The churn walks now follow merges, so a history landed through merge commits
  is no longer under-counted.
- **False zeros closed across the count surfaces**: a count that cannot be a total is labelled a
  floor, and a count whose unit differs from its neighbours says so, on every verb that emits one.
- **Host attribution is innermost-wins.** Plain span intersection could credit a 40-line function
  above a 3-line one as the host of the same `#if` region (tree-sitter definition extents over-reach
  in preprocessor-heavy Objective-C++). Hosts are now the definitions wholly inside the region plus
  the *innermost* definition containing its opening line — the same rule `--grep`'s `in=` uses, so a
  flip host and a grep hit can never disagree.
- **Gate shadowing.** A file that declares its own constant of the same name shadows the gate's, as
  normal C++ scoping requires. Without this, short house-style names cross-wired: *measured on one
  repository, a weapons header's `constexpr float kSpeed` / `constexpr int kTurns` contributed six
  phantom branch sites and four phantom hosts to an unrelated gate.* The value lane now also runs on
  C-family source only — an extension denylist had previously let a committed HTML report that merely
  quoted a gate name through.
- **`--flags` no longer reports gates from nested worktrees or build output as the repository's own.**
  The second directory walk that `--flags` needs (CMake files are never ingested) disagreed with the
  crawl about what counts as source. *(Measured: a stale worktree copy inverted a real option's
  reported default.)*
- **Ingest robustness.** Large or degenerately-nested JSON is skipped with a stderr note: the JSON
  lane indexes configuration keys, and a big or `[[[[…`-nested file is data or a test corpus — the
  former explodes the symbol table, the latter drives tree-sitter's error recovery superlinear
  (43 s measured on a 100 KB torture file). Both were found live by benchmarking against real
  upstream repositories.
- **CRLF-encoded files** are handled identically to LF in the flag value lane.
- **Reproducible dependency pinning.** All 15 fetched grammar, tree-sitter and test-framework
  dependencies previously pinned mutable tags, which can be force-moved server-side. Every one is now
  pinned to the commit SHA that tag resolved to, with the human-legible tag kept as a trailing comment.

### Security

- **Credential redaction is on by default** — credential-shaped literals are removed from emitted
  bodies and signatures unless you opt out with **`--no-redact`**. There is no opt-IN spelling,
  because the behaviour is not opt-in. The redaction fixtures that necessarily carry synthetic
  credentials are enumerated in `test/README.md` and enforced by a gate.

### Known limits

These are stated, not hidden, and each is measurable from the output itself:

- **Call edges are heuristic and name-based.** Dynamic dispatch, callbacks, and macro-generated call
  sites produce no edge. A high-ranking symbol with no call edges may be a dispatch hub, not a leaf.
- **`amb="K"`** on a symbol means K of its calls hit a name with multiple definitions and the resolver
  guessed. The header's `ambiguous=N` is the call-graph completeness gauge — read the source when
  which-target matters.
- **Token estimates are calibrated, never exact.** The `--pr-context` estimate in particular is known
  to under-charge relative to a real tokenizer; treat it as a lower bound.
- **Binary-doc extraction (`markitdown` bridge) is uncached and re-runs every ingest.** The doc
  post-pass is deliberately outside the parse cache, so on a machine with `markitdown` installed a
  corpus containing PDF/PPTX/DOCX/XLSX pays the full subprocess extraction on *warm* runs too —
  measured at ~97% of a warm run's wall (2.05 s of 2.11 s) on a 2-vCPU VM against this repository's
  own showcase PDF+PPTX, found by the self-profiler's wall-vs-task-clock gap (child-process CPU is
  invisible to per-thread counters). The extraction is a pure function of the file bytes, so it is a
  clean cache candidate; until then, the cost scales with the corpus's binary docs, not its code.
- **`--for`'s `--token-budget` shaping is not strictly binding at very small budgets** — the header
  floor (envelope, legend, verbatim task echo) is bytes no trim can shrink, and the lens labels the
  result `over_ceiling` rather than claiming a trim it did not perform.
- **Release automation has never been executed end-to-end.** The tag-triggered build-and-attach
  workflow and the release-binary installer are untested until the first real tag push.
- **The x86 64-bit-key rank kernels need SSE4.2.** `_mm_cmpgt_epi64` is not in the SSE2 baseline, so on
  a stock `-march=x86-64` build the `int64`/`uint64` specializations — including the production
  `dynamic_map<std::uint64_t, …>` instantiation — fall back to the scalar template. Build with
  `-march=x86-64-v2` or `RIPWIRE_NATIVE=ON` to light them up. Correctness is identical either way; only
  the scan width changes.
- **The Linux counter backend's *active* path has not been run against real PMU hardware.** It is
  validated for correctness, degrade behavior and the sanitizer set under x86-64 emulation and on
  PMU-less VMs, where `perf_event_open` fails and the backend goes inactive as designed — which
  exercises the inactive arm only. The live counting path awaits a bare-metal box; `bench/PROFILE.md`
  carries the probe that tells you whether a candidate machine qualifies.
