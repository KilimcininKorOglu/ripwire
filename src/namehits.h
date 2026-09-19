#pragma once
// namehits.h — LB3x (routing-loop round 2, PLAN_OUTPUT_ROUTING_LOOP_2026-09-12_REPORTS/12_round2_PREREG.md,
// Amendment 1 §R2, approved by rv-prereg2.md 2026-09-19): `--for`'s ranking-to-gold append.
//
// THE MECHANISM, stated so it can be re-derived (fixed a priori — mined from Graft, no tuned weights).
// For a file f, over its two fields — name (the basename stem's subtokens) and path (every path subtoken,
// directories and basename together) — score(f) = 3*BM25(name, query) + 2*BM25(path, query), k1=1.2, b=0.75,
// idf(t) = log(1 + (N-df+0.5)/(df+0.5)) (BM25+'s never-negative form), over EVERY indexed source file (N).
// Only files scoring > 0 are candidates, ranked (score desc, path asc) — a total order.
//
// THE ELEMENT. Up to kNameHitsMaxRows files this answer did NOT already name (by any p= row it emits), in
// their own element, the LAST child of the root: `<namehits n="K"><nh p="…"/>…</namehits>`. Never inside
// <tail> — <tail>'s shown=/total= count TRIMMED rows, a different population (files the ranked head already
// found but a byte budget cut). APPEND-ONLY: this NEVER re-ranks or reorders a row already in the answer —
// the RRF re-rank variant was simulated and rejected (it displaced gold on frozen q24; lb3_sim.py,
// $ORCH/reports/rv-prereg2.md §1b/§2). Honesty: n= is the TRUE count served (0..3), never padded — fewer
// than 3 qualifying files says so rather than filling with noise.
//
// SCOPE (disclosed, not yet closed): wired only into --for's DEFAULT regime (no explicit --token-budget).
// An explicit ceiling's byte ladder (climbCeilingLadderBy, W3FIX H2) does not yet price this element, so
// wiring it in there risks a document that claims est_tokens<=budget_tokens while shipping bytes the ladder
// never reserved for it — worse than omitting it. See docs/EVALS.md and the r2-LB3x report for the follow-up.
//
// PARITY. The tokenizer below is a byte-for-byte port of $ORCH/sim/lb3_sim.py's `toks()` — NOT lexindex.h's
// subtokens() (whose acronym-run rule is a different, more recent algorithm) — because the registered
// formula, and this header's parity gate (test/namehitscheck.sh, lb3sim mirror), is pinned to lb3_sim.py's
// simple one-boundary camel split. STOP mirrors lb3_sim.py's list verbatim, including corpus-shaped entries
// (cc/h/py strip source-file extensions out of path tokens; "rocksdb" was the pre-registration corpus's own
// name) — a disclosed, not a hidden, overfit; a future round may widen it with its own registered evidence.

#include "infra/Diagnostics.h"   // ASSUME/ENSURES — local invariants, never external input (that's VALIDATE)
#include "model.h"               // IngestResult, HashMap, NodeId

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kNameHitsMaxRows = 3;
inline constexpr double      kNameHitsK1      = 1.2;
inline constexpr double      kNameHitsB       = 0.75;

// $ORCH/sim/lb3_sim.py STOP, verbatim (see the file header above for why this is not subtokens()'s list).
inline constexpr std::array<std::string_view, 18> kNameHitsStop = {
    "cc", "h", "py", "how", "does", "reach", "where", "is", "implemented",
    "the", "a", "to", "in", "of", "and", "for", "when", "rocksdb"
};

