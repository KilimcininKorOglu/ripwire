// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster
//
//  stackthreads.h
//
//  Run one piece of work on N threads whose STACK SIZE is chosen, not inherited. std::thread cannot ask for a
//  stack, and the default differs by a factor of sixteen across the platforms this tree ships on (512 KiB on a
//  macOS secondary thread, 8 MiB under glibc), so work whose depth is data-dependent — libstdc++'s regex matcher
//  recurses once per state it visits — gets a stack it can state and bound instead of whatever the platform gave.
//
//  POSIX, inline: pthread_attr_setstacksize + pthread_create + pthread_join, nothing wrapped. A stack of S bytes
//  is an address-space reservation; pages are committed only as deep as the work actually recurses, and returned
//  when the thread exits.
//
//  The work pulls its own share from shared state (an atomic cursor), so a thread that fails to start costs
//  parallelism, not coverage: the threads that did start finish the work. A thread the system refuses the full
//  stack is retried with half, down to 8 MiB. ONE size is then SETTLED — the smallest any started thread got — and
//  every thread is told that size, and no thread runs any work until it is settled (the threads wait on a gate
//  the creator holds). So a piece of work never sees a size that depends on which thread picked it up: work that
//  derives a limit from its stack derives the same limit on every thread (determinism, CLAUDE.md non-negotiable
//  #2). When NONE starts, the work runs once on the calling thread and is told kCallerStackBytesFloor — the
//  caller's stack is not this header's to measure, so the work plans for the smallest one this tree runs on. The
//  settled size is RETURNED, so a caller whose answer depends on it can disclose it.
//
#pragma once

#include "Diagnostics.h"   // DEGRADED_PATH_ALERT

#include <pthread.h>

#include <algorithm>
#include <cstddef>
#include <mutex>
#include <vector>

namespace rw
{

inline constexpr std::size_t kCallerStackBytesFloor = 512 * 1024;   // a macOS secondary thread: the smallest stack a caller here runs on

// The attribute object, released on every path.
class StackThreadAttr
{
public:
    explicit StackThreadAttr( std::size_t stackBytes ) noexcept
        : isInitialized( pthread_attr_init( &attr ) == 0 )
        , isSized( isInitialized && pthread_attr_setstacksize( &attr, stackBytes ) == 0 )
    {
    }
    ~StackThreadAttr() { if( isInitialized ) { pthread_attr_destroy( &attr ); } }
    StackThreadAttr( const StackThreadAttr& )            = delete;
    StackThreadAttr& operator=( const StackThreadAttr& ) = delete;

    pthread_attr_t attr {};
    const bool     isInitialized;
    const bool     isSized;
};

inline constexpr std::size_t kStackThreadBytesFloor = 8 * 1024 * 1024;   // the smallest stack a refused thread is retried with

// work( settledBytes ) on `threadCount` threads; returns the settled stack size after every thread has been joined. Each
// thread asks for `stackBytes` and, when the system refuses that much (a strict overcommit policy, an address-space
// ulimit), for half as much, down to kStackThreadBytesFloor. `work` must not throw: an exception escaping a thread's
// entry is std::terminate. `isRefused( threadIndex, tryBytes, askedBytes )` lets a caller's test hook refuse a size the
// system would have granted, so the degrade is reachable on demand; the default refuses nothing.
inline bool isStackNeverRefused( std::size_t, std::size_t, std::size_t ) noexcept { return false; }

template<typename Work, typename RefusePolicy = decltype( &isStackNeverRefused )>
std::size_t runOnStackThreads( std::size_t threadCount, std::size_t stackBytes, Work& work, RefusePolicy isRefused = &isStackNeverRefused ) noexcept
{
    struct Shared
    {
        explicit Shared( Work* w ) noexcept : work( w ) {}
        Work*       work;
        std::size_t settledBytes = 0;   // written under `gate` before it opens; read under it by every thread
        std::mutex  gate;
    };
    struct Launch
    {
        Shared*   shared;
        pthread_t thread;
    };
    const auto entry = []( void* arg ) -> void*
    {
        Shared&     shared       = *static_cast<Launch*>( arg )->shared;
        std::size_t settledBytes = 0;
        {
            const std::lock_guard<std::mutex> wait( shared.gate );   // blocks until the creator has settled one size
            settledBytes = shared.settledBytes;
        }
        ( *shared.work )( settledBytes );
        return nullptr;
    };
    Shared              shared( &work );
    std::vector<Launch> launches( threadCount, Launch{ &shared, pthread_t{} } );
    std::size_t         startedCount = 0;
    {
        const std::lock_guard<std::mutex> hold( shared.gate );
        std::size_t                       smallestBytes = stackBytes;
        for( std::size_t t = 0; t < threadCount; ++t )
        {
            Launch& launch    = launches[ startedCount ];
            bool    isStarted = false;
            for( std::size_t tryBytes = stackBytes; !isStarted && tryBytes > 0 && tryBytes >= std::min( stackBytes, kStackThreadBytesFloor ); tryBytes /= 2 )
            {
                const StackThreadAttr attr( tryBytes );
                isStarted     = attr.isSized && !isRefused( t, tryBytes, stackBytes ) && pthread_create( &launch.thread, &attr.attr, entry, &launch ) == 0;
                smallestBytes = isStarted ? std::min( smallestBytes, tryBytes ) : smallestBytes;
            }
            startedCount += isStarted ? 1 : 0;
        }
        shared.settledBytes = startedCount == 0 ? kCallerStackBytesFloor : smallestBytes;
    }
    for( std::size_t t = 0; t < startedCount; ++t )
    {
        pthread_join( launches[ t ].thread, nullptr );
    }
    if( startedCount == 0 )
    {
        DEGRADED_PATH_ALERT( "stackthreads: no thread could be created with any stack of at least 8 MiB — the work runs on the caller's thread" );
        work( kCallerStackBytesFloor );
    }
    return shared.settledBytes;
}

}   // namespace rw
