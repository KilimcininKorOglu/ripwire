// os_win32.cpp — the Windows bodies of the functions src/infra/os.h declares. Compiled only for Windows.
//
// TRANSITIONAL STATE. This first version DELEGATES: each body forwards to PR #44's compat layer
// (src/infra/platform_compat.{h,cpp}, still force-included into every translation unit) or to the CRT call the compat
// macros used to rename. It exists so the os:: call sites merged from lane/os-header compile on Windows while the
// compat layer is still present; the real bodies replace these one subsystem at a time, and the compat layer is then
// deleted. Nothing here is reachable on Linux or macOS.

#include "platform_compat.h"   // force-included today; named so the dependency is visible
#include "os.h"

#include <cerrno>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <string>

#include <direct.h>
#include <io.h>
#include <process.h>

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
