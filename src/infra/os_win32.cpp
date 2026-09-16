// os_win32.cpp — the Windows bodies of the functions src/infra/os.h declares. Compiled only for Windows.
//
// TRANSITIONAL STATE. This first version DELEGATES: each body forwards to PR #44's compat layer
// (src/infra/platform_compat.{h,cpp}, still force-included into every translation unit) or to the CRT call the compat
// macros used to rename. It exists so the os:: call sites merged from lane/os-header compile on Windows while the
// compat layer is still present; the real bodies replace these one subsystem at a time, and the compat layer is then
// deleted. Nothing here is reachable on Linux or macOS.

#include "platform_compat.h"   // force-included today; named so the dependency is visible
#include "os.h"
#include "os_win32_logic.h"    // the pure logic, compiled and tested on every platform

#include <cerrno>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <string>

#include <direct.h>
#include <io.h>
#include <process.h>
#include <vector>

namespace rw::os
{

namespace
{
    int fromStat64( const struct _stat64& native, stat_t* st )
    {
        *st          = stat_t{};
        st->st_dev   = static_cast<std::uint64_t>( native.st_dev );
        st->st_ino   = static_cast<std::uint64_t>( native.st_ino );
        st->st_mode  = static_cast<mode_t>( native.st_mode );
        st->st_nlink = static_cast<std::uint32_t>( native.st_nlink );
        st->st_uid   = static_cast<uid_t>( -2 );
        st->st_size  = native.st_size;
        st->st_mtime = native.st_mtime;
        st->st_ctime = native.st_ctime;
        st->st_mtim  = ::timespec{ native.st_mtime, 0 };
        st->st_ctim  = ::timespec{ native.st_ctime, 0 };
        return 0;
    }

    int crtFlags( int flags )
    {
        return ( flags & ~( O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC ) ) | _O_BINARY | ( ( flags & O_CLOEXEC ) != 0 ? _O_NOINHERIT : 0 );
    }
}

// ── descriptors and files ──────────────────────────────────────────────────────────────────────────────────
int     open( const char* path, int flags )                          { return ::_open( path, crtFlags( flags ) ); }
int     open( const char* path, int flags, mode_t mode )             { return ::_open( path, crtFlags( flags ), static_cast<int>( mode ) ); }
int     close( int fd )                                              { return rw::compat::rw_close( fd ); }
ssize_t read( int fd, void* buf, std::size_t count )                 { return ::_read( fd, buf, static_cast<unsigned>( count > INT_MAX ? INT_MAX : count ) ); }
ssize_t write( int fd, const void* buf, std::size_t count )          { return ::_write( fd, buf, static_cast<unsigned>( count > INT_MAX ? INT_MAX : count ) ); }
ssize_t pread( int fd, void* buf, std::size_t count, off_t offset )  { return rw::compat::rw_pread( fd, buf, count, static_cast<std::uint64_t>( offset ) ); }

int fstat( int fd, stat_t* st )
{
    struct _stat64 native {};
    return ::_fstat64( fd, &native ) != 0 ? -1 : fromStat64( native, st );
}
int stat( const char* path, stat_t* st )
{
    struct _stat64 native {};
    return ::_stat64( path, &native ) != 0 ? -1 : fromStat64( native, st );
}
int lstat( const char* path, stat_t* st )                            { return os::stat( path, st ); }
int fcntl( int fd, int cmd )                                         { return rw_fcntl( fd, cmd ); }
int fcntl( int fd, int cmd, int arg )                                { return rw_fcntl( fd, cmd, arg ); }
int dup( int fd )                                                    { return ::_dup( fd ); }
int dup2( int fd, int fd2 )                                          { return ::_dup2( fd, fd2 ); }
int ftruncate( int fd, off_t length )
{
    const errno_t e = ::_chsize_s( fd, length );
    if( e != 0 )
    {
        errno = e;
        return -1;
    }
    return 0;
}
int fsync( int fd )                                                  { return ::_commit( fd ); }
int fchmod( int, mode_t )                                            { return 0; }
int flock( int fd, int operation )                                   { return rw::compat::rw_flock( fd, operation ); }
int pipe( int fds[ 2 ] )                                             { return ::_pipe( fds, 65536, _O_BINARY | _O_NOINHERIT ); }
int poll( pollfd*, nfds_t, int timeoutMs )
{
    ::Sleep( timeoutMs < 0 ? 0 : static_cast<DWORD>( timeoutMs ) );
    return 0;
}

// ── streams ────────────────────────────────────────────────────────────────────────────────────────────────
std::FILE* fdopen( int fd, const char* mode )                        { return ::_fdopen( fd, mode ); }
int        fileno( std::FILE* stream )                               { return ::_fileno( stream ); }
ssize_t getline( char** line, std::size_t* capacity, std::FILE* stream )
{
    std::size_t used = 0;
    for( ;; )
    {
        const int c = std::fgetc( stream );
        if( c == EOF )
        {
            return used == 0 ? -1 : static_cast<ssize_t>( used );
        }
        if( *line == nullptr || used + 2 > *capacity )
        {
            const std::size_t grown = *capacity < 128 ? 128 : *capacity * 2;
            char* const       next  = static_cast<char*>( std::realloc( *line, grown ) );
            if( next == nullptr )
            {
                errno = ENOMEM;
                return -1;
            }
            *line     = next;
            *capacity = grown;
        }
        ( *line )[ used++ ] = static_cast<char>( c );
        ( *line )[ used ]   = '\0';
        if( c == '\n' )
        {
            return static_cast<ssize_t>( used );
        }
    }
}
std::FILE* open_memstream( char** buffer, std::size_t* size )        { return rw::compat::rw_open_memstream( buffer, size ); }

// ── paths ──────────────────────────────────────────────────────────────────────────────────────────────────
int unlink( const char* path )                                       { return ::_unlink( path ); }
int remove( const char* path )                                       { return rw::compat::rw_remove_utf8( path ); }
int rename( const char* from, const char* to )
{
    if( rw::compat::rw_rename( from, to ) == 0 )
    {
        return 0;
    }
    errno = EACCES;
    return -1;
}
int   mkdir( const char* path, mode_t )                              { return ::_mkdir( path ); }
int   chmod( const char*, mode_t )                                   { return 0; }
int   access( const char* path, int mode )                           { return ::_access( path, mode & ( W_OK | R_OK ) ); }
char* realpath( const char* path, char* resolved )
{
    char* out = resolved != nullptr ? resolved : static_cast<char*>( std::malloc( PATH_MAX ) );
    if( out == nullptr )
    {
        errno = ENOMEM;
        return nullptr;
    }
    if( rw::compat::rw_realpath( path, out ) == nullptr )
    {
        if( resolved == nullptr )
        {
            std::free( out );
        }
        return nullptr;
    }
    for( char* p = out; *p != '\0'; ++p )
    {
        if( *p == '\\' )
        {
            *p = '/';
        }
    }
    return out;
}
char* getcwd( char* buf, std::size_t size )                          { return ::_getcwd( buf, static_cast<int>( size ) ); }
int   setenv( const char* name, const char* value, int overwrite )
{
    if( overwrite == 0 && std::getenv( name ) != nullptr )
    {
        return 0;
    }
    return ::_putenv_s( name, value ) == 0 ? 0 : -1;
}

// ── process start and path intake ──────────────────────────────────────────────────────────────────────────
void normalize_path_arg( char* text )
{
    oswin::normalizePathArgInPlace( text );
}

namespace
{
    // UTF-8 of a UTF-16 string, or false (a lone surrogate) — the caller keeps what it had.
    bool utf8Of( std::u16string_view wide, std::string& out )
    {
        const std::ptrdiff_t bytes = oswin::utf8LengthOf( wide );
        if( bytes < 0 )
        {
            return false;
        }
        out.assign( static_cast<std::size_t>( bytes ), '\0' );
        oswin::encodeUtf8( wide, out.data() );
        return true;
    }

