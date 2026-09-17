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
//  stack is retried with half, down to 8 MiB, and its work is told the stack it got. When NONE starts, the work
//  runs once on the calling thread and is told kCallerStackBytesFloor instead — the caller's stack is not this
//  header's to measure, so the work plans for the smallest one this tree runs on.
//
#pragma once

#include "Diagnostics.h"   // DEGRADED_PATH_ALERT

#include <pthread.h>

#include <algorithm>
#include <cstddef>
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

// work( stackBytes ) on `threadCount` threads; returns after every one has been joined. Each thread asks for `stackBytes`
// and, when the system refuses that much (a strict overcommit policy, an address-space ulimit), for half as much, down to
// kStackThreadBytesFloor — so `work` is told the stack ITS thread got. `work` must not throw: an exception escaping a
// thread's entry is std::terminate.
inline constexpr std::size_t kStackThreadBytesFloor = 8 * 1024 * 1024;

template<typename Work>
void runOnStackThreads( std::size_t threadCount, std::size_t stackBytes, Work& work ) noexcept
{
    struct Launch
    {
        Work*       work;
        std::size_t stackBytes;
        pthread_t   thread;
    };
    const auto entry = []( void* arg ) -> void*
    {
        const Launch& launch = *static_cast<Launch*>( arg );
        ( *launch.work )( launch.stackBytes );
        return nullptr;
    };
    std::vector<Launch> launches( threadCount, Launch{ &work, 0, pthread_t{} } );
    std::size_t         startedCount = 0;
    for( std::size_t t = 0; t < threadCount; ++t )
    {
        Launch& launch    = launches[ startedCount ];
        bool    isStarted = false;
        for( std::size_t tryBytes = stackBytes; !isStarted && tryBytes > 0 && tryBytes >= std::min( stackBytes, kStackThreadBytesFloor ); tryBytes /= 2 )
        {
            launch.stackBytes = tryBytes;                                // written BEFORE the thread can read it
            const StackThreadAttr attr( tryBytes );
            isStarted = attr.isSized && pthread_create( &launch.thread, &attr.attr, entry, &launch ) == 0;
        }
        startedCount += isStarted ? 1 : 0;
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
}

}   // namespace rw
