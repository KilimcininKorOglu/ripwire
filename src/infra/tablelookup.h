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
// isOneOf / isDigits (added routing-loop round 1, Amendment 1 fix round): the same "small constexpr
// table, linear scan" shape as findByField above, one level simpler — membership, not row lookup.
// `--quality-delta` flagged forpage.h's own hand-rolled stopword-membership loop as a clone of FIVE
// unrelated predicates (lintrules.h::isValidSeverity, mcp.h::isMcpProtocolVersionSupported,
// mcpverbs.h::mcpVerbDeclaresLegend, skillscan.h::detail::toolAllowed, hasNode) that each write the
// identical "is this string_view one of these?" any_of by hand, and forpage.h's own all-digits loop as
// a clone of tracein.h::detail::isDigits. Both land here rather than in either caller for the same
// reason findByField does: infra/ is below every caller and depends on none of them, so fixing the
// clone does not couple forpage.h to tracein.h or to any of the five predicate call sites (none of
// which this fix touches — out of scope for the lane that found it).
#include <cstddef>
#include <span>
#include <string_view>

namespace rw
{

// "is `word` one of `table`?" — table is typically a small constexpr std::string_view[] (a fixed array
// converts to std::span implicitly), so this binds without an explicit std::size().
inline bool isOneOf( std::string_view word, std::span<const std::string_view> table ) noexcept
{
    for( const std::string_view t : table )
    {
        if( t == word ) { return true; }
    }
    return false;
}

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
