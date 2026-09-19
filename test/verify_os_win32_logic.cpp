// verify_os_win32_logic.cpp — the Windows port's pure logic (src/infra/os_win32_logic.h), tested on the platforms its
// reviewers have. Every function in that header is exercised here against an ORACLE written independently of it: a
// reference UTF-8 encoder, a reference MSVCRT command-line parser, the traditional Unix wait-status and S_IF* encodings
// (and, on a host that has them, the host's own W* and S_IS* macros), and linear scans for the binary-searched table. A case that only restated the implementation would pass
// while proving nothing, so each oracle is a different algorithm from the code it checks.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include "infra/os_win32_logic.h"

// A POSIX host's own W* and S_IS* macros are a second oracle for the encodings. This target also builds on Windows,
// whose UCRT has neither header shape, so the host arm is feature-detected; the traditional-encoding oracle below
// runs everywhere. (This file is under test/, outside osswitchcheck's scope, and tests a header, not a platform.)
#if __has_include( <sys/wait.h> )
#include <sys/stat.h>
#include <sys/wait.h>
#define OSWIN_TEST_HOST_WAIT_MACROS 1
#else
#define OSWIN_TEST_HOST_WAIT_MACROS 0
#endif

#include <cerrno>
#include <cstdint>
#include <cstring>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

using namespace rw::oswin;

namespace
{

// The traditional Unix encodings, written from the System V / 4.4BSD definitions every POSIX libc still uses:
// type bits in the high octal digits of st_mode, exit status in bits 8..15, terminating signal in bits 0..6.
namespace traditional
{
inline constexpr unsigned kIfmt = 0170000, kIfifo = 0010000, kIfchr = 0020000, kIfdir = 0040000, kIfreg = 0100000, kIflnk = 0120000;
constexpr bool isType( unsigned mode, unsigned type ) noexcept { return ( mode & kIfmt ) == type; }
constexpr bool exited( int status ) noexcept { return ( status & 0x7f ) == 0; }
constexpr int  exitStatus( int status ) noexcept { return ( status >> 8 ) & 0xff; }
constexpr bool signaled( int status ) noexcept { return ( status & 0x7f ) != 0 && ( status & 0x7f ) != 0x7f; }
constexpr int  termSig( int status ) noexcept { return status & 0x7f; }
}   // namespace traditional

// ── oracles ─────────────────────────────────────────────────────────────────────────────────────────────────
std::string referenceUtf8( char32_t scalar )
{
    std::string out;
    if( scalar < 0x80 ) { out.push_back( char( scalar ) ); }
    else if( scalar < 0x800 ) { out.push_back( char( 0xC0 | ( scalar >> 6 ) ) ); out.push_back( char( 0x80 | ( scalar & 0x3F ) ) ); }
    else if( scalar < 0x10000 )
    {
        out.push_back( char( 0xE0 | ( scalar >> 12 ) ) ); out.push_back( char( 0x80 | ( ( scalar >> 6 ) & 0x3F ) ) ); out.push_back( char( 0x80 | ( scalar & 0x3F ) ) );
    }
    else
    {
        out.push_back( char( 0xF0 | ( scalar >> 18 ) ) ); out.push_back( char( 0x80 | ( ( scalar >> 12 ) & 0x3F ) ) );
        out.push_back( char( 0x80 | ( ( scalar >> 6 ) & 0x3F ) ) ); out.push_back( char( 0x80 | ( scalar & 0x3F ) ) );
    }
    return out;
}

std::u16string toUtf16( std::string_view utf8, bool& ok )
{
    const std::ptrdiff_t units = utf16LengthOf( utf8 );
    ok = units >= 0;
    if( !ok ) { return {}; }
    std::u16string out( std::size_t( units ), u'\0' );
    encodeUtf16( utf8, out.data() );
    return out;
}

std::string toUtf8( std::u16string_view utf16, bool& ok )
{
    const std::ptrdiff_t bytes = utf8LengthOf( utf16 );
    ok = bytes >= 0;
    if( !ok ) { return {}; }
    std::string out( std::size_t( bytes ), '\0' );
    encodeUtf8( utf16, out.data() );
    return out;
}

// The MSVCRT (2008 and later) / CommandLineToArgvW argument rules, written the way Microsoft documents them — a
// state machine over characters, not the backslash-count arithmetic appendQuotedArg uses. Every argument here is
// parsed with the non-first-argument rules (the program name is quoted by the same function, and contains no '"').
std::vector<std::string> parseCommandLine( std::string_view line )
{
    std::vector<std::string> args;
    std::size_t i = 0;
    while( true )
    {
        while( i < line.size() && ( line[ i ] == ' ' || line[ i ] == '\t' ) ) { ++i; }
        if( i >= line.size() ) { break; }
        std::string arg;
        bool inQuotes = false;
        while( i < line.size() )
        {
            const char c = line[ i ];
            if( ( c == ' ' || c == '\t' ) && !inQuotes ) { break; }
            if( c == '\\' )
            {
                std::size_t run = 0;
                while( i < line.size() && line[ i ] == '\\' ) { ++run; ++i; }
                if( i < line.size() && line[ i ] == '"' )
                {
                    arg.append( run / 2, '\\' );
                    if( run % 2 == 1 ) { arg.push_back( '"' ); ++i; }
                }
                else
                {
                    arg.append( run, '\\' );
                }
                continue;
            }
            if( c == '"' )
            {
                if( inQuotes && i + 1 < line.size() && line[ i + 1 ] == '"' ) { arg.push_back( '"' ); i += 2; continue; }
                inQuotes = !inQuotes;
                ++i;
                continue;
            }
            arg.push_back( c );
            ++i;
        }
        args.push_back( std::move( arg ) );
    }
    return args;
}

std::string normalized( std::string text )
{
    normalizePathArgInPlace( text.data() );
    return text;
}

std::string fromNative( std::u16string_view native, std::size_t capacity, int& error, std::ptrdiff_t& written )
{
    std::vector<char> out( capacity + 1, '\x7f' );
    error   = 0;
    written = programPathFromNative( native, out.data(), capacity, &error );
    return written < 0 ? std::string() : std::string( out.data() );
}

}   // namespace

