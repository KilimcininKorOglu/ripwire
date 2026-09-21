#pragma once

// statclock.h — a file timestamp as one signed 64-bit nanosecond count, without overflowing on the way.
//
// `seconds * 1'000'000'000 + nanoseconds` in `long long` holds only until 2262-04-11. APFS clamps a timestamp
// there, but ext4 (256-byte inodes), XFS bigtime and tmpfs store dates centuries later, and a tar archive
// restores whatever it carries — so the multiplication is signed overflow on a file anyone can hand over:
// undefined behaviour in a release build, and an abort in a build that traps integer overflow. Saturating is
// the exact answer inside the representable range and a pinned extreme outside it, and it costs one flag test.
//
// What saturation gives up: two timestamps beyond the range read as the same value. A caller that uses the value
// as a change signal must therefore pair it with a second one (size, a change time, a content hash) — the ones
// here already do.

#include <climits>
#include "platform.h"   // infra::platform::{mul,add}Overflow — the checked arithmetic this file is built on
#include <ctime>

namespace rw
{

[[nodiscard]] inline constexpr long long saturatingNanoseconds( long long seconds, long long nanoseconds ) noexcept
{
    long long scaled = 0;
    if( infra::platform::mulOverflow( seconds, 1000000000LL, &scaled ) )
    {
        return seconds < 0 ? LLONG_MIN : LLONG_MAX;
    }
    long long total = 0;
    if( infra::platform::addOverflow( scaled, nanoseconds, &total ) )
    {
        return nanoseconds < 0 ? LLONG_MIN : LLONG_MAX;
    }
    return total;
}

[[nodiscard]] inline constexpr long long saturatingNanoseconds( const timespec& ts ) noexcept
{
    return saturatingNanoseconds( static_cast<long long>( ts.tv_sec ), static_cast<long long>( ts.tv_nsec ) );
}

}   // namespace rw
