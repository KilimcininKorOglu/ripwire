#pragma once
// forpage.h — L-W (routing-loop round, owner decision 2026-09-12): --for's FILE-GRAIN WIDENING PAGE, its
// coverage= gauge, and the rule that makes --for's next= point at the page when the answer is thin.
//
// THE DEFECT THIS CLOSES. On the pre-registered follow-up ladder (RocksDB, frozen 30), every ripwire
// follow-up completed 0 answers through step 4: --for's next= pointed at --expand (a BODY, not a wider
// list), --top-k was INERT on --for, and --format=candidates is symbol-grain (40 symbols is about 18 files
// in 11 KB). The one follow-up that completed answers in that ladder was a file-grain page — one row per
// file, about 150 B each, +8 completes at ~6 KB — and local telemetry had --for -> --expand followed 0 of
// 259 times. So: `--for=TASK --limit=N` (offset=M pages it) is that page, `coverage=` on --for's root says
// how much of the query the top-ranked symbol actually carries, and when the answer is THIN the r=1 row's
// next= names the page instead of the body.
//
// ONE implementation for both dialects. The CLI --for (verbs_for.h) and the MCP `for` twin (mcpverbs.h) both
// call computeForFilePage/renderForFilePageXml on the SAME lensRank and the SAME LexTermEvidence, so the two
// surfaces cannot rank or render the page differently (the computeFileTail precedent).
//
// THE SCORE, stated so it can be re-derived. For a file f, over its top kForPageUnionSymbolCap positive-score
// symbols in lens order:
//     U_f = Σ_{u ∈ union of the symbols' term masks} idf(u)  /  Σ_{u ∈ query terms} idf(u)
// — the IDF-weighted share of the query's unique subtokens the file covers BETWEEN its symbols. It is bounded
// (≤ 1, a set share) and file-first by construction: a file whose symbols match several distinct terms
// outranks one that matches one term many times, and one huge file cannot monopolise the page because only
// its top few symbols contribute and a term counts once. Ties break by the file's best symbol's lens score
// (the same statistic the ranked head and the <tail> use), then by path — a total order, so the page is
// deterministic and --offset=M is the exact continuation of --limit=M (pageview.h). The mechanism is the one
// Graft's `ask --limit` rows use (file-first over a per-file union coverage); the arithmetic here is ripwire's.
//
// coverage= is the same share for ONE symbol (the r=1 row's) over ALL its fields — name, doc comment and body,
// because the persisted lexical statistics (lexindex.h) carry doc+body as one field and separating them would
// need a second read of the file. An unmatched query term weighs as the rarest possible term (BM25's own idf
// at df 0), never as nothing, so a query dragging a "(#12147)" token along reports the lower coverage that
// honestly describes it.
//
// THE THIN RULE (kForThinCoveragePct / kForThinMinFiles, stated in both legends): an answer is thin when the
// top-ranked symbol covers under 50% of the query's IDF mass, or when the ranked head (the top rows before any
// budget trim) spreads over fewer than 3 files. Thin ⇒ the root carries coverage= with its clause and next= names
// `--for=TASK --limit=40`; a CONFIDENT answer carries none of them (owner decision 2026-09-12: present-only) and
// keeps `--expand=FILE:NAME`. The thresholds are a registered hypothesis (PLAN_OUTPUT_ROUTING_LOOP §1.5 L-N),
// not a tuned number: the routing-loop ladder measures them, and a later round moves them with a measured reason.
//
// EXTEND-3 (routing-loop round 2, R2-L3′, re-registration of round-1 L3 as "extend3" — PLAN_OUTPUT_ROUTING_LOOP_
// 2026-09-12_REPORTS/12_round2_PREREG.md §R3, Amendment 1 item 3). Round-1's L3 re-sorted the WHOLE page by a
// score+path-overlap blend and self-rejected (it could DISPLACE a shipped row and lose gold — see that lane's
// frozen q21 loss). extend3 is the cheapest variant that cannot lose a shipped row: every row this call already
// shows (window.begin..window.end, unchanged order, unchanged attributes) stays exactly as it was; up to
// kForPageExtendMaxRows MORE rows are appended AFTER them, drawn only from the rows this call does not already
// show (window.end..total), chosen by the SAME blend key L3 registered (score/100 + path-subtoken overlap share).
// offset=0 ONLY (the single "follow-up page", not a walk-wide feature) — a later --offset= page of the same
// walk appends nothing, so a row offset=0 pulled in as "extra" can never collide with a row a later page of
// the SAME walk legitimately shows (forwidencheck.sh arm (3)'s no-overlap / concatenation invariant). So a
// file the task names by path can surface even when its lens score alone would not earn it a shown slot.
// The appended rows carry p= and score= only (no n=/sym=: they were never absorbed into a <ctx> ranking pass,
// so naming their symbols would overstate what the row is — a lookup, not graph evidence) and the root gains
// extra="K" (present-only: K==0 says nothing a reader needs). Branch-base note: this file cherry-picks only
// L3's tokenizer/key helpers (kForPageBlendStop, forPageBlendToks, forPageBlendKeyGreater) from
// origin/lane/r1-page-blend:src/forpage.h (965a942d) — not that lane's page re-sort call site, and not its
// infra/tablelookup.h / tracein.h changes (this branch never took those), so forPageBlendToks calls a small
// local digit predicate instead of the shared rw::isDigits that lane introduced elsewhere.