// ── 1. errno table ──────────────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "win32 errno: the binary search agrees with a linear scan for every code 0..12000 and a few far ones" )
{
    const auto linear = []( std::uint32_t code )
    {
        for( const ErrnoRow& row : kWin32ErrnoTable ) { if( row.code == code ) { return row.errnoValue; } }
        return EIO;
    };
    for( std::uint32_t code = 0; code <= 12000; ++code )
    {
        REQUIRE( errnoFromWin32( code ) == linear( code ) );
    }
    for( const std::uint32_t code : { 0x7FFFFFFFu, 0x80000000u, 0xC0000005u, 0xFFFFFFFFu } )
    {
        CHECK( errnoFromWin32( code ) == EIO );
    }
    CHECK( isWin32ErrnoTableSorted() );
    CHECK( win32TableIsComplete() );
}

TEST_CASE( "win32 errno: the rows call sites depend on" )
{
    CHECK( errnoFromWin32( 2 ) == ENOENT );           // ERROR_FILE_NOT_FOUND
    CHECK( errnoFromWin32( 3 ) == ENOENT );           // ERROR_PATH_NOT_FOUND
    CHECK( errnoFromWin32( 5 ) == EACCES );           // ERROR_ACCESS_DENIED — deliberately not libuv's EPERM
    CHECK( errnoFromWin32( 32 ) == EBUSY );           // ERROR_SHARING_VIOLATION
    CHECK( errnoFromWin32( 33 ) == EWOULDBLOCK );     // ERROR_LOCK_VIOLATION — flock( LOCK_NB )'s retry predicate
    CHECK( errnoFromWin32( 80 ) == EEXIST );          // ERROR_FILE_EXISTS
    CHECK( errnoFromWin32( 183 ) == EEXIST );         // ERROR_ALREADY_EXISTS
    CHECK( errnoFromWin32( 267 ) == ENOTDIR );        // ERROR_DIRECTORY
    CHECK( errnoFromWin32( 681 ) == ELOOP );          // ERROR_STOPPED_ON_SYMLINK
    CHECK( errnoFromWin32( 1921 ) == ELOOP );         // ERROR_CANT_RESOLVE_FILENAME
    CHECK( errnoFromWin32( 1113 ) == EILSEQ );        // ERROR_NO_UNICODE_TRANSLATION
    CHECK( errnoFromWin32( 109 ) == EPIPE );          // ERROR_BROKEN_PIPE
    CHECK( errnoFromWin32( 10004 ) == EINTR );        // WSAEINTR — accept()'s retry predicate
    CHECK( errnoFromWin32( 10048 ) == EADDRINUSE );   // WSAEADDRINUSE — the --listen bind failure text
    CHECK( errnoFromWin32( 10054 ) == ECONNRESET );
    CHECK( errnoFromWin32( 10060 ) == ETIMEDOUT );    // WSAETIMEDOUT — an SO_RCVTIMEO expiry
}

// ── 2. UTF-8 / UTF-16 ───────────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "utf: every scalar value round-trips UTF-8 -> UTF-16 -> UTF-8 byte-exactly" )
{
    std::size_t checked = 0;
    for( char32_t scalar = 0; scalar <= 0x10FFFF; ++scalar )
    {
        if( scalar >= 0xD800 && scalar <= 0xDFFF ) { continue; }
        const std::string utf8 = referenceUtf8( scalar );
        bool ok = false;
        const std::u16string utf16 = toUtf16( utf8, ok );
        REQUIRE( ok );
        REQUIRE( utf16.size() == ( scalar >= 0x10000 ? 2u : 1u ) );
        const std::string back = toUtf8( utf16, ok );
        REQUIRE( ok );
        REQUIRE( back == utf8 );
        ++checked;
    }
    CHECK( checked == 0x110000 - 0x800 );
}

