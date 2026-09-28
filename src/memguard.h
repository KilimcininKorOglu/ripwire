#pragma once

// memguard.h — #350 layer 3: a memory guard on every root, zero-config, silent on every normal run.
//
// WHY. ripwire held no bound on its own memory. An MCP server started in a home directory crawled it for seven hours
// and reached a 67 GB footprint (issue #350); nothing in the process measured memory at all. Layer 1 (rootguard.h)
// refuses the roots nobody chose; this guard is what protects the roots somebody did choose.
//
// THE LIMIT. The hard limit is 65% of the machine's memory — physical RAM, or the cgroup's memory.max when that is
// lower — so the default derives from the machine and nobody configures it. `--max-memory=<N>[K|M|G]` (or the
// RIPWIRE_MAX_MEMORY environment variable; the flag wins) replaces it; below kFloorBytes a value is refused as a typo,
// never obeyed. When the machine cannot say how much RAM it has the footprint cap is off and only the pressure signal
// remains.
//
// THE LINES, measured on the process footprint (os::mem_footprint):
//   crawl  stops when the footprint has GROWN by limit/8 since this ingest began, or reaches half the limit. The
//          crawl's own cost is ~1-3 KB per file (#350's measurements), so a crawl that alone reaches an eighth of the
//          limit is a tree whose parse could never fit; stopping there is what leaves room to answer.
//   parse  stops at half the limit. The other half is what the model build, the graph and the answer need: measured
//          2026-09-28 on a 160,000-file synthetic C tree, the ingest's own tail (dedup, symbols, attribution) grows the
//          footprint ~1.5x past the moment the parse stops, and with a 4/5 line every stop the 5 s cadence caught
//          became a hard stop after the ingest instead of a partial answer.
//   hard   at the limit itself, checked between phases (main.cpp) and before each MCP tool call: no partial answer.
//   pressure: the OS signal (os::mem_pressure) at "critical" stops the crawl or the parse too — but only once this
//          process holds at least max( 256 MiB, limit/8 ), so a small run is never cut because something ELSE is
//          using the machine. It never causes a hard stop.
//
// THE COST. Nothing is measured until five seconds after an ingest starts (owner decision, #350: the runaway adds
// ~15 MB per 5 s), and then at most once per five seconds: the crawl looks every 1,024 entries, the parse on each file
// completion, and only the thread that wins the time slot pays the syscall. A run shorter than five seconds — every
// normal run on every tree we measure — reads the footprint once at ingest start and never again, and its output is
// byte-identical to a run with no guard at all (test/memguardcheck.sh (C)). No thread, no timer, no signal handler.
//
// THE STOP. A soft stop sets an atomic flag the crawl loop and the parse workers read before the next unit of work,
// records WHY through DISCLOSE on IngestResult::memoryStop, and lets ingest() finish with what it has: the crawl keeps
// the entries it saw (then sorts them, as always); the parse keeps the unbroken prefix of its work order that
// finished (a worker checks the flag BEFORE claiming a file, so every claimed file completes). A partial parse is
// never written to the cache. Whether the partial ingest may answer is the caller's decision — main.cpp answers the
// default map with memory_stop= in its header and refuses every other verb (exit 5); the MCP server answers with
// `_memory_stop` in the envelope.
//
// THE TEST SEAM. RIPWIRE_TEST_MEMGUARD=crawl:N | parse:N | request:N replaces the footprint READING with a trip at
// the Nth guarded crawl entry, the Nth parsed file, or the Nth MCP tool-call pre-check, and turns the time gate off, so
// test/memguardcheck.sh can drive every stop path deterministically. The stops themselves are the real code paths.

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iterator>
#include <string>
#include <string_view>

#include "infra/Diagnostics.h"   // VALIDATE — the environment is external input
#include "infra/os.h"            // rw::os::mem_footprint / mem_physical / mem_cgroup_max / mem_pressure
#include "model.h"               // MemoryStop — the disclosure sink

