#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_importcap.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_importcap.h — the C++ half of the shared import-capture vocabulary (issue #358).
//
// THE SHAPE OF THE ROUND. What every per-language import extractor did was the same three steps: find the
// directive's node, pick the one child that carries the written specifier, normalise that child's text.
// Step one is now the tags query's job — `@import.path` in queries/<lang>/tags.scm names the specifier
// node, one capture name for every language, and an UNANCHORED pattern so a directive nested in a guard
// is found without the C++ walk descending to meet it. Steps two and three are what is left here, and
// they are ONE function per DepDialect instead of one per language: the dialect is the unit at which
// "what does a written specifier mean" actually varies (a C-family `<x.h>` carries a quote-vs-angle bit,
// a TS `'./x'` carries quote delimiters, a Ruby `require_relative` carries a file-relative rule), and
// dependencyDialect already groups languages by exactly that. Dependency RESOLUTION stays in
// src/resolve.h and is untouched by this round.
//
// WHAT IS STILL IN C++, AND WHY IT CANNOT LEAVE. Tags-pass predicates never run here (stated in
// queries/python/tags.scm, pinned by test/matchgrammarcheck.sh, and the reason `using namespace ns;` is
// gated in ingest.cpp rather than excluded by a query). So every gate that needs to READ TEXT stays in
// C++: which preprocessor directive a captured `preproc_call` argument belongs to, whether a callee is
// the bare name `require`, whether an argument is a single string literal. Those are normaliser arms, not
// extractors — one per dialect, not one per language.
//
// THE VOCABULARY IS A FAMILY, AND ONLY ITS FIRST MEMBER IS SPENT. `@import.path` is the only capture name
// in use, because C-family imports have no other part: `#include` names a path and nothing else — no
// alias to record, no list of imported names. The other two names the issue sketches are reserved BY NAME
// so the next language lands on them rather than inventing a spelling: `@import.alias` is the local name an
// import renames a target to (`import a.b as c`, `use Foo\Bar as Baz`, `using X = Foo.Bar`), and
// `@import.names` is a group of targets ONE directive names (`use Foo\{A, B}`, `alias MyApp.{Bar, Baz}`),
// which is why both of those are emitted by the C++ side today through a per-directive helper rather than
// by one capture — a capture names one node, and a group is many. No enum value reserves them: an unused
// arm that no query can reach is a lie about what the vocabulary supports.
//
// ORDERING. ts_query_cursor_next_match yields matches by the match's start byte, so a capture arrives in
// SOURCE order and the emitted Includes do too — the same order captureIncludes' walk produced, because
// emitCapturedImport runs straight from the capture dispatch with nothing staging it in between. The
// import-role use-site refs move into the tags pass's own window, where orderReferences re-sorts them by
// (startByte, name, role, isInherit) — a total key, so the move cannot reorder a published row.
//
// WHAT THE WALK STILL OWNS, AND DOES NOT TRAVEL WITH THE MOVE. Three things captureIncludes computed from
// its own frame are re-derived here rather than dropped: the import-container nesting bound
// (importContainerDepth + the same DISCLOSE, below), the lazy bit a TS/JS require needs from `insideFn`,
// and Ruby's innermost-open index for the constant-receiver dedupe. The first is recovered now because it
// is one parent hop per import; the other two are why a language still on the walk cannot move until the
// emission can re-derive them from ancestry too — the tags pass never sees a walk frame.

#include "depdialect.h"   // DepDialect + dependencyDialect — the unit one normaliser is written per