TEST_CASE( "utf: malformed UTF-8 is refused, never replaced" )
{
    const std::vector<std::string> bad = {
        "\xC0\xAF",             // overlong '/'
        "\xC1\xBF",             // overlong
        "\xE0\x80\xAF",         // overlong '/' — the form libuv's WTF-8 decoder accepts
        "\xF0\x80\x80\xAF",     // overlong '/'
        "\xED\xA0\x80",         // U+D800, a surrogate
        "\xED\xBF\xBF",         // U+DFFF
        "\xF4\x90\x80\x80",     // U+110000
        "\xF5\x80\x80\x80",     // lead byte past F4
        "\x80",                 // stray continuation
        "\xC3",                 // truncated
        "\xE2\x82",             // truncated
        "ok\xFF",               // invalid byte after valid text
        "\xE2\x28\xA1",         // bad continuation
    };
    for( const std::string& text : bad )
    {
        CAPTURE( text );
        CHECK( utf16LengthOf( text ) == -1 );
    }
    CHECK( utf16LengthOf( "" ) == 0 );
    CHECK( utf16LengthOf( "caf\xC3\xA9" ) == 4 );
}

TEST_CASE( "utf: a lone UTF-16 surrogate is refused" )
{
    const char16_t high[] = { u'a', char16_t( 0xD83D ) };
    const char16_t low[]  = { char16_t( 0xDE00 ), u'a' };
    const char16_t swap[] = { char16_t( 0xDE00 ), char16_t( 0xD83D ) };
    const char16_t pair[] = { char16_t( 0xD83D ), char16_t( 0xDE00 ) };
    CHECK( utf8LengthOf( std::u16string_view( high, 2 ) ) == -1 );
    CHECK( utf8LengthOf( std::u16string_view( low, 2 ) ) == -1 );
    CHECK( utf8LengthOf( std::u16string_view( swap, 2 ) ) == -1 );
    CHECK( utf8LengthOf( std::u16string_view( pair, 2 ) ) == 4 );   // U+1F600
}

// ── WidePath ────────────────────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "WidePath: separators, the Git Bash drive spelling, and nothing else rewritten" )
{
    CHECK( std::u16string_view( WidePath( "C:/repo/src/a.cpp" ).c_str() ) == u"C:\\repo\\src\\a.cpp" );
    CHECK( std::u16string_view( WidePath( "/c/repo" ).c_str() ) == u"C:\\repo" );
    CHECK( std::u16string_view( WidePath( "/d" ).c_str() ) == u"D:\\" );
    CHECK( std::u16string_view( WidePath( "/c/" ).c_str() ) == u"C:\\" );
    CHECK( std::u16string_view( WidePath( "/cd/x" ).c_str() ) == u"\\cd\\x" );         // two letters: not a drive
    CHECK( std::u16string_view( WidePath( "rel/c/x" ).c_str() ) == u"rel\\c\\x" );     // not at the start: not a drive
    CHECK( std::u16string_view( WidePath( "//server/share/x" ).c_str() ) == u"\\\\server\\share\\x" );
    CHECK( std::u16string_view( WidePath( "caf\xC3\xA9/\xF0\x9F\x98\x80" ).c_str() ) == u"caf\u00E9\\\U0001F600" );
    const WidePath empty( "" );
    CHECK( empty.ok() );
    CHECK( empty.size() == 0 );
}

TEST_CASE( "WidePath: the stack holds MAX_PATH units; one past it takes exactly one heap block" )
{
    const std::string fits( WidePath::kStackUnits - 1, 'a' );
    const std::string over( WidePath::kStackUnits, 'a' );
    const WidePath onStack( fits.c_str() );
    const WidePath onHeap( over.c_str() );
    CHECK( onStack.ok() );
    CHECK( !onStack.onHeap() );
    CHECK( onStack.size() == fits.size() );
    CHECK( onHeap.ok() );
    CHECK( onHeap.onHeap() );
    CHECK( onHeap.size() == over.size() );
    CHECK( std::u16string_view( onHeap.c_str() ) == std::u16string( over.size(), u'a' ) );
    // a 4-byte scalar is two units: 130 of them is 260 units + terminator — exactly the stack
    std::string emoji;
    for( int i = 0; i < 130; ++i ) { emoji += "\xF0\x9F\x98\x80"; }
    const WidePath pairs( emoji.c_str() );
    CHECK( pairs.ok() );
    CHECK( !pairs.onHeap() );
    CHECK( pairs.size() == 260 );
}

