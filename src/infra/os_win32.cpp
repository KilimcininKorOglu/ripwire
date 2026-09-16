// os_win32.cpp — the Windows bodies of the functions os.h declares. Compiled only for Windows; the one translation
// unit that includes <windows.h>.
//
// WHAT EACH BODY KEEPS. A call site is POSIX code, so each body keeps the POSIX contract that call site reads: the
// return value, errno (from os_win32_logic.h's one Win32→errno table), and the stat fields. Where Windows semantics
// differ in a way a caller can see, the difference is named at that body. Paths arrive in the program's spelling
// (UTF-8, '/') and are converted at the call through NativePath — a stack buffer, heap only past MAX_PATH — and
// paths handed back (realpath, getcwd, exepath, which) leave in that spelling again.
//
// WHAT IS NOT HERE. Every piece of logic that needs no Win32 call — the errno table, UTF-8/UTF-16, quoting, reparse
// classification, time and wait-status conversion — is in os_win32_logic.h, compiled and tested on every platform.
//
// TRANSITIONAL. The locks, the cache-directory ACLs, the processes and the sockets still delegate to PR #44's compat
// layer (platform_compat.{h,cpp}, force-included) until their own bodies land; each such section says so.

#include "platform_compat.h"   // TRANSITIONAL: force-included today; named so the dependency is visible
#include "os.h"
#include "os_win32_logic.h"    // the pure logic, compiled and tested on every platform

#include <cerrno>
#include <climits>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <cwchar>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <string_view>
#include <vector>

#include <direct.h>
#include <io.h>
#include <process.h>

namespace rw::os
{

namespace
{

// ── errno ───────────────────────────────────────────────────────────────────────────────────────────────────────
int fail( int errnoValue )
{
    errno = errnoValue;
    return -1;
}

int failWin32( DWORD code )
{
    errno = oswin::errnoFromWin32( code );
    return -1;
}

int failLastError()
{
    return failWin32( ::GetLastError() );
}

// ── UTF-8 / UTF-16 at the boundary ──────────────────────────────────────────────────────────────────────────────
std::u16string_view viewOf( const wchar_t* text )
{
    return text == nullptr ? std::u16string_view() : std::u16string_view( reinterpret_cast<const char16_t*>( text ), std::wcslen( text ) );
}

// UTF-8 of a UTF-16 string, or false (a lone surrogate); `out` is untouched on false.
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

std::u16string utf16Of( std::string_view utf8, bool& ok )
{
    const std::ptrdiff_t units = oswin::utf16LengthOf( utf8 );
    ok = units >= 0;
    std::u16string out( static_cast<std::size_t>( ok ? units : 0 ), u'\0' );
    if( ok )
    {
        oswin::encodeUtf16( utf8, out.data() );
    }
    return out;
}

// An environment variable in UTF-8, read from the wide environment (the narrow one is in the ANSI code page).
std::string environmentUtf8( const wchar_t* name )
{
    std::string value;
    const wchar_t* const wide = ::_wgetenv( name );
    if( wide != nullptr )
    {
        (void)utf8Of( viewOf( wide ), value );
    }
    return value;
}

// A native path returned by Windows, written to `out` in the program's spelling: 0, or -1 with errno.
int programPathInto( std::u16string_view native, char* out, std::size_t outCount )
{
    int error = 0;
    if( oswin::programPathFromNative( native, out, outCount, &error ) < 0 )
    {
        return fail( error );
    }
    return 0;
}

// The user's temporary directory in the program's spelling — Git for Windows' "/tmp" — read once.
const std::string& userTempDirectory()
{
    static const std::string directory = []
    {
        wchar_t     buffer[ MAX_PATH + 2 ];
        const DWORD length = ::GetTempPathW( MAX_PATH + 2, buffer );
        char        out[ PATH_MAX ];
        if( length == 0 || length > MAX_PATH + 1 || programPathInto( std::u16string_view( reinterpret_cast<const char16_t*>( buffer ), length ), out, sizeof( out ) ) != 0 )
        {
            return std::string();
        }
        return std::string( out );
    }();
    return directory;
}

// A program path as the -W calls take it: Git for Windows' "/tmp" rebased onto the user's temp directory (only a path
// that starts with "/tmp" pays for the lookup), then WidePath's UTF-16 — '\' separators, "/c/..." as "C:\...", on a
// stack buffer below MAX_PATH.
class NativePath
{
public:
    explicit NativePath( const char* path )
        : rebased_( path != nullptr && std::strncmp( path, "/tmp", 4 ) == 0 ? oswin::rebaseMsysTmp( path, userTempDirectory() ) : std::string() ),
          wide_( rebased_.empty() ? path : rebased_.c_str() )
    {
    }

