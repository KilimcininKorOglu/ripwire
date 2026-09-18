// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  diagnostics.cpp
//
//  The one out-of-line translation unit behind Diagnostics.h: the ConsoleLog report handlers (assert-family / panic /
//  thread-ownership violation / VALIDATE trace / degraded path) and the thread-id counter. Everything else in the
//  diagnostics system is macros, so every target and every standalone test harness in test/ links exactly this file
//  to satisfy ASSUME, EXPECTS, ENSURES, DASSERT, UNREACHABLE, VALIDATE, ASSUME_SAME_THREAD*, PANIC and
//  DISCLOSE.
//
#include "Diagnostics.h"
#include <atomic>
#include <cstdlib>
#include <iostream>

namespace Diagnostics
{

// The build-flavour link check behind ThreadOwner (Diagnostics.h §2): only a debug diagnostics.cpp defines it, so a
// debug TU that constructs a ThreadOwner cannot link against a release one.
#if !defined( NDEBUG )
void debugFlavourLinkCheck() noexcept {}
#endif

namespace
{
// Two columns, one row per CheckKind in enum order: the banner, then who to suspect. The blame line is the reason
// EXPECTS and ENSURES exist as words — it is the first thing a reader of the report needs.
constexpr const char* kKindBanner[] = {
    "ASSUME FAILED",
    "EXPECTS FAILED (precondition)",
    "ENSURES FAILED (postcondition)",
    "DASSERT FAILED",
    "UNREACHABLE REACHED",
};
constexpr const char* kKindBlame[] = {
    "an invariant this function relies on is false here",
    "the CALLER broke this function's contract — look up the stack",
    "THIS function broke its own contract — look inside it",
    "a debug-only check is false (no release promise was made)",
    "control arrived where this function says it cannot",
};
} // namespace

[[gnu::cold, gnu::noinline]]
void ConsoleLog::handleAssert( CheckKind kind, const char* expr, const char* file, int line, const char* function,
                               const char* description ) noexcept
{
    const std::size_t row = static_cast<std::size_t>( kind );
    std::cerr << "\n======================================\n"
              << "!!! " << kKindBanner[ row ] << " !!!\n"
              << "======================================\n"
              << "  Expr:     " << expr << "\n"
              << "  Blame:    " << kKindBlame[ row ] << "\n"
              << "  Location: " << file << ":" << line << "\n"
              << "  Function: " << function << "\n";
    if( description && description[ 0 ] != '\0' )
    {
        std::cerr << "  Notes:    " << description << "\n";
    }
    std::cerr << "======================================\n" << std::flush;
    __builtin_trap();
}

[[gnu::cold, gnu::noinline, noreturn]]
void ConsoleLog::handlePanic( const char* file, int line, const char* function, const char* description ) noexcept
{
    std::cerr << "\n======================================\n"
              << "!!! CRITICAL SYSTEM PANIC !!!\n"
              << "======================================\n"
              << "  Location: " << file << ":" << line << "\n"
              << "  Function: " << function << "\n"
              << "  Reason:   " << description << "\n"
              << "======================================\n" << std::flush;
    std::abort();
}

[[gnu::cold, gnu::noinline]]
void ConsoleLog::handleThreadViolation( std::uint64_t expected, std::uint64_t got, const char* file, int line, const char* function,
                                        const char* description ) noexcept
{
    std::cerr << "\n======================================\n"
              << "!!! THREAD-OWNERSHIP VIOLATION !!!\n"
              << "======================================\n"
              << "  This site or object is single-thread owned but was reached from another thread.\n"
              << "  Owner thread: " << expected << "   Offending thread: " << got << "\n"
              << "  Location: " << file << ":" << line << "\n"
              << "  Function: " << function << "\n";
    if( description && description[ 0 ] != '\0' )
    {
        std::cerr << "  Notes:    " << description << "\n";
    }
    std::cerr << "======================================\n" << std::flush;
    __builtin_trap();
}

[[gnu::cold, gnu::noinline]]
void ConsoleLog::handleValidateFailed( const char* expr, const char* file, int line, const char* function, const char* description ) noexcept
{
    // One line, no trap: a false VALIDATE is input being refused, which is the program working.
    std::cerr << "[validate] " << expr << " is false" << ( description && description[ 0 ] != '\0' ? " — " : "" )
              << ( description ? description : "" ) << "  (" << file << ":" << line << ", " << function << " — logged once per site)\n"
              << std::flush;
}

[[gnu::cold, gnu::noinline]]
void ConsoleLog::handleDegraded( const char* file, int line, const char* function, const char* description ) noexcept
{
    // DISCLOSE's debug trace. One-line notice, no trap — the caller clamps/falls back and continues. The
    // "[math degraded]" prefix and every message are kept byte-identical: 11 gates grep for the prefix
    // (test/*.sh on 3bf884e2) and test/sidecarsymlinkcheck.sh pins message text. Retiring the prefix is its own change.
    std::cerr << "[math degraded] " << description << "  (" << file << ":" << line << ", " << function << " — logged once per site)\n"
              << std::flush;
}

// Unique, stable, non-zero per-thread id. thread_local counter avoids pulling <thread> into the widely-included
// Diagnostics.h; first thread to ask gets 1, next 2, etc. Non-zero so 0 stays a valid "unclaimed" sentinel for the
// per-site latch and ThreadOwner.
std::uint64_t currentThreadId() noexcept
{
    static std::atomic<std::uint64_t> counter{ 0 };
    thread_local const std::uint64_t  id = ++counter;
    return id;
}

} // namespace Diagnostics