TEST_CASE( "WidePath: invalid input fails closed with an errno and an empty spelling" )
{
    const WidePath bad( "a\xE0\x80\xAF" "b" );
    CHECK( !bad.ok() );
    CHECK( bad.error() == EILSEQ );
    CHECK( std::u16string_view( bad.c_str() ).empty() );
    const WidePath null( nullptr );
    CHECK( !null.ok() );
    CHECK( null.error() == EINVAL );
}

// ── 3. program path spelling ────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "programPathFromNative: prefixes stripped, '/' separators, upper-case drive, UNC kept as //" )
{
    int error = 0;
    std::ptrdiff_t written = 0;
    CHECK( fromNative( u"\\\\?\\C:\\repo\\src", 64, error, written ) == "C:/repo/src" );
    CHECK( written == 11 );
    CHECK( fromNative( u"c:\\Users\\x", 64, error, written ) == "C:/Users/x" );
    CHECK( fromNative( u"\\\\?\\UNC\\server\\share\\dir", 64, error, written ) == "//server/share/dir" );
    CHECK( fromNative( u"\\\\server\\share", 64, error, written ) == "//server/share" );
    CHECK( fromNative( u"\\??\\D:\\x", 64, error, written ) == "D:/x" );
    CHECK( fromNative( u"C:\\caf\u00E9", 64, error, written ) == "C:/caf\xC3\xA9" );
}

TEST_CASE( "programPathFromNative: the buffer bound is exact and a lone surrogate is EILSEQ" )
{
    int error = 0;
    std::ptrdiff_t written = 0;
    CHECK( fromNative( u"C:\\abc", 7, error, written ) == "C:/abc" );     // 6 bytes + NUL in exactly 7
    CHECK( written == 6 );
    CHECK( fromNative( u"C:\\abcd", 7, error, written ).empty() );    // 7 bytes + NUL do not fit in 7
    CHECK( written == -1 );
    CHECK( error == ENAMETOOLONG );
    const char16_t lone[] = { u'C', u':', u'\\', char16_t( 0xDC00 ) };
    std::vector<char> out( 32 );
    error = 0;
    CHECK( programPathFromNative( std::u16string_view( lone, 4 ), out.data(), out.size(), &error ) == -1 );
    CHECK( error == EILSEQ );
}

TEST_CASE( "normalizePathArgInPlace: separators and Git Bash drives, length-preserving, at list boundaries only" )
{
    CHECK( normalized( "C:\\repo\\src" ) == "C:/repo/src" );
    CHECK( normalized( "/c/repo" ) == "C:/repo" );
    CHECK( normalized( "/d" ) == "D:" );
    CHECK( normalized( "src/a.cpp,/c/x/b.cpp" ) == "src/a.cpp,C:/x/b.cpp" );
    CHECK( normalized( "/c,/d/y" ) == "C:,D:/y" );
    CHECK( normalized( "C:/a/b" ) == "C:/a/b" );         // PR #44's rewrite also fired after ':' and made this "C:A:b"
    CHECK( normalized( "/cd/x" ) == "/cd/x" );
    CHECK( normalized( "rel/c/x" ) == "rel/c/x" );
    CHECK( normalized( "c:\\Repo" ) == "C:/Repo" );          // the drive upper-cased, nothing else
    CHECK( normalized( "a,d:/x" ) == "a,D:/x" );
    CHECK( normalized( "" ).empty() );
    std::string text = "/e/\\x";
    const std::size_t before = text.size();
    normalizePathArgInPlace( text.data() );
    CHECK( text == "E://x" );
    CHECK( text.size() == before );
    normalizePathArgInPlace( nullptr );                   // no crash
}

TEST_CASE( "rebaseDevNull: a POSIX fail-closed path stays unopenable on Windows" )
{
    CHECK( rebaseDevNull( "/dev/null" ) == "NUL" );
    const std::string unusable = rebaseDevNull( "/dev/null/ripwire-cache-unavailable/blob" );
    CHECK( unusable.find( '|' ) != std::string::npos );          // '|' is refused in every Win32 file name
    CHECK( unusable.find( "ripwire-cache-unavailable/blob" ) != std::string::npos );
    CHECK( rebaseDevNull( "/dev/nullx" ).empty() );
    CHECK( rebaseDevNull( "/dev/null2/x" ).empty() );
    CHECK( rebaseDevNull( "C:/dev/null/x" ).empty() );
}

TEST_CASE( "rebaseMsysTmp: Git for Windows' /tmp is the user's temp directory; nothing else moves" )
{
    CHECK( rebaseMsysTmp( "/tmp/ripwire-1001", "C:\\Users\\x\\AppData\\Local\\Temp\\" ) == "C:/Users/x/AppData/Local/Temp/ripwire-1001" );
    CHECK( rebaseMsysTmp( "/tmp", "c:/t/" ) == "C:/t" );
    CHECK( rebaseMsysTmp( "/tmp/", "C:/t" ) == "C:/t/" );
    CHECK( rebaseMsysTmp( "/tmpfoo/x", "C:/t" ).empty() );      // a sibling whose name starts with tmp
    CHECK( rebaseMsysTmp( "/var/tmp/x", "C:/t" ).empty() );
    CHECK( rebaseMsysTmp( "C:/tmp/x", "C:/t" ).empty() );
    CHECK( rebaseMsysTmp( "/tmp/x", "" ).empty() );
}