    [[nodiscard]] bool    ok() const { return wide_.ok(); }
    [[nodiscard]] int     error() const { return wide_.error(); }
    [[nodiscard]] LPCWSTR c_str() const { return reinterpret_cast<LPCWSTR>( wide_.c_str() ); }

private:
    std::string     rebased_;
    oswin::WidePath wide_;
};

constexpr DWORD kShareAll = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;

HANDLE handleOf( int fd )
{
    return oswin::isSocketFd( fd ) ? INVALID_HANDLE_VALUE : reinterpret_cast<HANDLE>( ::_get_osfhandle( fd ) );
}

// ── stat ────────────────────────────────────────────────────────────────────────────────────────────────────────
// What a stat reports, gathered from one handle or one by-name query.
struct Facts
{
    DWORD         fileType    = FILE_TYPE_DISK;
    DWORD         attributes  = 0;
    DWORD         reparseTag  = 0;
    DWORD         links       = 1;
    std::uint64_t volume      = 0;
    std::uint64_t fileId      = 0;
    std::int64_t  size        = 0;
    std::int64_t  writeTicks  = 0;
    std::int64_t  changeTicks = 0;
};

// stat and fstat never read the owner (it costs a security-descriptor query per call); their st_uid is this value,
// which no getuid() returns, so an ownership test over stat fails closed. lstat reads the owner.
constexpr uid_t kOwnerNotRead = static_cast<uid_t>( -2 );

// Three queries at most: GetFileType, then for a disk file BY_HANDLE_FILE_INFORMATION (volume serial, 64-bit file
// index, size, links, attributes) and FILE_BASIC_INFO (the change time POSIX calls ctime), plus the reparse tag only
// when the attributes say there is one.
bool factsFromHandle( HANDLE handle, Facts& facts )
{
    ::SetLastError( NO_ERROR );
    facts.fileType = ::GetFileType( handle );
    if( facts.fileType == FILE_TYPE_UNKNOWN && ::GetLastError() != NO_ERROR )
    {
        return false;
    }
    if( facts.fileType != FILE_TYPE_DISK )
    {
        return true;   // a pipe or a character device: its type is the whole answer
    }
    BY_HANDLE_FILE_INFORMATION information {};
    FILE_BASIC_INFO            basic {};
    if( !::GetFileInformationByHandle( handle, &information ) || !::GetFileInformationByHandleEx( handle, FileBasicInfo, &basic, sizeof( basic ) ) )
    {
        return false;
    }
    facts.attributes  = information.dwFileAttributes;
    facts.links       = information.nNumberOfLinks;
    facts.volume      = information.dwVolumeSerialNumber;
    facts.fileId      = ( std::uint64_t( information.nFileIndexHigh ) << 32 ) | information.nFileIndexLow;
    facts.size        = static_cast<std::int64_t>( ( std::uint64_t( information.nFileSizeHigh ) << 32 ) | information.nFileSizeLow );
    facts.writeTicks  = basic.LastWriteTime.QuadPart;
    facts.changeTicks = basic.ChangeTime.QuadPart;
    if( ( facts.attributes & FILE_ATTRIBUTE_REPARSE_POINT ) != 0 )
    {
        FILE_ATTRIBUTE_TAG_INFO tag {};
        if( ::GetFileInformationByHandleEx( handle, FileAttributeTagInfo, &tag, sizeof( tag ) ) )
        {
            facts.reparseTag = tag.ReparseTag;
        }
    }
    return true;
}

void fillStat( const Facts& facts, bool followed, stat_t* st )
{
    *st          = stat_t{};
    st->st_mode  = oswin::modeTypeBits( facts.fileType, facts.attributes, facts.reparseTag, followed ) | oswin::modePermissionBits( facts.attributes );
    st->st_dev   = facts.volume;
    st->st_ino   = facts.fileId;
    st->st_nlink = facts.links;
    st->st_uid   = kOwnerNotRead;
    st->st_size  = S_ISDIR( st->st_mode ) ? 0 : facts.size;
    if( facts.fileType == FILE_TYPE_DISK )
    {
        const oswin::UnixTime written = oswin::unixTimeFromFiletime( facts.writeTicks );
        const oswin::UnixTime changed = oswin::unixTimeFromFiletime( facts.changeTicks );
        st->st_mtime = static_cast<std::time_t>( written.seconds );
        st->st_ctime = static_cast<std::time_t>( changed.seconds );
        st->st_mtim  = ::timespec{ static_cast<std::time_t>( written.seconds ), written.nanoseconds };
        st->st_ctim  = ::timespec{ static_cast<std::time_t>( changed.seconds ), changed.nanoseconds };
    }
}

// The by-name stat, where the system has it (GetFileInformationByName, FileStatBasicByNameInfo: Windows 11 24H2 /
// Server 2025): one call and no handle, which is what the crawl's warm-run stat of every file wants. Adapted from
// libuv's fs__stat_path (src/win/fs.c at e15526ade343bdfc7cdaaeb0a51b9bba656533ce; MIT, notice in THIRD_PARTY.md):
// the structure layout is declared here under this file's own name so an older SDK builds, the function is looked up
// at run time, and — as libuv does — a reparse point always takes the handle path, which follows or classifies it.
struct StatBasicByName
{
    LARGE_INTEGER fileId;
    LARGE_INTEGER creationTime;
    LARGE_INTEGER lastAccessTime;
    LARGE_INTEGER lastWriteTime;
    LARGE_INTEGER changeTime;
    LARGE_INTEGER allocationSize;
    LARGE_INTEGER endOfFile;
    ULONG         fileAttributes;
    ULONG         reparseTag;
    ULONG         numberOfLinks;
    ULONG         deviceType;
    ULONG         deviceCharacteristics;
    ULONG         reserved;
    LARGE_INTEGER volumeSerialNumber;
    BYTE          fileId128[ 16 ];
};
using GetFileInformationByNameFn = BOOL( WINAPI* )( LPCWSTR, int, void*, ULONG );
constexpr int   kFileStatBasicByNameInfo = 3;
constexpr ULONG kFileDeviceNull          = 0x15;

GetFileInformationByNameFn getFileInformationByName()
{
    static const GetFileInformationByNameFn function = []() -> GetFileInformationByNameFn
    {
        for( const wchar_t* module : { L"kernelbase.dll", L"api-ms-win-core-file-l2-1-4.dll" } )
        {
            if( const HMODULE handle = ::GetModuleHandleW( module ) )
            {
                if( const FARPROC address = ::GetProcAddress( handle, "GetFileInformationByName" ) )
                {
                    return reinterpret_cast<GetFileInformationByNameFn>( reinterpret_cast<void*>( address ) );
                }
            }
        }
        return nullptr;
    }();
    return function;
}

enum class ByName : std::uint8_t
{
    Answered,
    Failed,     // errno set: the path does not exist, no retry would help
    UseHandle,
};

ByName statByName( LPCWSTR path, bool noFollow, stat_t* st )
{
    const GetFileInformationByNameFn byName = getFileInformationByName();
    if( byName == nullptr )
    {
        return ByName::UseHandle;
    }
    StatBasicByName information {};
    if( !byName( path, kFileStatBasicByNameInfo, &information, sizeof( information ) ) )
    {
        const DWORD error = ::GetLastError();
        if( error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND || error == ERROR_NOT_READY || error == ERROR_BAD_NET_NAME )
        {
            (void)failWin32( error );
            return ByName::Failed;
        }
        return ByName::UseHandle;
    }
    if( ( information.fileAttributes & FILE_ATTRIBUTE_REPARSE_POINT ) != 0 )
    {
        return ByName::UseHandle;
    }
    Facts facts;
    facts.fileType    = information.deviceType == kFileDeviceNull ? FILE_TYPE_CHAR : FILE_TYPE_DISK;
    facts.attributes  = information.fileAttributes;
    facts.links       = information.numberOfLinks;
    facts.volume      = static_cast<std::uint64_t>( information.volumeSerialNumber.QuadPart );
    facts.fileId      = static_cast<std::uint64_t>( information.fileId.QuadPart );
    facts.size        = information.endOfFile.QuadPart;
    facts.writeTicks  = information.lastWriteTime.QuadPart;
    facts.changeTicks = information.changeTime.QuadPart;
    fillStat( facts, !noFollow, st );
    return ByName::Answered;
}

int statByHandle( LPCWSTR path, bool noFollow, stat_t* st )
{
    const HANDLE handle = ::CreateFileW( path, FILE_READ_ATTRIBUTES, kShareAll, nullptr, OPEN_EXISTING,
                                         FILE_FLAG_BACKUP_SEMANTICS | ( noFollow ? FILE_FLAG_OPEN_REPARSE_POINT : 0 ), nullptr );
    if( handle == INVALID_HANDLE_VALUE )
    {
        return failLastError();
    }
    Facts       facts;
    const bool  gathered = factsFromHandle( handle, facts );
    const DWORD error    = ::GetLastError();
    ::CloseHandle( handle );
    if( !gathered )
    {
        return failWin32( error );
    }
    fillStat( facts, !noFollow, st );
    return 0;
}

int statPath( const char* path, bool noFollow, stat_t* st )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    switch( statByName( native.c_str(), noFollow, st ) )
    {
        case ByName::Answered:  return 0;
        case ByName::Failed:    return -1;
        case ByName::UseHandle: break;
    }
    return statByHandle( native.c_str(), noFollow, st );
}

// The file identity a no-follow reopen must match.
bool sameFile( HANDLE a, HANDLE b )
{
    BY_HANDLE_FILE_INFORMATION x {}, y {};
    return ::GetFileInformationByHandle( a, &x ) && ::GetFileInformationByHandle( b, &y ) && x.dwVolumeSerialNumber == y.dwVolumeSerialNumber
        && x.nFileIndexHigh == y.nFileIndexHigh && x.nFileIndexLow == y.nFileIndexLow;
}

}   // namespace