#include "infra/Diagnostics.h"  // ASSUME / ENSURES — self-checks on the extend-3 selection
#include "lexical.h"     // LexTermEvidence — the term masks + df the BM25 pass already accumulated
#include "model.h"
#include "nextverb.h"    // nextFlag / nextAttrXml / kNextAttrMaxBytes — the ONE next= spelling
#include "pageview.h"    // pageWindow / pageDisclosure — the shared --limit/--offset vocabulary
#include "serialize.h"   // escapeXml, lensRowPath, ctxRootOpen, radixSortByScoreDescId
#include "taskroute.h"   // rw::taskroute::isOneOf — reused as-is (L3's stopword check; not cloned)
#include "testmap.h"     // splitChangedFilesOfSymbols — the ONE "distinct files of a symbol set" walk (--affected's)

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr int         kForPageRowsDefault    = 40;   // `--for --limit=N` with no N is never accepted (the flag refuses 0);
                                                            //   this is the N the r=1 row's widening next= spells
inline constexpr std::size_t kForPageUnionSymbolCap = 8;    // symbols per file whose term masks join that file's union
inline constexpr std::size_t kForPageSymNameCount   = 3;    // sym= names the file's top symbols by lens rank, this many
inline constexpr int         kForThinCoveragePct    = 50;   // coverage= below this ⇒ thin (see the header)
inline constexpr std::size_t kForThinMinFiles       = 3;    // a ranked head over fewer files than this ⇒ thin

// The IDF-weighted share (whole percent) of the query's unique subtokens present in `mask` (maskWords words).
// -1 when the evidence is unmeasured (no query terms — the empty-query shape lexicalScoresTiered returns early on).
inline int termShareWithin( const LexTermEvidence& ev, const std::uint64_t* mask ) noexcept
{
    const std::size_t termCount = ev.terms.size();
    if( termCount == 0 || ev.df.size() != termCount || ev.maskWords * 64 < termCount )
    {
        return -1;
    }
    double total = 0.0, matched = 0.0;   // fixed u-ascending order: the sum is deterministic
    for( std::size_t u = 0; u < termCount; ++u )
    {
        const double w = ev.idf( u );
        total += w;
        if( LexTermEvidence::hasBit( mask, u ) )
        {
            matched += w;
        }
    }
    if( !( total > 0.0 ) )
    {
        return -1;
    }
    return int( 100.0 * matched / total + 0.5 );
}

// coverage= for one symbol: its any-field mask (name, doc comment, body).
inline int forCoveragePct( const LexTermEvidence& ev, NodeId sym ) noexcept
{
    if( ev.maskWords == 0 || sym >= ev.symbolCount || ev.anyMask.size() != ev.symbolCount * ev.maskWords )
    {
        return -1;
    }
    return termShareWithin( ev, ev.anyMaskOf( sym ) );
}

// the r=1 symbol of a ranking: the highest score, lowest id on a tie (the (score desc, id asc) order every
// --for consumer selects with); kNoNode when nothing scored above zero — there is no top-ranked symbol then
inline NodeId topLensId( const std::vector<float>& rank ) noexcept
{
    NodeId best = kNoNode;
    for( std::size_t i = 0; i < rank.size(); ++i )
    {
        if( rank[i] > 0.0f && ( best == kNoNode || rank[i] > rank[best] ) )
        {
            best = NodeId( i );
        }
    }
    return best;
}