TEST_CASE( "extendedLengthPath: only an absolute, clean path gets the \\\\?\\ prefix" )
{
    CHECK( extendedLengthPath( u"C:\\Users\\x\\Temp\\" ) == u"\\\\?\\C:\\Users\\x\\Temp\\" );
    CHECK( extendedLengthPath( u"c:/a/b" ) == u"\\\\?\\c:\\a\\b" );
    CHECK( extendedLengthPath( u"\\\\server\\share\\dir" ) == u"\\\\?\\UNC\\server\\share\\dir" );
    CHECK( extendedLengthPath( u"\\\\?\\C:\\already" ) == u"\\\\?\\C:\\already" );
    CHECK( extendedLengthPath( u"relative\\x" ).empty() );
    CHECK( extendedLengthPath( u"C:relative" ).empty() );                    // drive-relative
    CHECK( extendedLengthPath( u"\\rooted-no-drive" ).empty() );
    CHECK( extendedLengthPath( u"C:\\a\\..\\b" ).empty() );              // ".." would not be folded under the prefix
    CHECK( extendedLengthPath( u"C:\\a\\.\\b" ).empty() );
    CHECK( extendedLengthPath( u"C:\\..hidden\\.x" ) == u"\\\\?\\C:\\..hidden\\.x" );   // names that only start with dots are fine
    CHECK( extendedLengthPath( u"\\\\.\\pipe\\x" ).empty() );         // a device path is not a UNC share
}

TEST_CASE( "isLongTemporaryEntry: TMP/TEMP/TMPDIR, any case, at or past the limit" )
{
    const std::u16string longValue( 240, u'x' );
    const std::u16string shortValue( 239, u'x' );
    CHECK( isLongTemporaryEntry( u"TMP=" + longValue ) );
    CHECK( isLongTemporaryEntry( u"temp=" + longValue ) );
    CHECK( isLongTemporaryEntry( u"TmpDir=" + longValue ) );
    CHECK( !isLongTemporaryEntry( u"TMP=" + shortValue ) );
    CHECK( !isLongTemporaryEntry( u"TEMPORARY=" + longValue ) );
    CHECK( !isLongTemporaryEntry( u"PATH=" + longValue ) );
    CHECK( !isLongTemporaryEntry( u"=C:=" + longValue ) );
    CHECK( !isLongTemporaryEntry( u"TMP" ) );
    CHECK( isLongTemporaryEntry( u"TMP=abcd", 4 ) );
}

// ── 4. command-line quoting ─────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "quoting: libuv's documented cases, always quoted" )
{
    const auto quoted = []( std::string_view arg ) { std::string out; appendQuotedArg( out, arg ); return out; };
    CHECK( quoted( "" ) == "\"\"" );
#if defined( OSWIN_LOGIC_MUTANT )
    CHECK( quoted( "hello" ) == "hello" );                     // MUTANT: libuv's bare form — must be caught
    CHECK( errnoFromWin32( 5 ) == EPERM );                     // MUTANT: libuv's EPERM for ACCESS_DENIED — must be caught
#else
    CHECK( quoted( "hello" ) == "\"hello\"" );
#endif
    CHECK( quoted( "hello\"world" ) == "\"hello\\\"world\"" );
    CHECK( quoted( "hello\"\"world" ) == "\"hello\\\"\\\"world\"" );
    CHECK( quoted( "hello\\world" ) == "\"hello\\world\"" );
    CHECK( quoted( "hello\\\\world" ) == "\"hello\\\\world\"" );
    CHECK( quoted( "hello\\\"world" ) == "\"hello\\\\\\\"world\"" );
    CHECK( quoted( "hello\\\\\"world" ) == "\"hello\\\\\\\\\\\"world\"" );
    CHECK( quoted( "hello world\\" ) == "\"hello world\\\\\"" );
    CHECK( quoted( "*.cpp" ) == "\"*.cpp\"" );            // quoted, so the MSYS runtime does not glob it
}

// A deterministic generator whose arithmetic never wraps: arm (B) of oswin32logiccheck runs this file under the G1
// `integer` sanitizer, which refuses std::mt19937's own tempering inside libc++ (a left shift that drops bits). The
// state stays below 2^31 and the multiplier below 2^31, so the product fits in 64 bits. Quality is not the point:
// only that the vectors vary and every run draws the same ones.
struct Lcg31
{
    std::uint64_t state;
    int below( int bound ) noexcept
    {
        state = ( state * 1103515245u + 12345u ) % 2147483648u;
        return static_cast<int>( state % static_cast<std::uint64_t>( bound ) );
    }
};