namespace rw
{

namespace
{

// The import-container DEPTH a captured directive sits at, counted as the number of ALLOWLISTED
// containers on the path from the file root down to it — the same quantity captureIncludes' walk carried
// in its frame, recovered here from the captured node's ancestry because the walk no longer runs for this
// language. Counting the same predicate the walk's entry test used (isImportContainer) is what makes the
// two agree: an include under one `#if` measures 1, and under 600 measures 600.
//
// STOPS AT THE BOUND rather than climbing to the root: past kMaxImportContainerDepth the answer cannot
// change, and a hostile generated file must not be able to turn per-import capture into an unbounded
// parent walk. An include at file scope costs one parent hop, which is the overwhelmingly common case.
std::uint16_t importContainerDepth( TSNode directive, Lang lang ) noexcept
{
    std::uint16_t depth = 0;
    for( TSNode p = ts_node_parent( directive ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        if( isImportContainer( lang, ts_node_type( p ) ) && ++depth >= kMaxImportContainerDepth )
        {
            break;
        }
    }
    return depth;
}

// One captured `@import.path`, normalised. `text` empty is the "not an import after all" signal and the
// caller emits nothing: that is how a dropped directive reads (a floor), which is the honest direction
// for this graph — a wrong edge is worse than a missing one.
struct ImportSpec
{
    std::string text;
    bool        isAngle = false;   // CFamily: <x.h> is external (unresolvable without a build system), "x.h" is not
};

// ── DepDialect::CFamily ───────────────────────────────────────────────────────────────────────────────
// `<dir/x.h>` / `"dir/x.h"` → `dir/x.h`, with the quote-vs-angle bit read from the delimiter BEFORE it
// is stripped. A spelling with no recognised opening delimiter — a macro include, `#include HEADER` —
// comes back verbatim in quote-form, which is pre-existing behaviour preserved byte-for-byte.
//
// THE ONE GATE, and it is a gate on TEXT because a predicate cannot run. Under the C and C++ grammars
// `#import` has no rule of its own, so it parses as a generic preproc_call whose `directive:` field holds
// the spelling — and so do `#pragma once`, `#error "…"`, `#warning`, and every unknown directive, all of
// which the query above captures and NONE of which is a physical dependency. Under the ObjC grammar
// `#import` IS a preproc_include and needs no gate, which is why this branch tests the node kind rather
// than the text alone. Every non-`#import` spelling is dropped: a floor, never a fabricated edge.
ImportSpec normaliseCFamilyImport( TSNode directive, std::string_view raw, std::string_view src )
{
    ImportSpec out;
    if( kindIs( ts_node_type( directive ), "preproc_call" )
        && nodeFieldText( directive, NodeField::Directive, src ) != "#import" )
    {
        return out;
    }
    out.text = includePathOf( raw, out.isAngle );
    return out;
}

// ── the dispatch: ONE normaliser per DepDialect ──────────────────────────────────────────────────────
// CFamily is the only dialect that has moved over so far; every other arm returns an empty ImportSpec,
// which is what makes the capture INERT rather than wrong on a language whose tags.scm has not adopted
// `@import.path` yet. Each `case` is deleted as its language moves, and the compiler then names every
// other dialect still to do — the same "one language at a time" landing the issue asks for.
ImportSpec normaliseImportSpecifier( DepDialect dialect, TSNode directive, std::string_view raw, std::string_view src )
{
    switch( dialect )
    {
        case DepDialect::CFamily: return normaliseCFamilyImport( directive, raw, src );
        default:                  return {};   // no language but C-family captures @import.path yet
    }
}

// One captured `@import.path` → the Include record plus its ABS-3 import-role use-site ref, which is
// exactly the pair captureIncludes' `emitDirective` lambda minted for a C-family directive.
//
// IT TAKES THE CAPTURED NODE, not a (node, text) pair, because the whole shape of this file is "one node
// in, everything else derived here": the specifier's text is its own source span, and the DIRECTIVE it
// belongs to is its parent — the `#include` / `#import` statement itself. Handing the caller a `directive`
// and a `raw` string instead would push that rule out to every call site and make this function correct
// only while its callers obey an unwritten contract.
//
// The directive is also the node both records are SITED at, so an include nested inside an `#if` reports
// its own line and byte, not the guard's (captureIncludes' own rule, kept because resolve.h's Ruby
// containment reads the byte and --deps reports the line). The use-site ref's name is the importable final
// segment — `dir/x.h` → `x`, `<vector>` → `vector` — and a target with no identifier head (a relative
// `../x`) names nothing and emits no ref, since there is nothing for the resolver to key on.
//
// THE NESTING BOUND IS KEPT, deliberately. A flat tags query has no depth limit of its own, so nothing
// about THIS path forces it — but the contract the walk carried is a real one: past
// kMaxImportContainerDepth a file's deeper imports are NOT captured, the file still indexes, and the fact
// is announced (test/preproccondcheck.sh's 600-deep arm pins all three). Dropping the bound here would
// silently CAPTURE those imports instead, which is a behaviour change on a hostile-input case and would
// leave that arm asserting a disclosure this path no longer owes. So the bound is re-derived from ancestry
// (importContainerDepth above) and the same DISCLOSE fires — one behaviour, measured on the node rather
// than on a walk frame, with the announcement unchanged.
//
// SEVEN PARAMETERS, and that is the house shape rather than an accident. --quality-delta's `params` check
// bars 5, and this is over it; the siblings it sits between take 5 (captureBases, captureFields,
// capturePythonImportBinds) and 9 (captureIncludes — the very function this round moved C-family OUT of),
// with the two per-file drivers at 10. Four of the seven are the sink set (includes, refs, shortfall) plus
// the file id every capture records carry. Collapsing them into a context struct would take this one call
// under the bar while leaving every sibling over it, i.e. a local abstraction that makes the family harder
// to read, not easier. The count is the convention; the bar is generic.
void emitCapturedImport( TSNode pathNode, std::uint32_t fileId, Lang lang, std::string_view src,
                         std::vector<Include>& includes, std::vector<RawRef>& refs, ExtractShortfall& shortfall )
{
    const TSNode directive = ts_node_parent( pathNode );
    if( importContainerDepth( directive, lang ) >= kMaxImportContainerDepth )
    {
        DISCLOSE( shortfall, ExtractShortfall::DisclosureWhy::ImportNestingTooDeep,
                  "ingest: import-container nesting past the depth bound — deeper imports not captured" );
        return;   // the same degrade the walk performed: not captured, file still indexed
    }
    const ImportSpec spec = normaliseImportSpecifier( dependencyDialect( lang ), directive, nodeTextOf( pathNode, src ), src );
    if( spec.text.empty() )
    {
        return;
    }
    if( std::string name = importName( spec.text ); !name.empty() )
    {
        RawRef r;
        r.fileId    = fileId;
        r.startByte = ts_node_start_byte( directive );   // the DIRECTIVE, never its enclosing #if
        r.line      = ts_node_start_point( directive ).row + 1;
        r.role      = RefRole::Import;
        r.name      = std::move( name );
        refs.push_back( std::move( r ) );
    }
    includes.push_back( { fileId, spec.isAngle, false, false, ts_node_start_byte( directive ), false, spec.text } );
}

}   // namespace

}   // namespace rw