// The legend clause defining coverage= and the thin rule — FULL dialect (rides --for's confidence sentence and
// the MCP twin's, so one spelling) and COMPACT dialect. No "--" anywhere (an XML comment, G4): the flags are named
// without their dashes.
inline constexpr std::string_view kForCoverageLegend =
    " [coverage= is the IDF-weighted share (whole percent) of the query's subtokens in the top-ranked symbol's name, "
    "doc or body; an unmatched subtoken weighs as the rarest. It rides a THIN answer only (under 50, or a head over "
    "fewer than 3 files), whose r=1 row's next= names the file-grain page (limit=N, one row per file), not the body]";
inline constexpr std::string_view kForCompactCoverageClause =
    " [coverage=: IDF share (%) of the query's subtokens in the top symbol's name/doc/body, on a THIN answer only "
    "(under 50 or head files under 3); next= then names the file page (limit=N)]";

inline bool forAnswerIsThin( int coveragePct, std::size_t distinctHeadFiles ) noexcept
{
    return coveragePct < kForThinCoveragePct || distinctHeadFiles < kForThinMinFiles;
}

// distinct files among the ranked head — the top rows BEFORE any budget trim, so the rule reads a fact the
// header already fixed rather than one the ladder decides later. The walk is --affected's own (testmap.h), which
// partitions the files into test and non-test; the rule wants the whole count, so the two halves are summed.
inline std::size_t distinctFilesOf( const IngestResult& ing, const std::vector<NodeId>& headIds )
{
    const ChangedFileSplit split = splitChangedFilesOfSymbols( ing, headIds );
    return split.src.size() + split.tests.size();
}

// `--for=TASK --limit=N [--offset=M]`, the task quoted as a shell would need it (nextFlag). "" when the
// invocation would not fit kNextAttrMaxBytes — a hint that pastes wrong is worse than no hint (the flipimpact.h
// rule), and the paging quintet still says how to continue.
inline std::string forPageInvocation( std::string_view task, int limit, int offset )
{
    std::string inv = nextFlag( "--for=", task );
    inv += " --limit=" + std::to_string( limit );
    if( offset > 0 )
    {
        inv += " --offset=" + std::to_string( offset );
    }
    return inv.size() > kNextAttrMaxBytes ? std::string() : inv;
}

// the r=1 row's widening follow-up: the page at its default width
inline std::string forWidenNext( std::string_view task )
{
    return forPageInvocation( task, kForPageRowsDefault, 0 );
}

struct ForFileRow
{
    std::uint32_t fileId      = 0;
    std::uint32_t symbolCount = 0;      // positive-score symbols in the file (n=)
    float         best        = 0.f;    // the file's best symbol's lens score (the tie-break)
    double        share       = 0.0;    // U_f in [0,1] — the score
    NodeId        top[ kForPageSymNameCount ] = { kNoNode, kNoNode, kNoNode };
};

struct ForFilePage
{
    std::vector<ForFileRow> rows;   // EVERY positive-score file, page order — the window is applied at render
};

// one more positive-score symbol of a file, in lens order: its terms join the union while the file is under the
// contribution cap, its name joins sym= while the file is under the name count, and n= counts it either way
inline void forFileRowAbsorb( ForFileRow& row, std::uint64_t* unionWords, const LexTermEvidence& ev, NodeId id, bool evidenceOk )
{
    if( evidenceOk && row.symbolCount < kForPageUnionSymbolCap && id < ev.symbolCount )
    {
        const std::uint64_t* src = ev.anyMaskOf( id );
        for( std::size_t w = 0; w < ev.maskWords; ++w )
        {
            unionWords[w] |= src[w];
        }
    }
    if( row.symbolCount < kForPageSymNameCount )
    {
        row.top[ row.symbolCount ] = id;
    }
    ++row.symbolCount;
}

// (share desc, best desc, path asc): a total order — paths are unique per file
inline bool forFileRowBefore( const IngestResult& ing, const ForFileRow& a, const ForFileRow& b ) noexcept
{
    if( a.share != b.share ) { return a.share > b.share; }
    if( a.best != b.best )   { return a.best > b.best; }
    return ing.files[ a.fileId ] < ing.files[ b.fileId ];
}