// ── descriptors and files ──────────────────────────────────────────────────────────────────────────────────
//
// open: CreateFileW, then _open_osfhandle, so the result is a CRT descriptor read/write/close/fstat accept. The flag
// mapping follows libuv's fs__open (src/win/fs.c at e15526ad; MIT). Every handle shares read, write AND delete, so a
// file one descriptor holds open can still be renamed over or unlinked, as on POSIX; no handle is inheritable.
//   O_NOFOLLOW — the final component is opened with FILE_FLAG_OPEN_REPARSE_POINT and classified by its reparse tag
//     (os_win32_logic.h): a symlink or junction is ELOOP; any other reparse point (a OneDrive placeholder) is reopened
//     normally and must be the SAME file (volume serial and file index), or it is ELOOP too — a link swapped in between
//     the two opens is refused, never followed. Intermediate components are traversed, as POSIX O_NOFOLLOW does.
//     O_TRUNC with O_NOFOLLOW truncates only after that check, so a link is never truncated through.
//   O_NONBLOCK — nothing to do at open: CreateFileW does not block on a pipe or device the way a POSIX FIFO open does,
//     and every caller that passes it refuses a non-regular file by fstat before reading.
//   O_CLOEXEC — every handle here is non-inheritable already.
namespace
{
int openImpl( const char* path, int flags, mode_t mode )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    DWORD access = 0;
    switch( flags & ( O_RDONLY | O_WRONLY | O_RDWR ) )
    {
        case O_RDONLY: access = FILE_GENERIC_READ; break;
        case O_WRONLY: access = FILE_GENERIC_WRITE; break;
        case O_RDWR:   access = FILE_GENERIC_READ | FILE_GENERIC_WRITE; break;
        default:       return fail( EINVAL );
    }
    if( ( flags & O_APPEND ) != 0 )
    {
        access &= ~FILE_WRITE_DATA;
        access |= FILE_APPEND_DATA;
    }
    const bool noFollow = ( flags & O_NOFOLLOW ) != 0;
    const bool truncate = ( flags & O_TRUNC ) != 0;
    const bool truncateAfterCheck = truncate && noFollow;
    DWORD disposition = OPEN_EXISTING;
    if( ( flags & O_CREAT ) != 0 )
    {
        disposition = ( flags & O_EXCL ) != 0 ? CREATE_NEW : ( truncate && !noFollow ) ? CREATE_ALWAYS : OPEN_ALWAYS;
    }
    else if( truncate && !noFollow )
    {
        disposition = TRUNCATE_EXISTING;
    }
    DWORD attributes = FILE_ATTRIBUTE_NORMAL;
    if( ( flags & O_CREAT ) != 0 && ( mode & 0200 ) == 0 )
    {
        attributes = FILE_ATTRIBUTE_READONLY;   // POSIX: a file created without the owner write bit
    }
    const DWORD fileFlags = FILE_FLAG_BACKUP_SEMANTICS | ( noFollow ? FILE_FLAG_OPEN_REPARSE_POINT : 0 );
    HANDLE handle = ::CreateFileW( native.c_str(), access, kShareAll, nullptr, disposition, attributes | fileFlags, nullptr );
    if( handle == INVALID_HANDLE_VALUE )
    {
        return failLastError();
    }
    if( noFollow )
    {
        FILE_ATTRIBUTE_TAG_INFO tag {};
        if( !::GetFileInformationByHandleEx( handle, FileAttributeTagInfo, &tag, sizeof( tag ) ) )
        {
            const DWORD error = ::GetLastError();
            ::CloseHandle( handle );
            return failWin32( error );
        }
        switch( oswin::classifyFinalComponent( tag.FileAttributes, tag.ReparseTag ) )
        {
            case oswin::FinalComponent::Plain:
                break;
            case oswin::FinalComponent::Link:
                ::CloseHandle( handle );
                return fail( ELOOP );
            case oswin::FinalComponent::OtherReparse:
            {
                const HANDLE content = ::CreateFileW( native.c_str(), access, kShareAll, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr );
                const bool   same    = content != INVALID_HANDLE_VALUE && sameFile( handle, content );
                ::CloseHandle( handle );
                if( !same )
                {
                    if( content != INVALID_HANDLE_VALUE )
                    {
                        ::CloseHandle( content );
                    }
                    return fail( ELOOP );
                }
                handle = content;
                break;
            }
        }
        if( truncateAfterCheck )
        {
            FILE_END_OF_FILE_INFO end {};
            if( !::SetFileInformationByHandle( handle, FileEndOfFileInfo, &end, sizeof( end ) ) )
            {
                const DWORD error = ::GetLastError();
                ::CloseHandle( handle );
                return failWin32( error );
            }
        }
    }
    int crtFlags = _O_BINARY;
    if( ( flags & ( O_RDONLY | O_WRONLY | O_RDWR ) ) == O_RDONLY )
    {
        crtFlags |= _O_RDONLY;
    }
    if( ( flags & O_APPEND ) != 0 )
    {
        crtFlags |= _O_APPEND;
    }
    const int fd = ::_open_osfhandle( reinterpret_cast<intptr_t>( handle ), crtFlags );
    if( fd < 0 )
    {
        const int error = errno;
        ::CloseHandle( handle );
        return fail( error );
    }
    return fd;
}
}   // namespace