namespace rw::memguard
{

inline constexpr std::uint64_t kMiB             = 1024ull * 1024ull;
inline constexpr std::uint64_t kFloorBytes      = 64ull * kMiB;              // --max-memory below this is a typo, refused
inline constexpr std::uint64_t kPressureMinimum = 256ull * kMiB;             // pressure never cuts a run smaller than this
inline constexpr std::int64_t  kCheckIntervalNs = 5'000'000'000;             // owner, #350: five seconds between readings
inline constexpr std::uint32_t kCrawlStride     = 1024;                      // crawl entries between time-gate looks
static_assert( ( kCrawlStride & ( kCrawlStride - 1 ) ) == 0, "the crawl stride is a mask" );

enum class Source : std::uint8_t
{
    Default,   // 65% of the machine's memory
    Flag,      // --max-memory
    Env,       // RIPWIRE_MAX_MEMORY
};

// The process-wide limit. Written once by main() before any worker thread exists (install), read everywhere after.
struct Limits
{
    std::uint64_t hardBytes = 0;   // 0 = the machine's memory is unknown: no footprint cap, pressure only
    Source        source    = Source::Default;
};
inline Limits& limitsSlot() noexcept
{
    static Limits slot;
    return slot;
}
inline const Limits& limits() noexcept { return limitsSlot(); }

// 65% of min( physical RAM, cgroup memory.max ), or 0 when the machine cannot say how much RAM it has.
inline std::uint64_t defaultLimitBytes()
{
    std::uint64_t machine = os::mem_physical();
    const std::uint64_t cgroup = os::mem_cgroup_max();
    if( cgroup != 0 && ( machine == 0 || cgroup < machine ) )
    {
        machine = cgroup;
    }
    return machine / 100 * 65;
}

// the limit as a --max-memory value ("10854M"): what the reader would type to raise it — so always in whole MiB,
// rounded up, the spelling every disclosure and message uses
inline std::string limitSpelling( std::uint64_t bytes )
{
    return std::to_string( ( bytes + kMiB - 1 ) / kMiB ) + "M";
}

// ── the test seam ──────────────────────────────────────────────────────────────────────────────────────────
enum class TripAt : std::uint8_t
{
    Nowhere,
    Crawl,
    Parse,
    Request,
};
struct TestTrip
{
    TripAt        at    = TripAt::Nowhere;
    std::uint64_t index = 0;   // 1-based: the Nth guarded unit trips
};
// RIPWIRE_TEST_MEMGUARD, read once. A malformed value is no seam at all (the variable is for gates only).
inline const TestTrip& testTrip() noexcept
{
    static const TestTrip trip = []() noexcept
    {
        TestTrip          t;
        const char* const env = std::getenv( "RIPWIRE_TEST_MEMGUARD" );
        if( env == nullptr )
        {
            return t;
        }
        const std::string_view v( env );
        const std::size_t      colon = v.find( ':' );
        if( !VALIDATE( colon != std::string_view::npos && colon + 1 < v.size(), "the test seam is <phase>:<n>" ) )
        {
            return t;
        }
        std::uint64_t n = 0;
        for( const char c : v.substr( colon + 1 ) )
        {
            if( c < '0' || c > '9' || n > ( 1ull << 40 ) )
            {
                return t;
            }
            n = n * 10 + std::uint64_t( c - '0' );
        }
        const std::string_view phase = v.substr( 0, colon );
        t.at    = phase == "crawl" ? TripAt::Crawl : phase == "parse" ? TripAt::Parse : phase == "request" ? TripAt::Request : TripAt::Nowhere;
        t.index = n;
        return t;
    }();
    return trip;
}

// the time gate runs on the steady clock's own ticks: no conversion on the hot path, only one at compile time
using GateClock = std::chrono::steady_clock;
inline constexpr GateClock::rep kCheckIntervalTicks = std::chrono::duration_cast<GateClock::duration>( std::chrono::nanoseconds( kCheckIntervalNs ) ).count();

// install: main() calls this once, before any thread, with the resolved limit. A zero `bytes` means "the default".
inline void install( std::uint64_t bytes, Source source )
{
    Limits& slot  = limitsSlot();
    slot.hardBytes = bytes != 0 ? bytes : defaultLimitBytes();
    slot.source    = bytes != 0 ? source : Source::Default;
}

// ── the per-ingest watch ───────────────────────────────────────────────────────────────────────────────────
// One per ingest() call: the crawl and the parse pool share it, the parse workers from several threads.
class Watch
{
public:
    Watch() noexcept
        : trip_( testTrip() )
        , hardBytes_( limits().hardBytes )
    {
        seam_ = trip_.at == TripAt::Crawl || trip_.at == TripAt::Parse;
        if( !seam_ )
        {
            baseFootprint_ = os::mem_footprint();
            nextCheckTick_.store( GateClock::now().time_since_epoch().count() + kCheckIntervalTicks, std::memory_order_relaxed );
        }
    }
    Watch( const Watch& )            = delete;
    Watch& operator=( const Watch& ) = delete;

