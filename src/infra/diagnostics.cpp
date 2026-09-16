// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 David Brewster

//
//  diagnostics.cpp
//
//  The one out-of-line translation unit behind Diagnostics.h: the four ConsoleLog
//  report handlers (assert / panic / thread-affinity violation / degraded path) and
//  the thread-id counter. Everything else in the diagnostics system is macros, so
//  every target and every standalone test harness in test/ links exactly this file
//  to satisfy VERIFY, PANIC and DEGRADED_PATH_ALERT.
//
#include "Diagnostics.h"
#include "emit.h"

#include <atomic>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <format>
#include <utility>

namespace Diagnostics {

namespace {

// ── ONE NOTICE, ONE WRITE ────────────────────────────────────────────────────────────────────────────────────────
// Every reporter below formats its whole notice first and hands it to stderr in ONE stdio call. They used to build it
// from a chain of `std::cerr <<` insertions, and with stdio sync on (the default) each insertion is its own fwrite on
// an unbuffered stderr, so its own write(2). Any other thread's single-write line could then land between two
// insertions and split the notice across lines. Measured on a gate whose fixture refuses two files at once: the
// degraded notice torn in 32-73% of runs depending on load, and 0 tears in 3,800 runs once it was written whole.
//
// WHY emitRaw OVER A RAW write( 2, … ). One stdio call holds the stream's lock for the whole call, so no other stdio
// writer in the process — which is every other stderr writer here — can interleave, at any length. Underneath, the
// unbuffered stderr hands the whole notice to the kernel as one write(2): measured on macOS up to the full buffer
// (4,093 bytes in one write), and glibc's unbuffered path passes the whole block to a single write as well. A libc
// that split a long write would still do it with the lock held. A raw write(2) would add nothing for this process
// and would step OUTSIDE that lock, so a line another thread is writing through stdio could be split by the notice
// instead. Across PROCESSES sharing the descriptor, one write to a pipe is atomic only up to PIPE_BUF (512 bytes on
// macOS), and neither spelling changes that.
//
// NO ALLOCATION. A reporter may be running because memory ran out, so the notice is formatted into a fixed stack
// buffer through rw::formatTo, never into a std::string (which std::print and rw::emitTo both build). The buffer is
// a cap: a notice longer than it is cut, and the cut is DISCLOSED in the notice itself (markTruncated, below).
inline constexpr std::size_t kNoticeByteCap = 4096;   // a longer notice is cut and says so: " ... [notice truncated: N bytes]"

// std::format on a null const char* is undefined, and a reporter must survive the malformed call it is reporting.
const char* orEmpty( const char* text ) noexcept
{
    return text != nullptr ? text : "";
}

// The optional "Notes:" row of the assert and thread-violation banners: three pieces, all empty without a description.
struct NotesRow
{
    const char* label;
    const char* text;
    const char* eol;
};

NotesRow notesRowOf( const char* description ) noexcept
{
    if( description != nullptr && description[ 0 ] != '\0' )
    {
        return NotesRow{ "  Notes:    ", description, "\n" };
    }
    return NotesRow{ "", "", "" };
}

// A notice past kNoticeByteCap keeps its opening and ends in a marker that names the full length, still on a line of
// its own. The cut backs off to a UTF-8 lead byte, so the kept text never ends inside a multi-byte sequence.
void markTruncated( char* notice, std::size_t capacity, std::size_t fullBytes ) noexcept
{
    char              marker[ 64 ];
    const std::size_t markerBytes = rw::formatTo( marker, sizeof( marker ), " ... [notice truncated: {} bytes]\n", fullBytes );
    std::size_t       keptBytes   = capacity - 1 - markerBytes;
    while( keptBytes > 0 && ( static_cast<unsigned char>( notice[ keptBytes ] ) & 0xC0 ) == 0x80 )
    {
        --keptBytes;
    }
    std::memcpy( notice + keptBytes, marker, markerBytes + 1 );
}

template<class... A>
[[gnu::cold]] void writeNotice( std::format_string<A...> format, A&&... args ) noexcept
{
    char              notice[ kNoticeByteCap ];
    const std::size_t fullBytes = rw::formatTo( notice, sizeof( notice ), format, std::forward<A>( args )... );
    if( fullBytes >= sizeof( notice ) )
    {
        markTruncated( notice, sizeof( notice ), fullBytes );
    }
    rw::emitRaw( stderr, notice );
    std::fflush( stderr );
}

} // namespace

[[gnu::cold, gnu::noinline]]
void ConsoleLog::handleAssert( const char* expr, const char* file, int line,
                                const char* function, const char* description ) noexcept
{
    const NotesRow notes = notesRowOf( description );
    writeNotice( "\n======================================\n"
                 "!!! DEBUG ASSERT FAILED !!!\n"
                 "======================================\n"
                 "  Expr:     {}\n"
                 "  Location: {}:{}\n"
                 "  Function: {}\n"
                 "{}{}{}"
                 "======================================\n",
                 orEmpty( expr ), orEmpty( file ), line, orEmpty( function ), notes.label, notes.text, notes.eol );
    __builtin_trap();
}

[[gnu::cold, gnu::noinline, noreturn]]
void ConsoleLog::handlePanic( const char* file, int line,
                               const char* function, const char* description ) noexcept
{
    writeNotice( "\n======================================\n"
                 "!!! CRITICAL SYSTEM PANIC !!!\n"
                 "======================================\n"
                 "  Location: {}:{}\n"
                 "  Function: {}\n"
                 "  Reason:   {}\n"
                 "======================================\n",
                 orEmpty( file ), line, orEmpty( function ), orEmpty( description ) );
    std::abort();
}

[[gnu::cold, gnu::noinline]]
void ConsoleLog::handleThreadViolation( uint64_t expected, uint64_t got,
                                         const char* file, int line,
                                         const char* function, const char* description ) noexcept
{
    const NotesRow notes = notesRowOf( description );
    writeNotice( "\n======================================\n"
                 "!!! THREAD-AFFINITY VIOLATION !!!\n"
                 "======================================\n"
                 "  This call site is single-thread only but was reached from a 2nd thread.\n"
                 "  Owner thread: {}   Offending thread: {}\n"
                 "  Location: {}:{}\n"
                 "  Function: {}\n"
                 "{}{}{}"
                 "======================================\n",
                 expected, got, orEmpty( file ), line, orEmpty( function ), notes.label, notes.text, notes.eol );
    __builtin_trap();
}

[[gnu::cold, gnu::noinline]]
void ConsoleLog::handleDegraded( const char* file, int line,
                                  const char* function, const char* description ) noexcept
{
    // One-line notice, no trap — the caller clamps/falls back and continues.
    writeNotice( "[math degraded] {}  ({}:{}, {} — logged once per site)\n", orEmpty( description ), orEmpty( file ), line, orEmpty( function ) );
}

// Unique, stable, non-zero per-thread id. thread_local counter avoids pulling
// <thread> into the widely-included Diagnostics.h; first thread to ask gets 1,
// next 2, etc. Non-zero so 0 stays a valid "unclaimed" sentinel for the latch.
uint64_t currentThreadId() noexcept
{
    static std::atomic<uint64_t> counter{ 0 };
    thread_local const uint64_t id = ++counter;
    return id;
}

} // namespace Diagnostics