// The page's ranking, from the finished lens ranking (every lift applied) and the term evidence.
inline ForFilePage computeForFilePage( const IngestResult& ing, const std::vector<float>& rank, const LexTermEvidence& ev )
{
    ForFilePage       out;
    const std::size_t S = std::min( ing.symbols.size(), rank.size() );
    const std::size_t F = ing.files.size();
    if( S == 0 || F == 0 )
    {
        return out;
    }
    std::vector<NodeId> order( S );
    for( NodeId i = 0; i < S; ++i )
    {
        order[i] = i;
    }
    sortutil::radixSortByScoreDescId( order, rank );

    const std::size_t          words      = ev.maskWords;
    const bool                 evidenceOk = words > 0 && ev.anyMask.size() == ev.symbolCount * words;
    std::vector<std::uint32_t> rowOfFile( F, UINT32_MAX );
    std::vector<std::uint64_t> unionMask;   // rows × words, grown as rows are opened
    for( std::size_t k = 0; k < S && rank[ order[k] ] > 0.0f; ++k )   // (score desc) order: the zero-score tail is contiguous
    {
        const NodeId        id = order[k];
        const std::uint32_t f  = ing.symbols[id].fileId;
        if( f >= F )
        {
            continue;
        }
        if( rowOfFile[f] == UINT32_MAX )
        {
            rowOfFile[f] = std::uint32_t( out.rows.size() );
            out.rows.push_back( ForFileRow{ f, 0u, rank[id], 0.0, { kNoNode, kNoNode, kNoNode } } );
            unionMask.resize( unionMask.size() + words, 0u );
        }
        forFileRowAbsorb( out.rows[ rowOfFile[f] ], unionMask.data() + std::size_t( rowOfFile[f] ) * words, ev, id, evidenceOk );
    }
    for( std::size_t r = 0; r < out.rows.size(); ++r )
    {
        const int pct     = evidenceOk ? termShareWithin( ev, unionMask.data() + r * words ) : -1;
        out.rows[r].share = pct < 0 ? 0.0 : double( pct ) / 100.0;
    }
    std::stable_sort( out.rows.begin(), out.rows.end(), [ & ]( const ForFileRow& a, const ForFileRow& b ) { return forFileRowBefore( ing, a, b ); } );
    return out;
}

// The full legend of the page document. No "--" anywhere: it rides inside an XML comment (G4), so the two
// flags are named without their dashes.
inline constexpr std::string_view kForPageLegend =
    ": the file-grain WIDENING page of the for lens (task= the query, route= which ranker answered and why, root= "
    "the crawl root), ONE row per file, every file holding a positive-score symbol for this task, ranked "
    "file-first: score= the IDF-weighted share of the query's subtokens the file's "
    "top 8 symbols cover between them (whole percent; a term counts once however often it recurs, so one huge "
    "file cannot monopolise), ties by the best symbol's lens score then path; n= positive-score symbols in the "
    "file; sym= its top symbols by lens rank; p= the file. coverage= is the lens root's gauge: the same share "
    "for the top-ranked symbol alone (name, doc and body). extra=K: K rows appended AFTER the ranked rows, "
    "chosen only by task-word overlap with the file path (not by score=); they carry p= score= only. "
    "shown=/total=/capped=1 when this page cut the list; "
    "offset=/limit=/has_more=/next_offset= page it and next= is the next page, pasted as-is";
inline constexpr std::string_view kForPageLegendCompact =
    ": file-grain widening page (task= the query, route= the ranker that answered), one <f> row per positive-score "
    "file: score= IDF-weighted share of the query's "
    "subtokens the file's top 8 symbols cover together (%, a term counts once), ties by best symbol then path; "
    "n= positive symbols; sym= top symbols; coverage= the top symbol's own share; "
    "extra=K: K path-word-matched rows appended after the ranked ones (p= score= only); "
    "shown=/total=/capped=1 when cut; "
    "offset=/limit=/has_more=/next_offset= page it, next= the next page; root= the crawl root";

