#pragma once
// tablelookup.h — find a row in a small constexpr table by one of its string fields.
//
// WHY THIS EXISTS. Two independent layers grew the identical function: `lookupLang` (ingest, maps a
// file extension to a language row) and `agentTarget` (wrap, maps an agent name to its target row).
// Both are a linear scan over a constexpr array comparing one std::string_view member, returning a
// pointer or nullptr. `--quality-delta` flagged the second as a clone of the first and refused the
// change, which was correct.
//
// It lives in infra/ rather than in either caller because the alternative was worse: wrap.h and
// ingest_crawl.h share no header, so deduplicating in place would have coupled the CLI's agent table
// to the ingest hot path (lookupLang has ~21 call sites across six ingest translation units) purely to
// satisfy a lint. infra/ is below both and depends on neither, so nothing is coupled to anything.
//
// LINEAR, deliberately. These tables are ~8 and ~40 rows; a linear scan over contiguous constexpr
// storage beats any lookup structure at this size and keeps the call constant-foldable. Do not
// "optimize" this into a hash without a measurement showing one of these tables grew enough to matter.
//
// isDigits (added routing-loop round 1, Amendment 1 fix round): the same "tiny, dependency-free string
// predicate two headers independently need" shape findByField's own header note argues for. forpage.h's
// stopword-membership check reuses the EXISTING rw::taskroute::isOneOf (src/taskroute.h) directly rather
// than gaining a new symbol here — quality-delta's clone census flags a clone pair the moment either
// side is NEW, so introducing a fresh isOneOf here (even a byte-identical move of taskroute.h's own)
// still counted as a new instance of the shape five other predicates already share (lintrules.h::
// isValidSeverity, mcp.h::isMcpProtocolVersionSupported, mcpverbs.h::mcpVerbDeclaresLegend,
// skillscan.h::detail::toolAllowed, hasNode) — reusing the untouched symbol is the only shape that adds
// no new clone site. isDigits had only ONE prior instance (tracein.h::detail), so moving it here is
// clean: infra/ is below both callers and depends on neither, same as findByField's own precedent.
#include <cstddef>
#include <string_view>

namespace rw
{

// moved from tracein.h::detail (routing-loop round 1 Amendment 1 fix round): a second caller
// (forpage.h) needed the identical "every byte 0-9, and at least one byte" predicate, and infra/ is
// where a helper goes once it has two callers in headers that share nothing else (the findByField
// precedent above). Behaviour unchanged: empty is false, never a vacuous true.
inline bool isDigits( std::string_view s ) noexcept
{
    if( s.empty() )
    {
        return false;
    }
    for( const char c : s )
    {
        if( c < '0' || c > '9' )
        {
            return false;
        }
    }
    return true;
}

// Row is deduced from the MEMBER POINTER, not from the container, so this binds to a C array and to a
// std::array alike — the two callers happen to use one of each (wrap's kAgentTargets is a plain array,
// ingest's kLangTable is a std::array<LangEntry, 46>).
// The KEY type is deduced too, not fixed to string_view: the third caller (lanes.h::findClaimByKey)
// matches a std::uint64_t. --quality-delta found that one — it flagged this helper as a clone of it,
// which is how a two-instance dedup turned out to be a three-instance one.
template< typename Table, typename Row, typename Key, typename Wanted >
constexpr const Row* findByField( const Table& rows, Key Row::*field, const Wanted& wanted ) noexcept
{
    for( const Row& r : rows )
    {
        if( r.*field == wanted )
        {
            return &r;
        }
    }
    return nullptr;
}

}   // namespace rw