TEST_CASE( "quoting: 20,000 random argument vectors survive the MSVCRT parser unchanged" )
{
    Lcg31 rng{ 0x5eed };
    const std::string_view alphabet[] = { "a", "b", " ", "\t", "\"", "\\", "*", "?", "'", "$", "%", "^", "&", "|", "\xC3\xA9", "\xF0\x9F\x98\x80", "-c", "/" };
    for( int trial = 0; trial < 20000; ++trial )
    {
        std::vector<std::string> argv{ "C:/Program Files/Git/bin/bash.exe" };
        const int count = rng.below( 5 );
        for( int a = 0; a < count; ++a )
        {
            std::string arg;
            const int length = rng.below( 13 );
            for( int c = 0; c < length; ++c ) { arg += alphabet[ rng.below( int( std::size( alphabet ) ) ) ]; }
            argv.push_back( arg );
        }
        std::string line;
        for( const std::string& arg : argv )
        {
            if( !line.empty() ) { line.push_back( ' ' ); }
            appendQuotedArg( line, arg );
        }
        CAPTURE( line );
        REQUIRE( parseCommandLine( line ) == argv );
    }
}

TEST_CASE( "quoting: buildCommandLine joins with single spaces and refuses an embedded NUL" )
{
    CHECK( buildCommandLine( { "bash.exe", "-c", "echo \"hi\"" } ) == "\"bash.exe\" \"-c\" \"echo \\\"hi\\\"\"" );
    CHECK( buildCommandLine( { "a", std::string_view( "b\0c", 3 ) } ).empty() );
    CHECK( parseCommandLine( buildCommandLine( { "C:/x/bash.exe", "-c", "git log --format='%H' | tail -1" } ) )
           == std::vector<std::string>{ "C:/x/bash.exe", "-c", "git log --format='%H' | tail -1" } );
}

// ── 5. reparse points and modes ─────────────────────────────────────────────────────────────────────────────
TEST_CASE( "reparse: symlink and junction are links; cloud, dedup, app-exec-link and WSL tags are not" )
{
    CHECK( isLinkReparseTag( 0xA000000C ) );   // IO_REPARSE_TAG_SYMLINK
    CHECK( isLinkReparseTag( 0xA0000003 ) );   // IO_REPARSE_TAG_MOUNT_POINT
    for( const std::uint32_t tag : { 0x9000001Au, 0x9000101Au, 0x80000013u, 0x8000001Bu, 0xA000001Du, 0x80000017u, 0u } )
    {
        CAPTURE( tag );
        CHECK( !isLinkReparseTag( tag ) );
    }
    CHECK( classifyFinalComponent( kFileAttributeReparsePoint, kReparseTagSymlink ) == FinalComponent::Link );
    CHECK( classifyFinalComponent( kFileAttributeReparsePoint | kFileAttributeDirectory, kReparseTagMountPoint ) == FinalComponent::Link );
    CHECK( classifyFinalComponent( kFileAttributeReparsePoint, 0x9000001A ) == FinalComponent::OtherReparse );
    CHECK( classifyFinalComponent( 0, kReparseTagSymlink ) == FinalComponent::Plain );   // no reparse attribute: the tag is noise
    CHECK( classifyFinalComponent( kFileAttributeDirectory, 0 ) == FinalComponent::Plain );
}

TEST_CASE( "mode: type bits match the traditional S_IF* encoding, and the host's S_IS* macros where it has them" )
{
    CHECK( kModeFifo == traditional::kIfifo );
    CHECK( kModeCharacter == traditional::kIfchr );
    CHECK( kModeDirectory == traditional::kIfdir );
    CHECK( kModeRegular == traditional::kIfreg );
    CHECK( kModeLink == traditional::kIflnk );

    const unsigned symlink  = modeTypeBits( kFileTypeDisk, kFileAttributeReparsePoint, kReparseTagSymlink, false );
    const unsigned junction = modeTypeBits( kFileTypeDisk, kFileAttributeReparsePoint | kFileAttributeDirectory, kReparseTagMountPoint, true );
    const unsigned oneDrive = modeTypeBits( kFileTypeDisk, kFileAttributeReparsePoint, 0x9000001A, false );   // a OneDrive placeholder
    const unsigned dir      = modeTypeBits( kFileTypeDisk, kFileAttributeDirectory, 0, false );
    const unsigned regular  = modeTypeBits( kFileTypeDisk, 0, 0, false );
    const unsigned fifo     = modeTypeBits( kFileTypePipe, 0, 0, true );
    const unsigned chr      = modeTypeBits( kFileTypeChar, 0, 0, true );
    CHECK( traditional::isType( symlink, traditional::kIflnk ) );
    CHECK( traditional::isType( junction, traditional::kIfdir ) );
    CHECK( traditional::isType( oneDrive, traditional::kIfreg ) );
    CHECK( traditional::isType( dir, traditional::kIfdir ) );
    CHECK( traditional::isType( regular, traditional::kIfreg ) );
    CHECK( traditional::isType( fifo, traditional::kIfifo ) );
    CHECK( traditional::isType( chr, traditional::kIfchr ) );
#if OSWIN_TEST_HOST_WAIT_MACROS   // the macros do not exist to name on a host without them, so this cannot be an if
    CHECK( kModeLink == unsigned( S_IFLNK ) );
    CHECK( S_ISLNK( symlink ) );
    CHECK( S_ISDIR( junction ) );
    CHECK( S_ISREG( oneDrive ) );
    CHECK( S_ISDIR( dir ) );
    CHECK( S_ISREG( regular ) );
    CHECK( S_ISFIFO( fifo ) );
    CHECK( S_ISCHR( chr ) );
#endif
    CHECK( modePermissionBits( 0 ) == 0777 );
    CHECK( modePermissionBits( kFileAttributeReadonly ) == 0555 );
    CHECK( modePermissionBits( kFileAttributeReadonly | kFileAttributeDirectory ) == 0777 );   // read-only is not honoured on directories
}