// lb3_sim.py's toks(): re.sub(r'([a-z])([A-Z])', r'\1 \2', s).lower(), split on runs of non-[A-Za-z0-9],
// drop empty/stopword/all-digit tokens. ONE camel boundary (lower-then-upper) — deliberately NOT the
// ACRONYMWord rule subtokens() applies elsewhere, so this must stay its own tokenizer (see file header).
inline std::vector<std::string> nameHitsToks( std::string_view s )
{
    std::string camel;
    camel.reserve( s.size() + 8 );
    for( std::size_t i = 0; i < s.size(); ++i )
    {
        const unsigned char c = static_cast<unsigned char>( s[i] );
        camel.push_back( static_cast<char>( c ) );
        if( i + 1 < s.size() )
        {
            const unsigned char n = static_cast<unsigned char>( s[ i + 1 ] );
            if( c >= 'a' && c <= 'z' && n >= 'A' && n <= 'Z' )
            {
                camel.push_back( ' ' );
            }
        }
    }
    for( char& c : camel )
    {
        if( c >= 'A' && c <= 'Z' )
        {
            c = static_cast<char>( c - 'A' + 'a' );
        }
    }
    std::vector<std::string> out;
    std::string              cur;
    // one token's two independent membership questions, answered in place rather than through two more
    // one-purpose free functions — src/lintrules.h::isValidSeverity and src/tracein.h::detail::isDigits
    // already answer "is this whole span in a small closed set" and "is this whole span all-digit"
    // respectively, and a THIRD near-identical pair here is the clone quality-delta gates on, not a
    // different fact than either of them already states.
    const auto flush = [ & ]()
    {
        if( cur.empty() )
        {
            return;
        }
        bool allDigit = true;
        for( unsigned char c : cur )
        {
            if( c < '0' || c > '9' )
            {
                allDigit = false;
                break;
            }
        }
        bool stop = false;
        for( std::string_view s : kNameHitsStop )
        {
            if( s == cur )
            {
                stop = true;
                break;
            }
        }
        if( !allDigit && !stop )
        {
            out.push_back( cur );
        }
        cur.clear();
    };
    for( char c : camel )
    {
        if( ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' ) )
        {
            cur.push_back( c );
        }
        else
        {
            flush();
        }
    }
    flush();
    return out;
}

// the basename minus its LAST extension (lb3_sim.py's os.path.splitext(os.path.basename(f))[0])
inline std::string_view nameHitsStem( std::string_view path ) noexcept
{
    std::string_view base = path;
    if( const std::size_t slash = base.find_last_of( '/' ); slash != std::string_view::npos )
    {
        base = base.substr( slash + 1 );
    }
    if( const std::size_t dot = base.find_last_of( '.' ); dot != std::string_view::npos && dot > 0 )
    {
        return base.substr( 0, dot );
    }
    return base;
}

inline double nameHitsIdf( std::size_t N, std::uint32_t df ) noexcept
{
    return std::log( 1.0 + ( double( N ) - double( df ) + 0.5 ) / ( double( df ) + 0.5 ) );
}

struct NameHitsRanked
{
    std::uint32_t fileId = 0;
    double        score  = 0.0;
};

// EVERY indexed source file, ranked by 3*BM25(name-field) + 2*BM25(path-field) against `queryToks`
// (already-tokenized, dedup not required — the scorer only reads the unique membership below). Files
// scoring 0 (no field match at all) are excluded; the rest sort (score desc, path asc) — deterministic:
// integer-free but total, since floats never tie except on identical inputs, and the path tie-break makes
// the order total even then.
inline std::vector<NameHitsRanked> rankNameHits( const IngestResult& ing, const std::vector<std::string>& queryToks )
{
    std::vector<NameHitsRanked> out;
    const std::size_t           F = ing.files.size();
    if( F == 0 || queryToks.empty() )
    {
        return out;
    }
    // every kept token came out of nameHitsToks(), whose own contract is lowercase-ascii — a local
    // invariant this loop relies on for the qset membership test below (no case-folding at lookup time).
    // DASSERT (debug-only, no promise made to the optimizer): the check itself is real work — a scan of
    // every token — which ASSUME's "not evaluated in release" contract is not meant to carry.
    DASSERT( std::all_of( queryToks.begin(), queryToks.end(), []( const std::string& t )
        { return !t.empty() && std::all_of( t.begin(), t.end(), []( char c ) { return ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' ); } ); } ),
        "namehits: rankNameHits's query tokens must already be lowercase-ascii (nameHitsToks's own contract)" );

    HashMap<std::string, std::uint8_t> qset;
    for( const std::string& t : queryToks )
    {
        qset[ t ] = 1;
    }
    if( qset.empty() )
    {
        return out;
    }

    std::vector<std::vector<std::string>> nameToks( F ), pathToks( F );
    HashMap<std::string, std::uint32_t>   dfName, dfPath;
    double                                lenSumName = 0.0, lenSumPath = 0.0;
    HashMap<std::string, std::uint8_t>    seen;   // per-file scratch, cleared each iteration
    for( std::size_t f = 0; f < F; ++f )
    {
        nameToks[f] = nameHitsToks( nameHitsStem( ing.files[f] ) );
        pathToks[f] = nameHitsToks( ing.files[f] );
        lenSumName += double( nameToks[f].size() );
        lenSumPath += double( pathToks[f].size() );
        seen.clear();
        for( const std::string& t : nameToks[f] )
        {
            if( seen.emplace( t, std::uint8_t{ 1 } ).second )
            {
                ++dfName[ t ];
            }
        }
        seen.clear();
        for( const std::string& t : pathToks[f] )
        {
            if( seen.emplace( t, std::uint8_t{ 1 } ).second )
            {
                ++dfPath[ t ];
            }
        }
    }
    const double avgName = lenSumName / double( F );
    const double avgPath = lenSumPath / double( F );

    out.reserve( F );
    HashMap<std::string, std::uint32_t> tf;   // per-file, per-field scratch
    for( std::size_t f = 0; f < F; ++f )
    {
        double score = 0.0;
        for( int fi = 0; fi < 2; ++fi )
        {
            const std::vector<std::string>&            doc = fi == 0 ? nameToks[f] : pathToks[f];
            const double                                w   = fi == 0 ? 3.0 : 2.0;
            const double                                avg = fi == 0 ? avgName : avgPath;
            const HashMap<std::string, std::uint32_t>&  df  = fi == 0 ? dfName : dfPath;
            if( doc.empty() )
            {
                continue;
            }
            tf.clear();
            for( const std::string& t : doc )
            {
                if( qset.find( t ) != qset.end() )
                {
                    ++tf[ t ];
                }
            }
            for( const auto& [ t, c ] : tf )
            {
                const auto           dfIt  = df.find( t );
                const std::uint32_t  dfN   = dfIt == df.end() ? 0u : dfIt->second;
                const double         idf   = nameHitsIdf( F, dfN );
                const double         denom = double( c ) + kNameHitsK1 * ( 1.0 - kNameHitsB + kNameHitsB * double( doc.size() ) / std::max( 1e-9, avg ) );
                score += w * idf * double( c ) * ( kNameHitsK1 + 1.0 ) / denom;
            }
        }
        if( score > 0.0 )
        {
            out.push_back( NameHitsRanked{ std::uint32_t( f ), score } );
        }
    }
    std::sort( out.begin(), out.end(), [ & ]( const NameHitsRanked& a, const NameHitsRanked& b )
    {
        if( a.score != b.score )
        {
            return a.score > b.score;
        }
        return ing.files[ a.fileId ] < ing.files[ b.fileId ];
    } );
    // postcondition (debug-only — the scan itself is real work, so DASSERT not ENSURES): every candidate
    // this function hands back is a real, positive-score, in-range file.
    DASSERT( std::all_of( out.begin(), out.end(), [ F ]( const NameHitsRanked& r ) { return r.fileId < F && r.score > 0.0; } ),
             "namehits: rankNameHits must return only in-range, positive-score files" );
    return out;
}

// the element itself: up to kNameHitsMaxRows of `ranked` whose display path (lensRowPath) is not already
// in `namedPaths` (the answer's own p= rows — sigs + the deep tail actually shown).
// N3 (round 3, PLAN_OUTPUT_ROUTING_LOOP_2026-09-12_REPORTS/13_round3_PREREG.md §2.1, Amendment 1 Q6): a
// picked list of ZERO now emits NOTHING — no element at all, not even a self-closed "n=0" one. The old
// B1.4-style "a count states reality" reasoning is superseded by the owner's Q6 answer: absence already
// reads as "not computed" on the explicit-budget regime (forNameHitsOn=false), so an empty default-regime
// answer is now spelled the same way. Callers must treat "" as "omit this element and its definition".
// Returns the ELEMENT ONLY — no over_ceiling attribute, no trailing comment, no suffix (this is exactly
// the "E" the round-3 over_ceiling predicate prices; see finishNameHitsXml below).
inline std::string renderNameHitsXml( const IngestResult& ing, const std::vector<NameHitsRanked>& ranked,
                                       const HashMap<std::string, std::uint8_t>& namedPaths,
                                       std::string_view rootArg, std::vector<char>& esc )
{
    std::vector<std::string> picked;
    picked.reserve( kNameHitsMaxRows );
    for( const NameHitsRanked& r : ranked )
    {
        if( picked.size() >= kNameHitsMaxRows )
        {
            break;
        }
        std::string p = lensRowPath( ing, r.fileId, rootArg );
        if( namedPaths.find( p ) != namedPaths.end() )
        {
            continue;
        }
        picked.push_back( std::move( p ) );
    }
    // the honesty contract (rv-prereg2.md R2): n= is the TRUE served count, never padded — this loop is
    // the only place that can grow `picked`, and its own break already bounds it; ENSURES makes the cap
    // a checked fact instead of a property that happens to hold today.
    ENSURES( picked.size() <= kNameHitsMaxRows, "namehits: renderNameHitsXml must never pad past the registered cap" );
    if( picked.empty() )
    {
        return {};   // Q6: empty answer, nothing rides — no element, no definition (finishNameHitsXml mirrors this)
    }
    std::string x = "<namehits n=\"" + std::to_string( picked.size() ) + "\">";
    for( const std::string& p : picked )
    {
        x += "<nh p=\"";
        x += escapeXml( p, esc );
        x += "\"/>";
    }
    x += "</namehits>";
    return x;
}

// Definitions, verbatim (PREREG round 3 §2.1 + Amendment 1c). N3 moves the definition OFF the top legend
// and onto a trailing XML comment immediately after the element's own end — these are the comment's INNER
// text only (no "<!--"/"-->" wrapper, added by finishNameHitsXml so the over_ceiling suffix can be spliced
// in before the close). Wrapped: FULL 200 B, COMPACT 92 B (§2.1's registered byte counts).
inline constexpr std::string_view kForNameHitsDefFull =
    "namehits: up to 3 files this answer did not already name, ranked ONLY by how many query words their "
    "file name (x3) and directory path (x2) contain (BM25); a lookup, NOT graph evidence; n= shown";
inline constexpr std::string_view kForNameHitsDefCompact =
    "namehits/nh: <=3 unnamed files by name/path word match (not graph evidence); n= shown";
// A1.1 / Amendment 1c #2: present-only suffix, inside the same trailing comment, exactly when the element
// carries over_ceiling="1". Wrapped totals: FULL 235 B, COMPACT 127 B.
inline constexpr std::string_view kForNameHitsOverCeilingSuffix = "; over_ceiling=1: past budget_bytes";

// Amendment 1c #2 — the over_ceiling predicate, pinned to one code sum shared by both --for dialects (CLI
// and MCP): does the ranked payload, PLUS this element alone (E — no attribute, no comment, no suffix),
// exceed the ceiling the composer already computed for the ranked payload? `fixedBytesForHeader` and
// `sigSideCeiling` are the composer's own values (verbs_for.h ~2651-2657 / mcpverbs.h ~1963-1965, N3
// header — no namehits clause in either); `sigsStr`/`tailStr` are the rendered strings already charged.
inline bool nameHitsOverCeiling( std::size_t fixedBytesForHeader, std::size_t sigsBytes, std::size_t tailBytes,
                                  std::size_t elementOnlyBytes, std::size_t sigSideCeiling ) noexcept
{
    return fixedBytesForHeader + sigsBytes + tailBytes + elementOnlyBytes > sigSideCeiling;
}

// Splices the over_ceiling attribute (when set) onto `elem` and appends the trailing definition comment —
// the ONE place both --for dialects finish the element, so they cannot drift (task item 5). `elem` must be
// exactly renderNameHitsXml's return: "" (Q6 — returned unchanged, nothing to finish) or a well-formed
// "<namehits n=\"K\">...</namehits>" with K>=1 (never self-closing — Q6 removed the only self-closing case).
inline std::string finishNameHitsXml( std::string elem, bool compactDialect, bool overCeiling )
{
    if( elem.empty() )
    {
        return elem;   // Q6: no element ⇒ no attribute, no comment — nothing rides
    }
    if( overCeiling )
    {
        const std::size_t openEnd = elem.find( '>' );
        ENSURES( openEnd != std::string::npos, "namehits: finishNameHitsXml expects a well-formed opening tag" );
        elem.insert( openEnd, " over_ceiling=\"1\"" );
    }
    elem += "<!--";
    elem += ( compactDialect ? kForNameHitsDefCompact : kForNameHitsDefFull );
    if( overCeiling )
    {
        elem += kForNameHitsOverCeilingSuffix;
    }
    elem += "-->";
    return elem;
}

}   // namespace rw