int open( const char* path, int flags )                  { return openImpl( path, flags, 0666 ); }
int open( const char* path, int flags, mode_t mode )     { return openImpl( path, flags, mode ); }

int close( int fd )
{
    if( oswin::isSocketFd( fd ) )
    {
        return rw::compat::rw_closesocket( static_cast<SOCKET>( fd ) );   // TRANSITIONAL: the socket table lands with the socket bodies
    }
    return ::_close( fd );
}

ssize_t read( int fd, void* buf, std::size_t count )
{
    return ::_read( fd, buf, static_cast<unsigned>( count > INT_MAX ? INT_MAX : count ) );
}

ssize_t write( int fd, const void* buf, std::size_t count )
{
    return ::_write( fd, buf, static_cast<unsigned>( count > INT_MAX ? INT_MAX : count ) );
}

// pread: ReadFile at an explicit OVERLAPPED offset. Unlike POSIX, on a synchronous handle this also moves the
// descriptor's file position (the only caller reads a cache blob by offset and never by position).
ssize_t pread( int fd, void* buf, std::size_t count, off_t offset )
{
    const HANDLE handle = handleOf( fd );
    if( handle == INVALID_HANDLE_VALUE )
    {
        return fail( EBADF );
    }
    OVERLAPPED position {};
    position.Offset     = static_cast<DWORD>( static_cast<std::uint64_t>( offset ) & 0xFFFFFFFFu );
    position.OffsetHigh = static_cast<DWORD>( static_cast<std::uint64_t>( offset ) >> 32 );
    DWORD bytesRead = 0;
    if( !::ReadFile( handle, buf, static_cast<DWORD>( count > INT_MAX ? INT_MAX : count ), &bytesRead, &position ) )
    {
        const DWORD error = ::GetLastError();
        return error == ERROR_HANDLE_EOF ? 0 : failWin32( error );
    }
    return static_cast<ssize_t>( bytesRead );
}

int fstat( int fd, stat_t* st )
{
    const HANDLE handle = handleOf( fd );
    if( handle == INVALID_HANDLE_VALUE )
    {
        return fail( EBADF );
    }
    Facts facts;
    if( !factsFromHandle( handle, facts ) )
    {
        return failLastError();
    }
    fillStat( facts, true, st );
    return 0;
}

int stat( const char* path, stat_t* st )  { return statPath( path, false, st ); }
int lstat( const char* path, stat_t* st ) { return statPath( path, true, st ); }   // TRANSITIONAL: the owner read lands with the cache-directory bodies

// fcntl: a CRT descriptor has no status flags to read or set; F_GETFL answers 0 and F_SETFL accepts and ignores (the
// only caller clears O_NONBLOCK, which a Windows handle never had).
int fcntl( int fd, int cmd )           { return fcntl( fd, cmd, 0 ); }
int fcntl( int fd, int cmd, int )
{
    if( handleOf( fd ) == INVALID_HANDLE_VALUE )
    {
        return fail( EBADF );
    }
    return cmd == F_GETFL || cmd == F_SETFL ? 0 : fail( EINVAL );
}

int dup( int fd )           { return ::_dup( fd ); }
int dup2( int fd, int fd2 ) { return ::_dup2( fd, fd2 ); }

int ftruncate( int fd, off_t length )
{
    const errno_t error = ::_chsize_s( fd, length );
    return error == 0 ? 0 : fail( error );
}

int fsync( int fd ) { return ::_commit( fd ); }

// fchmod: NTFS has no POSIX mode bits. The owner write bit maps to the read-only attribute; everything else is ignored.
int fchmod( int fd, mode_t mode )
{
    const HANDLE handle = handleOf( fd );
    FILE_BASIC_INFO basic {};
    if( handle == INVALID_HANDLE_VALUE || !::GetFileInformationByHandleEx( handle, FileBasicInfo, &basic, sizeof( basic ) ) )
    {
        return handle == INVALID_HANDLE_VALUE ? fail( EBADF ) : failLastError();
    }
    const DWORD wanted = ( mode & 0200 ) != 0 ? ( basic.FileAttributes & ~FILE_ATTRIBUTE_READONLY ) : ( basic.FileAttributes | FILE_ATTRIBUTE_READONLY );
    if( wanted == basic.FileAttributes )
    {
        return 0;
    }
    basic.FileAttributes = wanted == 0 ? FILE_ATTRIBUTE_NORMAL : wanted;
    basic.CreationTime.QuadPart = basic.LastAccessTime.QuadPart = basic.LastWriteTime.QuadPart = basic.ChangeTime.QuadPart = 0;   // 0 = unchanged
    return ::SetFileInformationByHandle( handle, FileBasicInfo, &basic, sizeof( basic ) ) ? 0 : failLastError();
}

// ── TRANSITIONAL: locks, pipes and polling delegate until their bodies land ──────────────────────────────────
int flock( int fd, int operation ) { return rw::compat::rw_flock( fd, operation ); }
int pipe( int fds[ 2 ] )           { return ::_pipe( fds, 65536, _O_BINARY | _O_NOINHERIT ); }
int poll( pollfd*, nfds_t, int timeoutMs )
{
    ::Sleep( timeoutMs < 0 ? 0 : static_cast<DWORD>( timeoutMs ) );
    return 0;
}

// ── streams over descriptors and memory ────────────────────────────────────────────────────────────────────
std::FILE* fdopen( int fd, const char* mode ) { return ::_fdopen( fd, mode ); }
int        fileno( std::FILE* stream )        { return ::_fileno( stream ); }

