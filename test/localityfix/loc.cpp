// localityfix/loc.cpp — gate fixture for the S6-C locality tie-break (adversarial HIGH-1 regression).
//
// THE BUG (now fixed): the locality tie-break used to compare canonical ids `path::scope::name` by RAW BYTE
// prefix. Two UNRELATED classes whose names merely start with the same letter (`Xenon` caller vs class `Xtra`)
// then scored a longer shared byte-run — *inside* the scope segment — than the genuinely-correct class
// (`Bravo`). So `Bravo b; b.go();` inside `Xenon::call()` resolved CONFIDENTLY to `Xtra::go` (WRONG) and the
// header reported `ambiguous=0`. The legitimate `Bravo::go` edge the §2a ladder reached was silently dropped.
//
// THE FIX: `sharedLocality` compares on WHOLE `/`- and `::`-delimited SEGMENTS. A partial overlap inside a
// segment (`Xenon` vs `Xtra`) counts as ZERO locality. So both `Xtra` and `Bravo` share only the file PATH with
// the caller — they TIE — no candidate is strictly more local, and the call stays HONESTLY AMBIGUOUS (count=2,
// ambiguous=1) instead of a false-confident wrong pick. The receiver is an UNTYPED `auto` local: P2-D Rule 2
// narrows a typed local or PARAMETER to its type before the tie-break, so only an untyped receiver reaches it.
//
// Out-of-line method defs (the realistic C++ layout) give each `go` its enclosing scope, so the canonical ids
// `…::Xtra::go` / `…::Bravo::go` exist and the tie-break has scopes to (correctly NOT) discriminate on.

struct Xtra
{
    int go();
};

struct Bravo
{
    int go();
};

int Xtra::go()  { return 1; }
int Bravo::go() { return 2; }

Bravo* roster[ 2 ];

struct Xenon
{
    void call( int slot );
};

void Xenon::call( int slot )
{
    // b is an `auto` local with a subscript initializer → no var→type binding → Rule 2 cannot fire → this call
    // reaches the locality tie-break. (Until 2026-09-16 b was a `Bravo* b` PARAMETER; Rule 2 reads that now.)
    auto b = roster[ slot ];
    b->go();  // FIXED: stays AMBIGUOUS (Xtra/Bravo tie on path-only locality) — never a confident Xtra::go pick
}