// ── 6. time, wait status, timeouts, socket descriptors ──────────────────────────────────────────────────────
TEST_CASE( "time: FILETIME ticks to Unix seconds and nanoseconds, floor-divided" )
{
    const auto at = []( std::int64_t ticks ) { return unixTimeFromFiletime( ticks ); };
    CHECK( at( kFiletimeTicksAtUnixEpoch ).seconds == 0 );
    CHECK( at( kFiletimeTicksAtUnixEpoch ).nanoseconds == 0 );
    CHECK( at( kFiletimeTicksAtUnixEpoch + 1 ).nanoseconds == 100 );
    CHECK( at( kFiletimeTicksAtUnixEpoch - 1 ).seconds == -1 );
    CHECK( at( kFiletimeTicksAtUnixEpoch - 1 ).nanoseconds == 999999900 );
    // 2026-09-16T00:00:00Z = 1789516800 s
    const UnixTime day = at( kFiletimeTicksAtUnixEpoch + 1789516800LL * 10000000LL + 1234567 );
    CHECK( day.seconds == 1789516800 );
    CHECK( day.nanoseconds == 123456700 );
}

TEST_CASE( "wait status: the encoding decodes as a POSIX child's would — traditional encoding, and the host's W* macros" )
{
    // Checks one status through every decoder this host has: the traditional-encoding oracle, the header's own
    // decoders (what os.h's W* macros expand to on Windows), and the host's W* macros where they exist.
    const auto exitedWith = []( int status, int code )
    {
        CHECK( traditional::exited( status ) );
        CHECK( !traditional::signaled( status ) );
        CHECK( traditional::exitStatus( status ) == code );
        CHECK( rw::oswin::waitIfExited( status ) );
        CHECK( !rw::oswin::waitIfSignaled( status ) );
        CHECK( rw::oswin::waitExitStatus( status ) == code );
#if OSWIN_TEST_HOST_WAIT_MACROS
        const int hostStatus = status;   // macOS's W* macros need an lvalue
        CHECK( WIFEXITED( hostStatus ) );
        CHECK( !WIFSIGNALED( hostStatus ) );
        CHECK( WEXITSTATUS( hostStatus ) == code );
#endif
    };
    const auto signaledWith = []( int status, int signal )
    {
        CHECK( traditional::signaled( status ) );
        CHECK( !traditional::exited( status ) );
        CHECK( traditional::termSig( status ) == signal );
        CHECK( rw::oswin::waitIfSignaled( status ) );
        CHECK( !rw::oswin::waitIfExited( status ) );
        CHECK( rw::oswin::waitTermSig( status ) == signal );
#if OSWIN_TEST_HOST_WAIT_MACROS
        const int hostStatus = status;
        CHECK( WIFSIGNALED( hostStatus ) );
        CHECK( !WIFEXITED( hostStatus ) );
        CHECK( WTERMSIG( hostStatus ) == signal );
#endif
    };
    for( const std::uint32_t code : { 0u, 1u, 2u, 3u, 42u, 126u, 127u, 255u } )
    {
        CAPTURE( code );
        exitedWith( waitStatusFromExit( code ), int( code ) );
    }
    exitedWith( waitStatusFromExit( 256 ), 0 );   // POSIX keeps the low 8 bits too
    for( const auto& [ code, signal ] : { std::pair{ 0xC0000005u, 11 }, std::pair{ 0xC00000FDu, 11 }, std::pair{ 0xC000001Du, 4 },
                                          std::pair{ 0xC0000094u, 8 }, std::pair{ 0x80000003u, 5 }, std::pair{ 0xC0000409u, 6 },
                                          std::pair{ 0xC000013Au, 2 } } )
    {
        CAPTURE( code );
        signaledWith( waitStatusFromExit( code ), signal );
    }
    signaledWith( waitStatusFromSignal( kSignalKill ), 9 );
}