// getline: POSIX's contract (the line including its '\n', NUL-terminated, the buffer grown with realloc; -1 at EOF
// before any byte), read under one stream lock with _getc_nolock — never a locked fgetc per byte.
ssize_t getline( char** line, std::size_t* capacity, std::FILE* stream )
{
    if( line == nullptr || capacity == nullptr || stream == nullptr )
    {
        return fail( EINVAL );
    }
    ::_lock_file( stream );
    std::size_t used   = 0;
    ssize_t     result = -1;
    for( ;; )
    {
        const int c = ::_getc_nolock( stream );
        if( c == EOF )
        {
            result = used == 0 ? -1 : static_cast<ssize_t>( used );
            break;
        }
        if( *line == nullptr || used + 2 > *capacity )
        {
            const std::size_t grown = *capacity < 128 ? 128 : *capacity * 2;
            char* const       next  = static_cast<char*>( std::realloc( *line, grown ) );
            if( next == nullptr )
            {
                errno = ENOMEM;
                break;
            }
            *line     = next;
            *capacity = grown;
        }
        ( *line )[ used++ ] = static_cast<char>( c );
        ( *line )[ used ]   = '\0';
        if( c == '\n' )
        {
            result = static_cast<ssize_t>( used );
            break;
        }
    }
    ::_unlock_file( stream );
    return result;
}

// open_memstream: the UCRT has no memory stream, so the stream is a delete-on-close temporary file (kept in the
// system cache by FILE_ATTRIBUTE_TEMPORARY) and *buffer / *size are published when the caller calls os::fflush or
// os::fclose on it — exactly the two moments POSIX publishes them. The registry below is consulted ONLY by those two
// calls, never by std::fflush / std::fclose, so no other stream pays for it. Carried from PR #44's rw_open_memstream
// (proven by the MCP verb gates on lennix1337's machine), changed to wide temp paths and a registry keyed by stream.
namespace
{
struct MemoryStream
{
    std::FILE*   stream;
    char**       buffer;
    std::size_t* size;
};

std::mutex& memoryStreamMutex()
{
    static std::mutex mutex;
    return mutex;
}

std::vector<MemoryStream>& memoryStreams()
{
    static std::vector<MemoryStream> streams;
    return streams;
}

// Copy the stream's whole content into a fresh *buffer (NUL-terminated) and *size, leaving the position where it was.
int publishMemoryStream( const MemoryStream& record )
{
    const long position = std::ftell( record.stream );
    if( std::fseek( record.stream, 0, SEEK_END ) != 0 )
    {
        return EOF;
    }
    const long length = std::ftell( record.stream );
    if( length < 0 || std::fseek( record.stream, 0, SEEK_SET ) != 0 )
    {
        return EOF;
    }
    char* const published = static_cast<char*>( std::realloc( *record.buffer, static_cast<std::size_t>( length ) + 1 ) );
    if( published == nullptr )
    {
        errno = ENOMEM;
        return EOF;
    }
    const std::size_t got = length > 0 ? std::fread( published, 1, static_cast<std::size_t>( length ), record.stream ) : 0;
    published[ got ] = '\0';
    *record.buffer   = published;
    *record.size     = got;
    return position >= 0 && std::fseek( record.stream, position, SEEK_SET ) == 0 ? 0 : EOF;
}
}   // namespace

std::FILE* open_memstream( char** buffer, std::size_t* size )
{
    if( buffer == nullptr || size == nullptr )
    {
        errno = EINVAL;
        return nullptr;
    }
    wchar_t directory[ MAX_PATH + 2 ];
    wchar_t name[ MAX_PATH + 1 ];
    const DWORD directoryLength = ::GetTempPathW( MAX_PATH + 2, directory );
    if( directoryLength == 0 || directoryLength > MAX_PATH + 1 || ::GetTempFileNameW( directory, L"rwm", 0, name ) == 0 )
    {
        (void)failLastError();
        return nullptr;
    }
    const HANDLE handle = ::CreateFileW( name, GENERIC_READ | GENERIC_WRITE, kShareAll, nullptr, CREATE_ALWAYS,
                                         FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, nullptr );
    if( handle == INVALID_HANDLE_VALUE )
    {
        const DWORD error = ::GetLastError();
        ::DeleteFileW( name );
        (void)failWin32( error );
        return nullptr;
    }
    const int fd = ::_open_osfhandle( reinterpret_cast<intptr_t>( handle ), _O_RDWR | _O_BINARY );
    if( fd < 0 )
    {
        ::CloseHandle( handle );
        return nullptr;
    }
    std::FILE* const stream = ::_fdopen( fd, "w+b" );
    if( stream == nullptr )
    {
        ::_close( fd );
        return nullptr;
    }
    *buffer = static_cast<char*>( std::malloc( 1 ) );
    if( *buffer == nullptr )
    {
        std::fclose( stream );
        errno = ENOMEM;
        return nullptr;
    }
    ( *buffer )[ 0 ] = '\0';
    *size            = 0;
    const std::lock_guard<std::mutex> lock( memoryStreamMutex() );
    memoryStreams().push_back( MemoryStream{ stream, buffer, size } );
    return stream;
}

int fflush( std::FILE* stream )
{
    const int flushed = std::fflush( stream );
    if( flushed != 0 || stream == nullptr )
    {
        return flushed;
    }
    const std::lock_guard<std::mutex> lock( memoryStreamMutex() );
    for( const MemoryStream& record : memoryStreams() )
    {
        if( record.stream == stream )
        {
            return publishMemoryStream( record );
        }
    }
    return 0;
}

int fclose( std::FILE* stream )
{
    int published = 0;
    {
        const std::lock_guard<std::mutex> lock( memoryStreamMutex() );
        std::vector<MemoryStream>&        streams = memoryStreams();
        for( auto it = streams.begin(); it != streams.end(); ++it )
        {
            if( it->stream == stream )
            {
                published = std::fflush( stream ) == 0 ? publishMemoryStream( *it ) : EOF;
                streams.erase( it );
                break;
            }
        }
    }
    const int closed = std::fclose( stream );
    return published != 0 ? published : closed;
}

// ── paths ──────────────────────────────────────────────────────────────────────────────────────────────────
// unlink: DeleteFileW. POSIX removes a file whatever its mode bits, so a read-only file loses the attribute and the
// delete is retried once. With every handle opened FILE_SHARE_DELETE, a file another descriptor holds open is
// unlinked too (POSIX delete semantics are the NTFS default since Windows 10 1903).
int unlink( const char* path )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    if( ::DeleteFileW( native.c_str() ) )
    {
        return 0;
    }
    const DWORD error      = ::GetLastError();
    const DWORD attributes = ::GetFileAttributesW( native.c_str() );
    if( error == ERROR_ACCESS_DENIED && attributes != INVALID_FILE_ATTRIBUTES && ( attributes & FILE_ATTRIBUTE_READONLY ) != 0
        && ( attributes & FILE_ATTRIBUTE_DIRECTORY ) == 0 && ::SetFileAttributesW( native.c_str(), attributes & ~FILE_ATTRIBUTE_READONLY ) )
    {
        if( ::DeleteFileW( native.c_str() ) )
        {
            return 0;
        }
        (void)::SetFileAttributesW( native.c_str(), attributes );
    }
    return failWin32( error );
}

