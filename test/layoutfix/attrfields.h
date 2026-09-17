#pragma once

// attrfields.h — layout fixture: a field whose declaration carries a `(` that is NOT a parameter list —
// `alignas(N)`, `__attribute__((...))`, `decltype(...)` or a `std::function<...>`'s template-nested paren.
// Never compiled; ripwire indexes it as C++ and test/layoutcheck.sh asserts the computed table.
//
// parameterListParen (src/layout.h) used to take the FIRST `(` in the statement as a member-function's
// parameter list, whichever `(` that was. All four shapes below put an unrelated `(` before the real
// field, so the field was read as a member function and dropped — while the struct still reported
// modeled="1" with a size short by exactly that field's bytes. Each must now come back REFUSED
// (modeled="0", a named caveat, the field still counted) rather than silently missing.

struct AlignasFieldCase
{
    int          n;
    alignas( 8 ) int x;
    char         c;
};

struct AttributeFieldCase
{
    int n;
    int x __attribute__( ( aligned( 8 ) ) );
    char c;
};

// A3 (found-items 2026-09-17): the SAME postfix `__attribute__((...))` shape, but one that changes no byte
// of the layout (a hint attribute, not aligned/packed). This must come back fully MODELLED — peeling the
// attribute must not make every attribute-decorated field look unmodelable.
struct AttributeHarmlessFieldCase
{
    int n;
    int x __attribute__( ( deprecated ) );
    char c;
};

// A3 (review round, found-items 2026-09-17): the GNU reserved-namespace double-underscore spelling
// (`__aligned__` / `__packed__` — what system headers reach for so the keyword cannot collide with a
// macro of the same bare name) is the SAME attribute as the bare form and must degrade identically:
// `containsWord`'s word-boundary rule treats `_` as an identifier byte, so it does NOT match `aligned`
// inside `__aligned__` at all — the field used to come back modeled="1" with a confidently wrong sz/al/off.
struct AttributeGnuAlignedFieldCase
{
    int n;
    int x __attribute__( ( __aligned__( 8 ) ) );
    char c;
};

struct AttributeGnuPackedFieldCase
{
    int n;
    int x __attribute__( ( __packed__ ) );
    char c;
};

// the other half: a GNU double-underscore attribute that is layout-NEUTRAL must stay fully modelled —
// normalising `__unused__` to `unused` must not make it newly match `aligned`/`packed` by accident.
struct AttributeGnuHarmlessFieldCase
{
    int n;
    int x __attribute__( ( __unused__ ) );
    char c;
};

// A3 (review round): the C++11 standard attribute syntax, GNU's own namespace on it. Never given its own
// peel (peelAttributeGroups only recognises the postfix `__attribute__((...))` spelling) — pinned here so
// a later change to `[[...]]` handling cannot silently start modelling these as natural. Both refuse today
// as a side effect of how the surrounding text fails to parse as a plain field (postfix: swept up as an
// unevaluable array extent; prefix: pollutes the type spec) — never modeled="1" with a wrong sz/al/off.
struct AttributeStdAlignedFieldCase
{
    int n;
    int x [[gnu::aligned(8)]];
    char c;
};

struct AttributeStdPackedFieldCase
{
    int n;
    int x [[gnu::packed]];
    char c;
};

struct DecltypeFieldCase
{
    int            n;
    decltype( 1 ) x;
};

#include <functional>
struct StdFunctionFieldCase
{
    int                       n;
    std::function<void(int)> cb;
};

// CodeRabbit on #281: a string ARGUMENT inside a layout-neutral attribute is inert text. Its `)` used to unbalance the
// group match (the field was refused as unparsed-member) and its "packed" used to read as the packed keyword (refused
// as unknown-type). Both are a deprecated hint and must stay fully modelled, exactly like AttributeHarmlessFieldCase.
struct AttributeStringParenCase
{
    int n;
    int x __attribute__( ( deprecated( ")" ) ) );
    char c;
};

struct AttributeStringKeywordCase
{
    int n;
    int x __attribute__( ( deprecated( "packed" ) ) );
    char c;
};