    std::u16string_view viewOf( const wchar_t* text )
    {
        return text == nullptr ? std::u16string_view() : std::u16string_view( reinterpret_cast<const char16_t*>( text ), std::wcslen( text ) );
    }
}

void init_process( int& argc, char**& argv )
{
    static_assert( sizeof( wchar_t ) == sizeof( char16_t ), "the Windows ABI's wchar_t is UTF-16" );

    // stdout carries XML/JSON bytes and stdin carries MCP requests: no CRLF translation in either direction.
    (void)::_setmode( ::_fileno( stdin ), _O_BINARY );
    (void)::_setmode( ::_fileno( stdout ), _O_BINARY );
    (void)::_setmode( ::_fileno( stderr ), _O_BINARY );

    // argv as UTF-8, from the UTF-16 command line: the CRT's narrow argv is in the ANSI code page, which is UTF-8 only
    // when the manifest's activeCodePage took effect. One allocation for the process; an argument that is not valid
    // UTF-16 leaves the CRT's argv in place (every argument, so indices stay aligned).
    int                   wideCount = 0;
    const LPWSTR* const   wideArgv  = ::CommandLineToArgvW( ::GetCommandLineW(), &wideCount );
    if( wideArgv != nullptr )
    {
        static std::vector<std::string> storage;
        static std::vector<char*>       pointers;
        storage.resize( static_cast<std::size_t>( wideCount ) );
        bool allValid = wideCount > 0;
        for( int i = 0; i < wideCount && allValid; ++i )
        {
            allValid = utf8Of( viewOf( wideArgv[ i ] ), storage[ static_cast<std::size_t>( i ) ] );
        }
        ::LocalFree( const_cast<HLOCAL>( wideArgv ) );
        if( allValid )
        {
            pointers.clear();
            for( std::string& arg : storage )
            {
                pointers.push_back( arg.data() );
            }
            pointers.push_back( nullptr );
            argc = wideCount;
            argv = pointers.data();
        }
    }

    // the path-valued environment the program reads, in its own spelling. A variable left unchanged is not rewritten, so
    // a child process inherits exactly what this one was given unless the spelling had to change.
    static constexpr const wchar_t* kPathVariables[] = { L"HOME", L"TMPDIR", L"XDG_CACHE_HOME", L"CODEX_HOME", L"CLAUDE_CONFIG_DIR" };
    for( const wchar_t* name : kPathVariables )
    {
        std::string value;
        if( !utf8Of( viewOf( ::_wgetenv( name ) ), value ) || value.empty() )
        {
            continue;
        }
        const std::string before = value;
        oswin::normalizePathArgInPlace( value.data() );
        if( value == before )
        {
            continue;
        }
        const std::ptrdiff_t units = oswin::utf16LengthOf( value );   // valid: it was UTF-16 a moment ago
        std::u16string       programSpelling( static_cast<std::size_t>( units < 0 ? 0 : units ), u'\0' );
        oswin::encodeUtf16( value, programSpelling.data() );
        (void)::_wputenv_s( name, reinterpret_cast<const wchar_t*>( programSpelling.c_str() ) );
    }
}

int exepath( char* buf, std::size_t bufCount )
{
    const std::string self = rw::compat::rw_self_exe_path();
    if( self.empty() || self.size() + 1 > bufCount )
    {
        return -1;
    }
    std::memcpy( buf, self.c_str(), self.size() + 1 );
    return 0;
}

// ── time ───────────────────────────────────────────────────────────────────────────────────────────────────
int nanosleep( const ::timespec* request, ::timespec* remaining )    { return ::nanosleep( request, remaining ); }
std::tm* localtime_r( const std::time_t* time, std::tm* result )     { return ::localtime_s( result, time ) == 0 ? result : nullptr; }

// ── processes ──────────────────────────────────────────────────────────────────────────────────────────────
pid_t      getpid()                                                  { return ::_getpid(); }
uid_t      getuid()                                                  { return ::getuid(); }
int        kill( pid_t, int )                                        { errno = ENOSYS; return -1; }
pid_t      waitpid( pid_t, int*, int )                               { errno = ENOSYS; return -1; }
std::FILE* popen( const char* command, const char* mode )            { return rw::compat::rw_popen( command, mode ); }
int        pclose( std::FILE* stream )                               { return rw::compat::rw_pclose( stream ); }
int        system( const char* command )                             { return rw::compat::rw_system( command ); }
pid_t      spawn_sh( const std::string&, const int[ 2 ] )            { errno = ENOSYS; return -1; }

// ── threads ────────────────────────────────────────────────────────────────────────────────────────────────
pthread_t     pthread_self()                                         { return ::GetCurrentThreadId(); }
std::uint64_t gettid()                                               { return ::GetCurrentThreadId(); }
int pthread_main_np()
{
    static const DWORD firstCaller = ::GetCurrentThreadId();
    return ::GetCurrentThreadId() == firstCaller ? 1 : 0;
}
int pthread_getname_np( pthread_t, char* name, std::size_t nameCount )
{
    if( nameCount > 0 )
    {
        name[ 0 ] = '\0';
    }
    return 0;
}

// ── sockets (transitional: a SOCKET narrowed to int, as the compat layer's callers did) ───────────────────────
int     socket( int domain, int type, int protocol )                 { return static_cast<int>( ::socket( domain, type, protocol ) ); }
int     setsockopt( int fd, int level, int name, const void* value, socklen_t length ) { return rw::compat::rw_setsockopt( static_cast<SOCKET>( fd ), level, name, value, length ); }
int     bind( int fd, const ::sockaddr* address, socklen_t length )  { return ::bind( static_cast<SOCKET>( fd ), address, length ); }
int     listen( int fd, int backlog )                                { return ::listen( static_cast<SOCKET>( fd ), backlog ); }
int     accept( int fd, ::sockaddr* address, socklen_t* length )     { return static_cast<int>( ::accept( static_cast<SOCKET>( fd ), address, length ) ); }
ssize_t recv( int fd, void* buf, std::size_t count, int flags )      { return ::recv( static_cast<SOCKET>( fd ), static_cast<char*>( buf ), static_cast<int>( count > INT_MAX ? INT_MAX : count ), flags ); }
ssize_t send( int fd, const void* buf, std::size_t count, int flags ) { return ::send( static_cast<SOCKET>( fd ), static_cast<const char*>( buf ), static_cast<int>( count > INT_MAX ? INT_MAX : count ), flags ); }
int     inet_pton( int family, const char* text, void* address )     { return ::inet_pton( family, text, address ); }
int     setsockopt_nosigpipe( int, const void*, socklen_t )          { return 0; }

}   // namespace rw::os