// remove: POSIX's — unlink for a file, rmdir for a directory.
int remove( const char* path )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    const DWORD attributes = ::GetFileAttributesW( native.c_str() );
    if( attributes != INVALID_FILE_ATTRIBUTES && ( attributes & FILE_ATTRIBUTE_DIRECTORY ) != 0 && ( attributes & FILE_ATTRIBUTE_REPARSE_POINT ) == 0 )
    {
        return ::RemoveDirectoryW( native.c_str() ) ? 0 : failLastError();
    }
    return os::unlink( path );
}

// rename: POSIX replaces the destination atomically even while another descriptor holds it open. FileRenameInfoEx
// with REPLACE_IF_EXISTS | POSIX_SEMANTICS (Windows 10 1809+, NTFS) does exactly that, through a handle on the
// source opened without following it (renaming a link renames the link, as POSIX does). Where the file system refuses
// the flags (FAT, an SMB share) MoveFileExW( REPLACE_EXISTING | WRITE_THROUGH ) follows, with a short bounded retry
// on a sharing violation — PR #44's rw_rename retry, without its COPY_ALLOWED (a cross-volume copy is not atomic,
// and POSIX says EXDEV) and with errno set on the final failure.
namespace
{
struct RenameInfo   // FILE_RENAME_INFO's layout, with the Flags member of the union
{
    DWORD   flags;
    HANDLE  rootDirectory;
    DWORD   fileNameLength;
    wchar_t fileName[ 1 ];
};
constexpr int   kFileRenameInfoEx        = 22;           // FILE_INFO_BY_HANDLE_CLASS::FileRenameInfoEx
constexpr DWORD kRenameReplaceIfExists   = 0x00000001;   // FILE_RENAME_FLAG_REPLACE_IF_EXISTS
constexpr DWORD kRenamePosixSemantics    = 0x00000002;   // FILE_RENAME_FLAG_POSIX_SEMANTICS

DWORD renameWithPosixSemantics( LPCWSTR from, LPCWSTR to )
{
    const HANDLE source = ::CreateFileW( from, DELETE | SYNCHRONIZE, kShareAll, nullptr, OPEN_EXISTING,
                                         FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr );
    if( source == INVALID_HANDLE_VALUE )
    {
        return ::GetLastError();
    }
    const std::size_t units = std::wcslen( to );
    const std::size_t bytes = offsetof( RenameInfo, fileName ) + ( units + 1 ) * sizeof( wchar_t );
    std::unique_ptr<std::uint8_t[]> storage( new( std::nothrow ) std::uint8_t[ bytes ]() );
    if( !storage )
    {
        ::CloseHandle( source );
        return ERROR_NOT_ENOUGH_MEMORY;
    }
    auto* const information         = reinterpret_cast<RenameInfo*>( storage.get() );
    information->flags              = kRenameReplaceIfExists | kRenamePosixSemantics;
    information->rootDirectory      = nullptr;
    information->fileNameLength     = static_cast<DWORD>( units * sizeof( wchar_t ) );
    std::memcpy( information->fileName, to, ( units + 1 ) * sizeof( wchar_t ) );
    const BOOL  renamed = ::SetFileInformationByHandle( source, static_cast<FILE_INFO_BY_HANDLE_CLASS>( kFileRenameInfoEx ), information, static_cast<DWORD>( bytes ) );
    const DWORD error   = renamed ? NO_ERROR : ::GetLastError();
    ::CloseHandle( source );
    return error;
}
}   // namespace

int rename( const char* from, const char* to )
{
    const NativePath nativeFrom( from );
    const NativePath nativeTo( to );
    if( !nativeFrom.ok() || !nativeTo.ok() )
    {
        return fail( !nativeFrom.ok() ? nativeFrom.error() : nativeTo.error() );
    }
    DWORD error = renameWithPosixSemantics( nativeFrom.c_str(), nativeTo.c_str() );
    if( error == NO_ERROR )
    {
        return 0;
    }
    if( error != ERROR_INVALID_PARAMETER && error != ERROR_NOT_SUPPORTED && error != ERROR_INVALID_FUNCTION )
    {
        return failWin32( error );
    }
    for( int attempt = 0; attempt < 8; ++attempt )
    {
        if( ::MoveFileExW( nativeFrom.c_str(), nativeTo.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH ) )
        {
            return 0;
        }
        error = ::GetLastError();
        if( error != ERROR_SHARING_VIOLATION && error != ERROR_ACCESS_DENIED )
        {
            break;
        }
        ::Sleep( 5 );
    }
    return failWin32( error );
}

// ── TRANSITIONAL: the cache-directory bodies (mkdir with an owner-only ACL, chmod, the owner read) land next ────
int mkdir( const char* path, mode_t ) { return ::_mkdir( path ); }
int chmod( const char*, mode_t )      { return 0; }

// access: F_OK/R_OK — the path exists; W_OK — and is not a read-only file; X_OK — a directory (search), or a file
// whose extension PATHEXT lists. The UCRT's _access is never called: it rejects X_OK with the invalid-parameter
// handler, which ends the process.
int access( const char* path, int mode )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        return fail( native.error() );
    }
    const DWORD attributes = ::GetFileAttributesW( native.c_str() );
    if( attributes == INVALID_FILE_ATTRIBUTES )
    {
        return failLastError();
    }
    const bool isDirectory = ( attributes & FILE_ATTRIBUTE_DIRECTORY ) != 0;
    if( ( mode & W_OK ) != 0 && !isDirectory && ( attributes & FILE_ATTRIBUTE_READONLY ) != 0 )
    {
        return fail( EACCES );
    }
    if( ( mode & X_OK ) != 0 && !isDirectory )
    {
        std::string pathext = environmentUtf8( L"PATHEXT" );
        if( pathext.empty() )
        {
            pathext = ".COM;.EXE;.BAT;.CMD";
        }
        if( !oswin::extensionInList( path, pathext ) )
        {
            return fail( EACCES );
        }
    }
    return 0;
}