    // the crawl: called once per directory entry with the running entry count; true = stop walking now
    [[nodiscard]] bool crawlShouldStop( std::uint64_t entryCount ) noexcept
    {
        if( stopped_.load( std::memory_order_relaxed ) )
        {
            return true;
        }
        if( seam_ )
        {
            return trip_.at == TripAt::Crawl && entryCount + 1 >= trip_.index && tripSoft( false );
        }
        if( ( entryCount & ( kCrawlStride - 1 ) ) != 0 || !claimTimeSlot() )
        {
            return false;
        }
        const std::uint64_t footprint = os::mem_footprint();
        const bool overLine = hardBytes_ != 0 && footprint != 0
                           && ( footprint >= softLine() || ( footprint > baseFootprint_ && footprint - baseFootprint_ >= hardBytes_ / 8 ) );
        return ( overLine && tripSoft( false ) ) || ( underPressure( footprint ) && tripSoft( true ) );
    }

    // the parse: a worker asks BEFORE claiming its next file (a relaxed load, nothing else)
    [[nodiscard]] bool isStopped() const noexcept { return stopped_.load( std::memory_order_relaxed ); }

    // the parse: a worker reports each finished file; may trip the stop for every worker
    void parseFileDone() noexcept
    {
        if( stopped_.load( std::memory_order_relaxed ) )
        {
            return;
        }
        if( seam_ )
        {
            if( trip_.at == TripAt::Parse && parsedSeen_.fetch_add( 1, std::memory_order_relaxed ) + 1 >= trip_.index )
            {
                (void)tripSoft( false );
            }
            return;
        }
        if( !claimTimeSlot() )
        {
            return;
        }
        const std::uint64_t footprint = os::mem_footprint();
        if( hardBytes_ != 0 && footprint != 0 && footprint >= softLine() )
        {
            (void)tripSoft( false );
        }
        else if( underPressure( footprint ) )
        {
            (void)tripSoft( true );
        }
    }

    // ingest() calls this between the crawl and the parse: a crawl stop is already recorded, and the parse has its own
    // (higher) line, so the flag is re-armed rather than handed on — a stopped crawl's files are still parsed, guarded.
    void rearmForParse() noexcept
    {
        stopped_.store( false, std::memory_order_relaxed );
        trippedOnce_.store( false, std::memory_order_relaxed );
        byPressure_ = false;
    }

    [[nodiscard]] bool tripped() const noexcept { return stopped_.load( std::memory_order_acquire ); }
    [[nodiscard]] bool trippedByPressure() const noexcept { return byPressure_; }   // read after tripped() / the pool join
    [[nodiscard]] std::uint64_t hardBytes() const noexcept { return hardBytes_; }

private:
    [[nodiscard]] std::uint64_t softLine() const noexcept { return hardBytes_ / 2; }

    [[nodiscard]] bool underPressure( std::uint64_t footprint ) const noexcept
    {
        const std::uint64_t minimum = std::max( kPressureMinimum, hardBytes_ / 8 );
        return footprint >= minimum && os::mem_pressure() >= 3;
    }

    // true for exactly one caller per five-second slot: the one that moves the deadline forward
    [[nodiscard]] bool claimTimeSlot() noexcept
    {
        const GateClock::rep now      = GateClock::now().time_since_epoch().count();
        GateClock::rep       deadline = nextCheckTick_.load( std::memory_order_relaxed );
        return now >= deadline && nextCheckTick_.compare_exchange_strong( deadline, now + kCheckIntervalTicks, std::memory_order_relaxed );
    }

    // the first caller to trip records the cause; everyone sees stopped_ afterwards. Always returns true.
    bool tripSoft( bool byPressure ) noexcept
    {
        bool expected = false;
        if( trippedOnce_.compare_exchange_strong( expected, true, std::memory_order_acq_rel ) )
        {
            byPressure_ = byPressure;
            stopped_.store( true, std::memory_order_release );
        }
        return true;
    }