// ── EXTEND-3 (routing-loop round 2, R2-L3′) — tokenizer + blend key, copied from L3 ─────────────────────
// The task-language stopwords the registered simulator's toks() drops: RocksDB's own file extensions
// (cc/h) plus the closed set of connective words the ladder's question templates use. This list IS the
// registered formula, not a re-derivation of it — keep it in lockstep with pagesim.py if either changes.
// Copied verbatim from origin/lane/r1-page-blend:src/forpage.h (965a942d).
inline constexpr std::string_view kForPageBlendStop[] =
{
    "cc", "h", "how", "does", "reach", "where", "is", "implemented", "the", "a", "to", "in", "of", "and",
    "for", "when", "rocksdb",
};

// The same tiny "non-empty, every byte 0-9" predicate L3 called (there, rw::isDigits, shared out of
// infra/tablelookup.h by that lane). This branch does not take that lane's infra/tablelookup.h or
// tracein.h changes (see the header note above), so this is a small local instance rather than a call
// into either file's version — same contract, kept file-local on purpose.
inline bool forPageIsDigits( std::string_view s ) noexcept
{
    return !s.empty() && std::all_of( s.begin(), s.end(), []( unsigned char c ) { return c >= '0' && c <= '9'; } );
}

// The SAME tokenizer the registered simulator (pagesim.py's toks()) runs: a lowercase letter directly
// followed by an uppercase one is a camelCase split (one rule — NOT the acronym-aware ladder
// rw::subtokens() applies), any run of non-alnum bytes splits, stopwords and pure-digit tokens are
// dropped. Deliberately not rw::subtokens(): that function also drops <2-byte tokens and folds an
// uppercase run into one token, a DIFFERENT, stricter contract than the one the band was measured on —
// reusing it would silently drift the shipped ranking away from the registered simulation. Copied
// verbatim (bar the isDigits substitution above) from origin/lane/r1-page-blend:src/forpage.h (965a942d).
inline void forPageBlendToks( std::string_view s, std::vector<std::string>& out )
{
    std::string cur;
    char        prevRaw = 0;
    auto        flush = [ & ]()
    {
        if( !cur.empty() && !taskroute::isOneOf( cur, std::begin( kForPageBlendStop ), std::size( kForPageBlendStop ) ) && !forPageIsDigits( cur ) )
        {
            out.push_back( cur );
        }
        cur.clear();
    };
    for( const char raw : s )
    {
        const unsigned char c     = static_cast<unsigned char>( raw );
        const bool          alnum = ( c >= '0' && c <= '9' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= 'a' && c <= 'z' );
        if( !alnum )
        {
            flush();
            prevRaw = 0;
            continue;
        }
        const bool camelBoundary = prevRaw >= 'a' && prevRaw <= 'z' && c >= 'A' && c <= 'Z';
        if( camelBoundary )
        {
            flush();
        }
        cur.push_back( char( c >= 'A' && c <= 'Z' ? c - 'A' + 'a' : c ) );
        prevRaw = raw;
    }
    flush();
}

// hits (WITH repeats, as the registered simulator counts them) of PATH's subtokens present in the task's
// subtoken set, and PATH's own subtoken count (never 0: an empty tokenization is a share of 0/1, not a
// div-by-zero). Kept as two integers, not a ratio — see forPageBlendKeyGreater for why. Copied verbatim
// from origin/lane/r1-page-blend:src/forpage.h (965a942d).
struct ForPageBlendPathHits
{
    std::size_t hits     = 0;
    std::size_t pathToks = 1;
};

inline ForPageBlendPathHits forPageBlendPathShare( std::string_view path, const std::vector<std::string>& taskToks )
{
    std::vector<std::string> pathToks;
    forPageBlendToks( path, pathToks );
    if( pathToks.empty() )
    {
        return {};
    }
    std::size_t hits = 0;
    for( const std::string& t : pathToks )
    {
        for( const std::string& q : taskToks )
        {
            if( t == q ) { ++hits; break; }
        }
    }
    ENSURES( hits <= pathToks.size(), "hits counts a subset of pathToks" );
    return { hits, pathToks.size() };
}