// realpath: the path of the file itself, links resolved (GetFinalPathNameByHandleW on a handle opened through them),
// in the program's spelling — "C:/…" with an upper-case drive, "//server/share/…" for a UNC path. resolved == nullptr
// allocates with malloc, as POSIX.1-2008 specifies.
char* realpath( const char* path, char* resolved )
{
    const NativePath native( path );
    if( !native.ok() )
    {
        errno = native.error();
        return nullptr;
    }
    const HANDLE handle = ::CreateFileW( native.c_str(), FILE_READ_ATTRIBUTES, kShareAll, nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr );
    if( handle == INVALID_HANDLE_VALUE )
    {
        (void)failLastError();
        return nullptr;
    }
    wchar_t                    stackBuffer[ MAX_PATH + 1 ];
    std::unique_ptr<wchar_t[]> heapBuffer;
    wchar_t*                   buffer = stackBuffer;
    DWORD length = ::GetFinalPathNameByHandleW( handle, buffer, MAX_PATH + 1, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS );
    if( length > MAX_PATH )
    {
        heapBuffer.reset( new( std::nothrow ) wchar_t[ length ] );
        buffer = heapBuffer.get();
        length = buffer == nullptr ? 0 : ::GetFinalPathNameByHandleW( handle, buffer, length, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS );
    }
    const DWORD error = ::GetLastError();
    ::CloseHandle( handle );
    if( length == 0 || buffer == nullptr )
    {
        (void)failWin32( buffer == nullptr ? ERROR_NOT_ENOUGH_MEMORY : error );
        return nullptr;
    }
    char* const out = resolved != nullptr ? resolved : static_cast<char*>( std::malloc( PATH_MAX ) );
    if( out == nullptr )
    {
        errno = ENOMEM;
        return nullptr;
    }
    if( programPathInto( std::u16string_view( reinterpret_cast<const char16_t*>( buffer ), length ), out, PATH_MAX ) != 0 )
    {
        if( resolved == nullptr )
        {
            std::free( out );
        }
        return nullptr;
    }
    return out;
}

char* getcwd( char* buf, std::size_t size )
{
    if( buf == nullptr || size == 0 )
    {
        errno = EINVAL;
        return nullptr;
    }
    wchar_t                    stackBuffer[ MAX_PATH + 1 ];
    std::unique_ptr<wchar_t[]> heapBuffer;
    wchar_t*                   buffer = stackBuffer;
    DWORD length = ::GetCurrentDirectoryW( MAX_PATH + 1, buffer );
    if( length > MAX_PATH )
    {
        heapBuffer.reset( new( std::nothrow ) wchar_t[ length ] );
        buffer = heapBuffer.get();
        length = buffer == nullptr ? 0 : ::GetCurrentDirectoryW( length, buffer );
    }
    if( length == 0 )
    {
        (void)failLastError();
        return nullptr;
    }
    const int written = programPathInto( std::u16string_view( reinterpret_cast<const char16_t*>( buffer ), length ), buf, size );
    if( written != 0 )
    {
        if( errno == ENAMETOOLONG )
        {
            errno = ERANGE;   // POSIX getcwd's "buffer too small"
        }
        return nullptr;
    }
    return buf;
}

int setenv( const char* name, const char* value, int overwrite )
{
    if( name == nullptr || value == nullptr || *name == '\0' || std::strchr( name, '=' ) != nullptr )
    {
        return fail( EINVAL );
    }
    bool                 nameOk = false, valueOk = false;
    const std::u16string wideName  = utf16Of( name, nameOk );
    const std::u16string wideValue = utf16Of( value, valueOk );
    if( !nameOk || !valueOk )
    {
        return fail( EILSEQ );
    }
    if( overwrite == 0 && ::_wgetenv( reinterpret_cast<const wchar_t*>( wideName.c_str() ) ) != nullptr )
    {
        return 0;
    }
    const errno_t error = ::_wputenv_s( reinterpret_cast<const wchar_t*>( wideName.c_str() ), reinterpret_cast<const wchar_t*>( wideValue.c_str() ) );
    return error == 0 ? 0 : fail( error );
}

// which: the program a shell would start for `command`. PATH is ';'-separated; an entry that is empty or relative (the
// current directory) is never searched — a checkout carrying its own ripwire.exe or git.exe must not answer; a name
// without an extension is tried with each PATHEXT extension, one with an extension as given (if PATHEXT lists it).
// The answer is in the program's spelling.
std::string which( std::string_view command )
{
    if( command.empty() || command.find( '\0' ) != std::string_view::npos )
    {
        return {};
    }
    std::string pathext = environmentUtf8( L"PATHEXT" );
    if( pathext.empty() )
    {
        pathext = ".COM;.EXE;.BAT;.CMD";
    }
    const auto isFile = []( const std::string& candidate )
    {
        const NativePath native( candidate.c_str() );
        const DWORD      attributes = native.ok() ? ::GetFileAttributesW( native.c_str() ) : INVALID_FILE_ATTRIBUTES;
        return attributes != INVALID_FILE_ATTRIBUTES && ( attributes & FILE_ATTRIBUTE_DIRECTORY ) == 0;
    };
    const auto resolve = [ & ]( std::string base ) -> std::string
    {
        oswin::normalizePathArgInPlace( base.data() );
        if( oswin::hasExtension( base ) )
        {
            return oswin::extensionInList( base, pathext ) && isFile( base ) ? base : std::string();
        }
        std::size_t at = 0;
        while( at <= pathext.size() )
        {
            const std::string_view extension = oswin::nextPathListEntry( pathext, at );
            if( !extension.empty() && isFile( base + std::string( extension ) ) )
            {
                return base + std::string( extension );
            }
        }
        return {};
    };
    if( command.find_first_of( "/\\:" ) != std::string_view::npos )
    {
        return resolve( std::string( command ) );
    }
    const std::string path = environmentUtf8( L"PATH" );
    std::size_t       at   = 0;
    while( at <= path.size() )
    {
        std::string_view directory = oswin::nextPathListEntry( path, at );
        if( directory.empty() || !oswin::isAbsoluteNativePath( directory ) )
        {
            continue;
        }
        while( directory.size() > 3 && ( directory.back() == '/' || directory.back() == '\\' ) )
        {
            directory.remove_suffix( 1 );
        }
        std::string found = resolve( std::string( directory ) + "/" + std::string( command ) );
        if( !found.empty() )
        {
            return found;
        }
    }
    return {};
}

// ── process start and path intake ──────────────────────────────────────────────────────────────────────────
void normalize_path_arg( char* text )
{
    oswin::normalizePathArgInPlace( text );
}