    const TestTrip&           trip_;
    const std::uint64_t       hardBytes_;
    bool                      seam_          = false;
    std::uint64_t             baseFootprint_ = 0;
    std::atomic<GateClock::rep> nextCheckTick_{ 0 };
    std::atomic<bool>         stopped_{ false };
    std::atomic<bool>         trippedOnce_{ false };
    bool                      byPressure_    = false;
    std::atomic<std::uint64_t> parsedSeen_{ 0 };
};

// ── the hard line: between phases (CLI) and before each MCP tool call ──────────────────────────────────────
// true when the footprint is at or over the hard limit. Unlike the soft lines this reads the footprint every time it
// is called — its callers run it once per phase or once per request, never per unit of work.
inline bool overHardLimit()
{
    const Limits& l = limits();
    if( l.hardBytes == 0 )
    {
        return false;
    }
    if( testTrip().at == TripAt::Request )
    {
        return false;   // the request seam answers through requestOverHardLimit only
    }
    if( testTrip().at != TripAt::Nowhere )
    {
        return false;   // a crawl/parse seam replaces the reading: the phases between answer from what was built
    }
    const std::uint64_t footprint = os::mem_footprint();
    return footprint != 0 && footprint >= l.hardBytes;
}

// the MCP pre-check: overHardLimit, plus the request seam (the Nth tool call reads as over)
inline bool requestOverHardLimit()
{
    if( testTrip().at == TripAt::Request )
    {
        static std::atomic<std::uint64_t> requestsSeen{ 0 };
        return requestsSeen.fetch_add( 1, std::memory_order_relaxed ) + 1 >= testTrip().index;
    }
    return overHardLimit();
}

// ── the backstop: a stop nobody answered for ────────────────────────────────────────────────────────────
// ingest() counts every stop it discloses; the caller that decides what the partial ingest may answer (main.cpp's
// memoryStopExit) marks every stop so far as answered for. A CLI run that ends with a stop nobody answered for — an
// ingest INSIDE a verb (a --quality-delta HEAD snapshot, --index-out, --dmm) whose verb does not read memoryStop —
// exits 5 with one line, so a partial secondary ingest can never pass as a whole one. The counters are process-wide
// and relaxed: every reader runs after the ingests it counts have returned.
struct StopCounts
{
    std::atomic<std::uint32_t> recorded{ 0 };
    std::atomic<std::uint32_t> answered{ 0 };
};
inline StopCounts& stopCounts() noexcept
{
    static StopCounts counts;
    return counts;
}
inline void recordStop() noexcept { stopCounts().recorded.fetch_add( 1, std::memory_order_relaxed ); }
inline void answerStops() noexcept { stopCounts().answered.store( stopCounts().recorded.load( std::memory_order_relaxed ), std::memory_order_relaxed ); }
[[nodiscard]] inline bool hasUnansweredStop() noexcept
{
    return stopCounts().recorded.load( std::memory_order_relaxed ) > stopCounts().answered.load( std::memory_order_relaxed );
}

// ── the sentences ──────────────────────────────────────────────────────────────────────────────────────────
// indexed by MemoryStop::Phase; None never reaches a sentence that names a phase
inline constexpr std::string_view kPhaseNames[] = { "ingest", "crawl", "parse" };
static_assert( std::size( kPhaseNames ) == std::size_t( MemoryStop::Phase::Parse ) + 1, "one name per MemoryStop::Phase" );
inline std::string_view phaseName( MemoryStop::Phase phase ) noexcept
{
    return kPhaseNames[ std::size_t( phase ) ];
}

// every message ends with the override
inline constexpr std::string_view kOverride = "raise it with --max-memory=<N>[K|M|G] or RIPWIRE_MAX_MEMORY, or pass a smaller root";

// the hard stop's one line: nothing was built that could answer
inline std::string hardStopLine( std::string_view where )
{
    const Limits& l = limits();
    return "memory limit reached during the " + std::string( where ) + " (limit " + limitSpelling( l.hardBytes )
         + ( l.source == Source::Flag ? ", from --max-memory" : l.source == Source::Env ? ", from RIPWIRE_MAX_MEMORY" : ", 65% of this machine's memory" )
         + "); stopped cleanly without an answer — " + std::string( kOverride );
}

// the soft stop's one line (stderr on the CLI, the MCP envelope's _memory_stop)
inline std::string softStopLine( const IngestResult& ing )
{
    const MemoryStop& m = ing.memoryStop;
    std::string line = "the memory guard stopped the " + std::string( phaseName( m.phase ) )
                     + ( m.byPressure ? " under critical system memory pressure" : " at its line under the " + limitSpelling( m.limitBytes ) + " limit" )
                     + ": this answer covers " + std::to_string( ing.files.size() ) + " files";
    if( m.phase == MemoryStop::Phase::Parse )
    {
        line += ", " + std::to_string( m.parsedFiles ) + " of them parsed";
    }
    return line + ", a floor of the tree — " + std::string( kOverride );
}

}   // namespace rw::memguard