// One row's registered-formula term: scorePct/100 + W*(hits/pathToks), W=1, kept as three small integers
// rather than folded into one float. Compared EXACTLY by cross-multiplication (int64_t; scorePct <= 100
// and hits <= pathToks are both small, so the product never approaches overflow) — never as a float, for
// the determinism reason L3 documented (a float key ties two real rows within 1 ULP on this corpus under
// this TU's -ffast-math reassociation, which the determinism contract forbids drifting with the
// optimizer). Copied verbatim from origin/lane/r1-page-blend:src/forpage.h (965a942d).
struct ForPageBlendTerm
{
    int         scorePct = 0;
    std::size_t hits     = 0;
    std::size_t pathToks = 1;
};

inline bool forPageBlendKeyGreater( const ForPageBlendTerm& a, const ForPageBlendTerm& b ) noexcept
{
    ASSUME( a.pathToks > 0 && b.pathToks > 0, "forPageBlendPathShare never returns pathToks==0" );
    const std::int64_t lhs = std::int64_t( a.scorePct ) * std::int64_t( a.pathToks ) * std::int64_t( b.pathToks )
                            + std::int64_t( a.hits ) * 100 * std::int64_t( b.pathToks );
    const std::int64_t rhs = std::int64_t( b.scorePct ) * std::int64_t( a.pathToks ) * std::int64_t( b.pathToks )
                            + std::int64_t( b.hits ) * 100 * std::int64_t( a.pathToks );
    return lhs > rhs;
}

inline constexpr std::size_t kForPageExtendMaxRows = 3;   // extend-3: up to this many rows appended, never a re-sort

// extend-3's OWN selection (not L3's page re-sort): candidates are the rows THIS page does not already show
// — page.rows[windowEnd..total). offset ONLY: the PREREG names "the `--for --limit=N` follow-up page" (one
// page, not a walk-wide feature), so this fires on offset=0 alone — the r=1 row's own widening next= and the
// bare `--for --limit=N` call both land there. A later --offset= page of the SAME walk appends nothing: its
// shown window already starts past offset=0's window, but offset=0's own extend rows were drawn from ANYWHERE
// past ITS window (including rows a later page will legitimately show), so extending every offset would let
// page N's "extra" duplicate page N+1's real rows — the exact overlap forwidencheck.sh's arm (3) polices
// ("the second page has no row in common with the first", "pages 1+2 concatenate to the wider page"). Ranked
// by the blend key (exact integer compare, see forPageBlendKeyGreater) with an EXPLICIT path-string tie-break
// (never relies on the incoming order being a total order on its own). Returns up to kForPageExtendMaxRows
// indices into page.rows, in the order they should render.
inline std::vector<std::uint32_t> forPageExtendRows( const IngestResult& ing, const ForFilePage& page, std::string_view task,
                                                     std::string_view rootArg, std::size_t windowEnd, int offset )
{
    EXPECTS( windowEnd <= page.rows.size(), "windowEnd is a valid prefix bound of page.rows" );
    if( offset != 0 )
    {
        return {};
    }
    const std::size_t total = page.rows.size();
    std::vector<std::uint32_t> cand;
    cand.reserve( total > windowEnd ? total - windowEnd : 0 );
    for( std::size_t i = windowEnd; i < total; ++i )
    {
        cand.push_back( std::uint32_t( i ) );
    }
    if( cand.empty() )
    {
        return cand;
    }
    std::vector<std::string> taskToks;
    forPageBlendToks( task, taskToks );
    std::vector<ForPageBlendTerm> term( total );   // indexed by page.rows index; only cand[] entries are ever read
    for( const std::uint32_t idx : cand )
    {
        const ForFileRow& row     = page.rows[idx];
        const int          scorePct = int( row.share * 100.0 + 0.5 );
        ForPageBlendPathHits ph{};
        if( !taskToks.empty() )
        {
            ph = forPageBlendPathShare( lensRowPath( ing, row.fileId, rootArg ), taskToks );
        }
        term[idx] = ForPageBlendTerm{ scorePct, ph.hits, ph.pathToks };
    }
    std::sort( cand.begin(), cand.end(), [ & ]( std::uint32_t a, std::uint32_t b )
    {
        if( forPageBlendKeyGreater( term[a], term[b] ) ) { return true; }
        if( forPageBlendKeyGreater( term[b], term[a] ) ) { return false; }
        return ing.files[ page.rows[a].fileId ] < ing.files[ page.rows[b].fileId ];   // exact tie: path string
    } );
    if( cand.size() > kForPageExtendMaxRows )
    {
        cand.resize( kForPageExtendMaxRows );
    }
    ENSURES( cand.size() <= kForPageExtendMaxRows, "extend-3 never appends more than kForPageExtendMaxRows rows" );
    return cand;
}