TEST_CASE( "SO_RCVTIMEO: a nonzero timeval never becomes Winsock's 0 = wait forever" )
{
    CHECK( millisecondsFromTimeval( 10, 0 ) == 10000u );
    CHECK( millisecondsFromTimeval( 0, 500 ) == 1u );          // PR #44 truncated this to 0: an infinite wait
    CHECK( millisecondsFromTimeval( 0, 1000 ) == 1u );
    CHECK( millisecondsFromTimeval( 0, 1001 ) == 2u );
    CHECK( millisecondsFromTimeval( 0, 0 ) == 0u );
    CHECK( millisecondsFromTimeval( -1, 0 ) == 0u );
    CHECK( millisecondsFromTimeval( 5000000, 0 ) == 0xFFFFFFFEu );
}

TEST_CASE( "socket descriptors: a range the CRT never hands out" )
{
    CHECK( kSocketFdBase > 8192 );
    CHECK( !isSocketFd( 0 ) );
    CHECK( !isSocketFd( 8191 ) );
    CHECK( !isSocketFd( -1 ) );
    CHECK( isSocketFd( kSocketFdBase ) );
    CHECK( isSocketFd( kSocketFdBase + kSocketFdCount - 1 ) );
    CHECK( !isSocketFd( kSocketFdBase + kSocketFdCount ) );
    CHECK( isDirwatchFd( kDirwatchFdBase ) );
    CHECK( !isDirwatchFd( kSocketFdBase ) );
    CHECK( !isSocketFd( kDirwatchFdBase ) );
    CHECK( !isDirwatchFd( 3 ) );
}

// ── 7. the shell ────────────────────────────────────────────────────────────────────────────────────────────
TEST_CASE( "shell: only an absolute, non-WSL bash is acceptable" )
{
    CHECK( isAcceptableShell( "C:/Program Files/Git/bin/bash.exe" ) );
    CHECK( isAcceptableShell( "C:\\Program Files\\Git\\usr\\bin\\bash.exe" ) );
    CHECK( isAcceptableShell( "//server/tools/Git/bin/BASH.EXE" ) );
    CHECK( !isAcceptableShell( "C:\\Windows\\System32\\bash.exe" ) );                              // WSL launcher
    CHECK( !isAcceptableShell( "c:/windows/sysnative/bash.exe" ) );
    CHECK( !isAcceptableShell( "C:/Users/x/AppData/Local/Microsoft/WindowsApps/bash.exe" ) );      // WSL alias
    CHECK( !isAcceptableShell( "bash.exe" ) );                                                     // relative: the current directory
    CHECK( !isAcceptableShell( ".\\bash.exe" ) );
    CHECK( !isAcceptableShell( "repo/tools/bash.exe" ) );
    CHECK( !isAcceptableShell( "C:/repo/sh.exe" ) );                                               // not bash
    CHECK( !isAcceptableShell( "C:bash.exe" ) );                                                   // drive-relative
}

TEST_CASE( "executables: extension detection and PATHEXT membership" )
{
    CHECK( hasExtension( "tool.exe" ) );
    CHECK( hasExtension( "C:/bin/tool.CMD" ) );
    CHECK( !hasExtension( "tool" ) );
    CHECK( !hasExtension( ".profile" ) );
    CHECK( !hasExtension( "dir.d/tool" ) );
    CHECK( !hasExtension( "dir.d\\tool" ) );
    CHECK( !hasExtension( "tool." ) );
    const std::string_view pathext = ".COM;.EXE;.BAT;.CMD";
    CHECK( extensionInList( "C:/x/ripwire.exe", pathext ) );
    CHECK( extensionInList( "codex.cmd", pathext ) );
    CHECK( !extensionInList( "script.py", pathext ) );
    CHECK( !extensionInList( "ripwire", pathext ) );
    CHECK( !extensionInList( "a.exe", "" ) );
    CHECK( extensionInList( "a.exe", ";;.exe;" ) );
}

TEST_CASE( "shell: PATH entries split on ';', keep empties for the caller to skip, and unquote" )
{
    const std::string_view list = "C:\\Git\\bin;;\"C:\\odd;dir\";relative;D:/x";
    std::size_t at = 0;
    std::vector<std::string_view> entries;
    while( at <= list.size() ) { entries.push_back( nextPathListEntry( list, at ) ); }
    // a quoted entry containing ';' is split by the ';' first — the documented Windows behaviour is that PATH
    // entries cannot contain ';' at all, so the halves are what cmd.exe sees too
    CHECK( entries.front() == "C:\\Git\\bin" );
    CHECK( entries[ 1 ].empty() );
    CHECK( entries.back() == "D:/x" );
    std::size_t one = 0;
    CHECK( nextPathListEntry( "\"C:\\Program Files\\Git\\bin\"", one ) == "C:\\Program Files\\Git\\bin" );
}