void init_process( int& argc, char**& argv )
{
    static_assert( sizeof( wchar_t ) == sizeof( char16_t ), "the Windows ABI's wchar_t is UTF-16" );

    // stdout carries XML/JSON bytes and stdin carries MCP requests: no CRLF translation in either direction.
    (void)::_setmode( ::_fileno( stdin ), _O_BINARY );
    (void)::_setmode( ::_fileno( stdout ), _O_BINARY );
    (void)::_setmode( ::_fileno( stderr ), _O_BINARY );

    // argv as UTF-8, from the UTF-16 command line: the CRT's narrow argv is in the ANSI code page, which is UTF-8 only
    // when the manifest's activeCodePage took effect. An argument that is not valid UTF-16 leaves the CRT's argv in
    // place — every argument, so the indices stay aligned.
    int                 wideCount = 0;
    const LPWSTR* const wideArgv  = ::CommandLineToArgvW( ::GetCommandLineW(), &wideCount );
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

    // the path-valued environment the program reads, in its own spelling. A variable whose spelling is already right is
    // not rewritten, so a child process inherits exactly what this one was given unless the spelling had to change.
    static constexpr const wchar_t* kPathVariables[] = { L"HOME", L"TMPDIR", L"XDG_CACHE_HOME", L"CODEX_HOME", L"CLAUDE_CONFIG_DIR" };
    for( const wchar_t* const name : kPathVariables )
    {
        std::string value = environmentUtf8( name );
        if( value.empty() )
        {
            continue;
        }
        const std::string before = value;
        oswin::normalizePathArgInPlace( value.data() );
        bool                 ok = false;
        const std::u16string programSpelling = utf16Of( value, ok );
        if( value != before && ok )
        {
            (void)::_wputenv_s( name, reinterpret_cast<const wchar_t*>( programSpelling.c_str() ) );
        }
    }
}

// exepath: GetModuleFileNameW, grown past MAX_PATH when the answer did not fit, in the program's spelling.
int exepath( char* buf, std::size_t bufCount )
{
    wchar_t                    stackBuffer[ MAX_PATH + 1 ];
    std::unique_ptr<wchar_t[]> heapBuffer;
    wchar_t*                   buffer   = stackBuffer;
    DWORD                      capacity = MAX_PATH + 1;
    DWORD                      length   = ::GetModuleFileNameW( nullptr, buffer, capacity );
    while( length == capacity && capacity < 32768 )
    {
        capacity *= 4;
        heapBuffer.reset( new( std::nothrow ) wchar_t[ capacity ] );
        buffer = heapBuffer.get();
        length = buffer == nullptr ? 0 : ::GetModuleFileNameW( nullptr, buffer, capacity );
    }
    if( length == 0 || length == capacity )
    {
        return -1;
    }
    return programPathInto( std::u16string_view( reinterpret_cast<const char16_t*>( buffer ), length ), buf, bufCount );
}

// ── time ───────────────────────────────────────────────────────────────────────────────────────────────────
// nanosleep: Sleep in whole milliseconds, rounded up so a nonzero request never becomes a zero sleep; never interrupted.
int nanosleep( const ::timespec* request, ::timespec* remaining )
{
    if( request == nullptr || request->tv_sec < 0 || request->tv_nsec < 0 || request->tv_nsec >= 1000000000L )
    {
        return fail( EINVAL );
    }
    const std::uint64_t milliseconds = static_cast<std::uint64_t>( request->tv_sec ) * 1000u + ( static_cast<std::uint64_t>( request->tv_nsec ) + 999999u ) / 1000000u;
    ::Sleep( milliseconds > 0xFFFFFFFEu ? 0xFFFFFFFEu : static_cast<DWORD>( milliseconds ) );
    if( remaining != nullptr )
    {
        *remaining = ::timespec{};
    }
    return 0;
}

std::tm* localtime_r( const std::time_t* time, std::tm* result ) { return ::localtime_s( result, time ) == 0 ? result : nullptr; }

// ── TRANSITIONAL: processes delegate until their bodies land ────────────────────────────────────────────────
pid_t      getpid()                                        { return static_cast<pid_t>( ::GetCurrentProcessId() ); }
uid_t      getuid()                                        { return 1000; }
int        kill( pid_t, int )                              { return fail( ENOSYS ); }
pid_t      waitpid( pid_t, int*, int )                     { return fail( ENOSYS ); }
std::FILE* popen( const char* command, const char* mode )  { return rw::compat::rw_popen( command, mode ); }
int        pclose( std::FILE* stream )                     { return rw::compat::rw_pclose( stream ); }
int        system( const char* command )                   { return rw::compat::rw_system( command ); }
pid_t      spawn_sh( const std::string&, const int[ 2 ] )  { return fail( ENOSYS ); }

// ── threads ────────────────────────────────────────────────────────────────────────────────────────────────
pthread_t     pthread_self() { return ::GetCurrentThreadId(); }
std::uint64_t gettid()       { return ::GetCurrentThreadId(); }

// pthread_main_np: the thread that first asks is taken as the initial one — the same latch POSIX platforms without the
// call use. Its only caller asks from main's thread before any worker starts.
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

// ── TRANSITIONAL: sockets (a SOCKET narrowed to int, as the compat layer's callers did) ───────────────────────
int     socket( int domain, int type, int protocol )                  { return static_cast<int>( ::socket( domain, type, protocol ) ); }
int     setsockopt( int fd, int level, int name, const void* value, socklen_t length ) { return rw::compat::rw_setsockopt( static_cast<SOCKET>( fd ), level, name, value, length ); }
int     bind( int fd, const ::sockaddr* address, socklen_t length )   { return ::bind( static_cast<SOCKET>( fd ), address, length ); }
int     listen( int fd, int backlog )                                 { return ::listen( static_cast<SOCKET>( fd ), backlog ); }
int     accept( int fd, ::sockaddr* address, socklen_t* length )      { return static_cast<int>( ::accept( static_cast<SOCKET>( fd ), address, length ) ); }
ssize_t recv( int fd, void* buf, std::size_t count, int flags )       { return ::recv( static_cast<SOCKET>( fd ), static_cast<char*>( buf ), static_cast<int>( count > INT_MAX ? INT_MAX : count ), flags ); }
ssize_t send( int fd, const void* buf, std::size_t count, int flags ) { return ::send( static_cast<SOCKET>( fd ), static_cast<const char*>( buf ), static_cast<int>( count > INT_MAX ? INT_MAX : count ), flags ); }
int     inet_pton( int family, const char* text, void* address )      { return ::inet_pton( family, text, address ); }
int     setsockopt_nosigpipe( int, const void*, socklen_t )           { return 0; }

}   // namespace rw::os