// What the page document is rendered from, beside the rows: the task and the lens root's own open tag (ctxRootOpen's
// output — task=/route=/root= and the scrub tells — re-tagged <files>, so the two roots spell and escape their shared
// attributes identically), the coverage= gauge, the window, and the dialect.
struct ForPageRenderParts
{
    std::string_view task;
    std::string_view rootOpen;
    int              coveragePct;
    int              limit;
    int              offset;
    std::string_view rootArg;
    bool             compactLegend;
};

inline std::string renderForFilePageXml( const IngestResult& ing, const ForFilePage& page, const ForPageRenderParts& p )
{
    std::vector<char> esc;
    std::string       x;
    x.reserve( 512 + page.rows.size() * 120 );
    const std::size_t total  = page.rows.size();
    const PageWindow  window = pageWindow( total, p.limit, p.offset );
    const std::size_t shown  = window.end - window.begin;
    // extend-3 (R2-L3′): chosen ONCE, over the rows this call does not already show, before any XML is
    // written — the shown rows above are untouched (same slice, same order, same attributes as before
    // this lever existed; see forwidencheck.sh's byte-identity arm).
    const std::vector<std::uint32_t> extendRows = forPageExtendRows( ing, page, p.task, p.rootArg, window.end, p.offset );
    ENSURES( extendRows.size() <= kForPageExtendMaxRows, "extend-3 root attribute and row count must agree" );

    x += "<files";
    if( p.rootOpen.size() > 5 && p.rootOpen.substr( 0, 4 ) == "<ctx" && p.rootOpen.back() == '>' )
    {
        x.append( p.rootOpen.data() + 4, p.rootOpen.size() - 5 );   // the attributes between "<ctx" and ">"
    }
    if( p.coveragePct >= 0 )
    {
        x += " coverage=\"" + std::to_string( p.coveragePct ) + "\"";
    }
    if( !extendRows.empty() )
    {
        x += " extra=\"" + std::to_string( extendRows.size() ) + "\"";   // present-only: 0 says nothing a reader needs
    }
    char disc[ kPageDisclosureCap ];
    x += pageDisclosure( disc, sizeof( disc ), shown, total, window.end, p.limit, p.offset, /*discloseCap=*/true );
    if( window.end < total )
    {
        x += nextAttrXml( forPageInvocation( p.task, p.limit > 0 ? p.limit : kForPageRowsDefault, int( window.end ) ) );
    }
    x += ">";
    x += p.compactLegend ? "<!-- ripwire for-page ripwire.for-page/v1" : "<!-- ripwire for-page";
    x += p.compactLegend ? kForPageLegendCompact : kForPageLegend;
    x += " -->";
    x += forRootRelPathsLegendShort( !p.rootArg.empty() );
    for( std::size_t r = window.begin; r < window.end; ++r )
    {
        const ForFileRow& row = page.rows[r];
        x += "<f p=\"";  x += escapeXml( lensRowPath( ing, row.fileId, p.rootArg ), esc );
        x += "\" score=\"" + std::to_string( int( row.share * 100.0 + 0.5 ) );
        x += "\" n=\"" + std::to_string( row.symbolCount ) + "\" sym=\"";
        for( std::size_t k = 0; k < kForPageSymNameCount && row.top[k] != kNoNode; ++k )
        {
            if( k > 0 ) { x += ","; }
            x += escapeXml( ing.symbols[ row.top[k] ].name, esc );
        }
        x += "\"/>";
    }
    // extend-3: appended AFTER every ranked row, p= score= only (never n=/sym= — these rows were picked by
    // path-word overlap, not absorbed into the union-coverage ranking pass the other rows carry evidence of).
    for( const std::uint32_t idx : extendRows )
    {
        const ForFileRow& row = page.rows[idx];
        x += "<f p=\"";  x += escapeXml( lensRowPath( ing, row.fileId, p.rootArg ), esc );
        x += "\" score=\"" + std::to_string( int( row.share * 100.0 + 0.5 ) ) + "\"/>";
    }
    x += "</files>";
    return x;
}

}   // namespace rw
