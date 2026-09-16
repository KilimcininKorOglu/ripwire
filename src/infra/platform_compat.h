#pragma once

#ifndef RW_PLATFORM_HAS_KQUEUE
  #if !defined( _WIN32 ) && ( defined( __APPLE__ ) || defined( __FreeBSD__ ) || defined( __OpenBSD__ ) || defined( __NetBSD__ ) || defined( __DragonFly__ ) )
    #define RW_PLATFORM_HAS_KQUEUE 1
  #else
    #define RW_PLATFORM_HAS_KQUEUE 0
  #endif
#endif

#if RW_PLATFORM_HAS_KQUEUE && !defined( _WIN32 )
  #include <sys/event.h>
#endif

#if defined(_WIN32) || defined(_MSC_VER)

  #ifndef _CRT_SECURE_NO_WARNINGS
    #define _CRT_SECURE_NO_WARNINGS
  #endif
  #ifndef _CRT_NONSTDC_NO_DEPRECATE
    #define _CRT_NONSTDC_NO_DEPRECATE
  #endif

  #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
  #endif
  #ifndef NOMINMAX
    #define NOMINMAX
  #endif

  #include <winsock2.h>
  #include <ws2tcpip.h>
  #include <windows.h>
  #include <aclapi.h>
  #include <sddl.h>

  #ifdef near
    #undef near
  #endif
  #ifdef far
    #undef far
  #endif

  #include <io.h>
  #include <direct.h>
  #include <process.h>
  #include <basetsd.h>
  #include <fcntl.h>
  #include <sys/stat.h>
  #include <stdio.h>
  #include <cstdio>
  #include <stdlib.h>

  #ifndef PATH_MAX
    #define PATH_MAX 4096
  #endif

  #ifndef O_CLOEXEC
    #ifdef _O_NOINHERIT
      #define O_CLOEXEC _O_NOINHERIT
    #else
      #define O_CLOEXEC 0
    #endif
  #endif

  // The upstream code uses POSIX descriptor calls for bounded regular-file reads. Keep the calls available
  // on MSVC through the CRT, but do not invent an O_NOFOLLOW value: pathguard.h has the real Win32
  // FILE_FLAG_OPEN_REPARSE_POINT implementation for the security-sensitive opens.
  #ifndef O_NONBLOCK
    #define O_NONBLOCK 0
  #endif
  #ifndef F_GETFL
    #define F_GETFL 3
  #endif
  #ifndef F_SETFL
    #define F_SETFL 4
  #endif
  #ifndef open
    #define open _open
  #endif
  #ifndef fdopen
    #define fdopen _fdopen
  #endif
  #ifndef S_ISREG
    #define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
  #endif
  #ifndef S_ISDIR
    #define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
  #endif
  #ifndef S_ISLNK
    #define S_ISLNK(m) 0
  #endif

  #ifndef LOCK_SH
    #define LOCK_SH 1
    #define LOCK_EX 2
    #define LOCK_NB 4
    #define LOCK_UN 8
  #endif

#ifdef __cplusplus

  #include <cstddef>
  #include <cstdint>
  #include <cerrno>
  #include <cstring>
  #include <algorithm>
  #include <string>
  #include <string_view>
  #include <thread>
  #include <vector>

  namespace rw::compat
  {
  /// Returns the processors this process can actually run on, not just the machine total.
  /// Windows' std::thread::hardware_concurrency() reports the system count even after a caller
  /// narrows the process affinity mask; using it for worker pools silently oversubscribes constrained
  /// jobs and makes Windows measurements incomparable with a cgroup-limited POSIX process.
  inline unsigned rw_effective_hardware_concurrency() noexcept
  {
#if defined( _WIN32 )
      DWORD_PTR processMask = 0;
      DWORD_PTR systemMask  = 0;
      if( ::GetProcessAffinityMask( ::GetCurrentProcess(), &processMask, &systemMask ) && processMask != 0 )
      {
          unsigned count = 0;
          for( DWORD_PTR mask = processMask; mask != 0; mask >>= 1 )
          {
              count += static_cast<unsigned>( mask & 1u );
          }
          if( count != 0 )
          {
              return count;
          }
      }
#endif
      const unsigned hardware = std::thread::hardware_concurrency();
      return hardware == 0 ? 1u : hardware;
  }

  inline std::uint64_t rw_profile_thread_id() noexcept
  {
      return static_cast<std::uint64_t>( ::GetCurrentThreadId() );
  }

  inline bool rw_profile_is_initial_thread() noexcept
  {
      static const std::thread::id firstCaller = std::this_thread::get_id();
      return std::this_thread::get_id() == firstCaller;
  }

  inline void rw_profile_copy_thread_name( char* buffer, std::size_t buffer_count ) noexcept
  {
      if( buffer != nullptr && buffer_count > 0 )
      {
          buffer[ 0 ] = '\0';
      }
  }

  std::string rw_windows_path_from_msys( std::string_view path );

  inline std::string rw_native_path( std::string_view path )
  {
      std::string native = rw_windows_path_from_msys( path );
      for( char& c : native )
      {
          if( c == '\\' )
          {
              c = '/';
          }
      }
      return native;
  }

  inline bool rw_path_char_equal( char a, char b ) noexcept
  {
      if( a == '\\' ) { a = '/'; }
      if( b == '\\' ) { b = '/'; }
      if( a >= 'A' && a <= 'Z' ) { a = static_cast<char>( a - 'A' + 'a' ); }
      if( b >= 'A' && b <= 'Z' ) { b = static_cast<char>( b - 'A' + 'a' ); }
      return a == b;
  }

  inline bool rw_drive_letter_matches( std::string_view path, std::string_view prefix ) noexcept
  {
      if( path.size() < 2 || prefix.size() < 2 || path[ 1 ] != ':' || prefix[ 1 ] != ':' )
      {
          return false;
      }
      const auto isLetter = []( char c ) noexcept
      {
          return ( c >= 'A' && c <= 'Z' ) || ( c >= 'a' && c <= 'z' );
      };
      return isLetter( path[ 0 ] ) && isLetter( prefix[ 0 ] ) && rw_path_char_equal( path[ 0 ], prefix[ 0 ] );
  }

  // Git Bash can pass a drive-rooted option value as /c/... even when the caller
  // launches the native executable. The parser keeps string_views into argv, so
  // normalize only the equal-length drive prefix in place; longer /tmp mappings
  // are handled by the caller's native temporary directory.
  inline void rw_normalize_msys_drive_paths_in_place( char* text ) noexcept
  {
#if defined( _WIN32 )
      if( text == nullptr )
      {
          return;
      }
      const std::size_t textLength = std::strlen( text );
      for( std::size_t offset = 0; offset < textLength; ++offset )
      {
          char* p = text + offset;
          const bool boundary = ( p == text || p[ -1 ] == ',' || p[ -1 ] == ':' );
          const bool hasDriveLetter = offset + 1 < textLength;
          const char drive = hasDriveLetter ? p[ 1 ] : 0;
          const bool driveLetter = hasDriveLetter && ( ( drive >= 'a' && drive <= 'z' ) || ( drive >= 'A' && drive <= 'Z' ) );
          const bool driveTerminated = offset + 2 == textLength
                                    || ( offset + 2 < textLength && p[ 2 ] == '/' );
          if( boundary && p[ 0 ] == '/' && driveLetter && driveTerminated )
          {
              p[ 0 ] = drive >= 'a' && drive <= 'z' ? static_cast<char>( drive - ( 'a' - 'A' ) ) : drive;
              p[ 1 ] = ':';
          }
      }
#else
      (void)text;
#endif
  }

  /// Converts the application's UTF-8 paths to the native Windows wide spelling.
  /// Invalid UTF-8 falls back to the active code page to preserve the CRT's historical behavior.
  inline std::wstring rw_utf8_to_wide( std::string_view text )
  {
      if( text.empty() )
      {
          return {};
      }
      const int utf8Length = ::MultiByteToWideChar( CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>( text.size() ), nullptr, 0 );
      const UINT codePage = utf8Length > 0 ? CP_UTF8 : CP_ACP;
      const DWORD flags = utf8Length > 0 ? MB_ERR_INVALID_CHARS : 0;
      const int length = ::MultiByteToWideChar( codePage, flags, text.data(), static_cast<int>( text.size() ), nullptr, 0 );
      if( length <= 0 )
      {
          return {};
      }
      std::wstring result( static_cast<std::size_t>( length ), L'\0' );
      if( ::MultiByteToWideChar( codePage, flags, text.data(), static_cast<int>( text.size() ), result.data(), length ) != length )
      {
          return {};
      }
      return result;
  }

  inline std::string rw_wide_to_utf8( std::wstring_view text )
  {
      if( text.empty() )
      {
          return {};
      }
      const int length = ::WideCharToMultiByte( CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>( text.size() ), nullptr, 0, nullptr, nullptr );
      if( length <= 0 )
      {
          return {};
      }
      std::string result( static_cast<std::size_t>( length ), '\0' );
      if( ::WideCharToMultiByte( CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>( text.size() ), result.data(), length, nullptr, nullptr ) != length )
      {
          return {};
      }
      return result;
  }

  /// Checks a directory path without following a Windows reparse point at any component.
  inline bool rw_windows_directory_is_safe( std::string_view path ) noexcept
  {
      const std::wstring widePath = rw_utf8_to_wide( rw_windows_path_from_msys( path ) );
      if( widePath.empty() )
      {
          return false;
      }

      std::wstring absolute( 32768, L'\0' );
      DWORD fullLength = ::GetFullPathNameW( widePath.c_str(), static_cast<DWORD>( absolute.size() ), absolute.data(), nullptr );
      if( fullLength == 0 )
      {
          return false;
      }
      if( fullLength >= absolute.size() )
      {
          absolute.resize( static_cast<std::size_t>( fullLength ) + 1 );
          fullLength = ::GetFullPathNameW( widePath.c_str(), static_cast<DWORD>( absolute.size() ), absolute.data(), nullptr );
          if( fullLength == 0 || fullLength >= absolute.size() )
          {
              return false;
          }
      }
      absolute.resize( fullLength );

      const auto inspect = []( const std::wstring& component ) noexcept
      {
          const HANDLE handle = ::CreateFileW( component.c_str(), FILE_READ_ATTRIBUTES,
                                               FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                                               FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_OPEN_NO_RECALL | FILE_FLAG_BACKUP_SEMANTICS,
                                               nullptr );
          if( handle == INVALID_HANDLE_VALUE )
          {
              return false;
          }
          FILE_ATTRIBUTE_TAG_INFO info{};
          const BOOL inspected = ::GetFileInformationByHandleEx( handle, FileAttributeTagInfo, &info, sizeof( info ) );
          ::CloseHandle( handle );
          return inspected != FALSE && ( info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY ) != 0
              && ( info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT ) == 0;
      };

      std::wstring volume( 32768, L'\0' );
      const DWORD volumeLength = ::GetVolumePathNameW( absolute.c_str(), volume.data(), static_cast<DWORD>( volume.size() ) );
      if( volumeLength == 0 || volumeLength >= volume.size() )
      {
          return false;
      }
      const std::size_t finalSeparator = absolute.find_last_of( L"\\/" );
      for( std::size_t separator = absolute.find_first_of( L"\\/", volumeLength );
           separator != std::wstring::npos && separator < finalSeparator;
           separator = absolute.find_first_of( L"\\/", separator + 1 ) )
      {
          if( !inspect( absolute.substr( 0, separator ) ) )
          {
              return false;
          }
      }
      return inspect( absolute );
  }

  inline HANDLE rw_windows_open_safe_directory( std::string_view path ) noexcept
  {
      if( !rw_windows_directory_is_safe( path ) )
      {
          return INVALID_HANDLE_VALUE;
      }
      const std::wstring widePath = rw_utf8_to_wide( rw_windows_path_from_msys( path ) );
      if( widePath.empty() )
      {
          return INVALID_HANDLE_VALUE;
      }
      const HANDLE handle = ::CreateFileW( widePath.c_str(), READ_CONTROL | WRITE_DAC | FILE_READ_ATTRIBUTES,
                                           FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                                           FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_OPEN_NO_RECALL | FILE_FLAG_BACKUP_SEMANTICS,
                                           nullptr );
      if( handle == INVALID_HANDLE_VALUE )
      {
          return INVALID_HANDLE_VALUE;
      }
      FILE_ATTRIBUTE_TAG_INFO info{};
      const BOOL inspected = ::GetFileInformationByHandleEx( handle, FileAttributeTagInfo, &info, sizeof( info ) );
      if( inspected == FALSE || ( info.FileAttributes & FILE_ATTRIBUTE_DIRECTORY ) == 0
          || ( info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT ) != 0 )
      {
          ::CloseHandle( handle );
          return INVALID_HANDLE_VALUE;
      }
      return handle;
  }

  inline std::string rw_resolve_executable( std::string_view command );
  std::string rw_posix_shell_path();
  bool rw_windows_temporary_environment_is_long() noexcept;
  struct RwWindowsTemporaryEnvironmentScope
  {
      void* impl = nullptr;
      RwWindowsTemporaryEnvironmentScope();
      ~RwWindowsTemporaryEnvironmentScope();
      bool active() const noexcept;
  };

  inline bool rw_command_available( std::string_view command )
  {
      return !rw_resolve_executable( command ).empty();
  }

  inline bool rw_set_environment( const char* key, const char* value ) noexcept
  {
      return key != nullptr && value != nullptr && ::_putenv_s( key, value ) == 0;
  }

  inline int rw_binary_open_flags( int flags ) noexcept
  {
      return flags | O_BINARY;
  }

  inline std::string rw_resolve_executable( std::string_view command )
  {
      if( command.empty() )
      {
          return {};
      }
      const std::wstring wideCommand = rw_utf8_to_wide( rw_native_path( command ) );
      if( wideCommand.empty() )
      {
          return {};
      }
      const std::size_t separator = wideCommand.find_last_of( L"\\/" );
      const bool hasExtension = wideCommand.find( L'.', separator == std::wstring::npos ? 0 : separator + 1 ) != std::wstring::npos;
      constexpr const wchar_t* kExtensions[] = { L"", L".exe", L".cmd", L".bat" };
      const auto executable = []( const std::wstring& path ) noexcept
      {
          const DWORD attributes = ::GetFileAttributesW( path.c_str() );
          if( attributes == INVALID_FILE_ATTRIBUTES || ( attributes & FILE_ATTRIBUTE_DIRECTORY ) != 0 )
          {
              return false;
          }
          const HANDLE handle = ::CreateFileW( path.c_str(), FILE_EXECUTE | FILE_READ_ATTRIBUTES,
                                               FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                                               FILE_ATTRIBUTE_NORMAL, nullptr );
          if( handle == INVALID_HANDLE_VALUE )
          {
              return false;
          }
          ::CloseHandle( handle );
          return true;
      };
      const auto checkCandidate = [ & ]( const std::wstring& candidate ) -> std::string
      {
          return executable( candidate ) ? rw_wide_to_utf8( candidate ) : std::string();
      };
      wchar_t resolved[ 32768 ];
      if( separator != std::wstring::npos || ( wideCommand.size() >= 2 && wideCommand[ 1 ] == L':' ) )
      {
          for( const wchar_t* extension : kExtensions )
          {
              if( hasExtension && extension[ 0 ] != L'\0' )
              {
                  break;
              }
              if( const std::string path = checkCandidate( wideCommand + extension ); !path.empty() )
              {
                  return path;
              }
          }
          return {};
      }

      std::wstring pathList( 32768, L'\0' );
      DWORD pathLength = ::GetEnvironmentVariableW( L"PATH", pathList.data(), static_cast<DWORD>( pathList.size() ) );
      if( pathLength == 0 )
      {
          return {};
      }
      if( pathLength >= pathList.size() )
      {
          pathList.resize( static_cast<std::size_t>( pathLength ) + 1 );
          pathLength = ::GetEnvironmentVariableW( L"PATH", pathList.data(), static_cast<DWORD>( pathList.size() ) );
          if( pathLength == 0 || pathLength >= pathList.size() )
          {
              return {};
          }
      }
      pathList.resize( pathLength );
      const bool semicolonSeparated = pathList.find( L';' ) != std::wstring::npos;
      for( std::size_t at = 0; at <= pathList.size(); )
      {
          std::size_t split = pathList.size();
          if( semicolonSeparated )
          {
              const std::size_t found = pathList.find( L';', at );
              if( found != std::wstring::npos )
              {
                  split = found;
              }
          }
          else
          {
              for( std::size_t i = at; i < pathList.size(); ++i )
              {
                  const bool upperDrive = pathList[ at ] >= L'A' && pathList[ at ] <= L'Z';
                  const bool lowerDrive = pathList[ at ] >= L'a' && pathList[ at ] <= L'z';
                  const bool driveColon = i == at + 1 && ( upperDrive || lowerDrive );
                  if( pathList[ i ] == L':' && !driveColon )
                  {
                      split = i;
                      break;
                  }
              }
          }
          const std::wstring pathEntry = pathList.substr( at, split - at );
          const std::string pathEntryUtf8 = rw_wide_to_utf8( pathEntry.empty() ? std::wstring_view( L"." ) : std::wstring_view( pathEntry ) );
          const std::wstring nativeEntry = rw_utf8_to_wide( rw_native_path( pathEntryUtf8 ) );
          if( !nativeEntry.empty() )
          {
              for( const wchar_t* extension : kExtensions )
              {
                  if( hasExtension && extension[ 0 ] != L'\0' )
                  {
                      break;
                  }
                  const std::wstring candidate = wideCommand + extension;
                  const DWORD length = ::SearchPathW( nativeEntry.c_str(), candidate.c_str(), nullptr,
                                                      static_cast<DWORD>( std::size( resolved ) ), resolved, nullptr );
                  if( length > 0 && length < std::size( resolved ) )
                  {
                      const std::wstring found( resolved, length );
                      if( const std::string path = checkCandidate( found ); !path.empty() )
                      {
                          return path;
                      }
                  }
              }
          }
          if( split == pathList.size() )
          {
              break;
          }
          at = split + 1;
      }
      return {};
  }

  /// Opens a UTF-8 path using the native wide CRT on Windows, after accepting Git Bash's /drive and /tmp spellings.
  inline std::FILE* rw_fopen_utf8( std::string_view path, std::string_view mode )
  {
      const std::wstring widePath = rw_utf8_to_wide( rw_windows_path_from_msys( path ) );
      const std::wstring wideMode = rw_utf8_to_wide( mode );
      return widePath.empty() || wideMode.empty() ? nullptr : ::_wfopen( widePath.c_str(), wideMode.c_str() );
  }

  struct RwFileTimes
  {
      long long mtimeNs;
      long long sizeBytes;
      long long changeTimeNs;
  };

  /// Reads the Windows file size, write time and change time through one native handle.
  inline RwFileTimes rw_file_times_of( const std::string& path ) noexcept
  {
      const std::wstring widePath = rw_utf8_to_wide( rw_windows_path_from_msys( path ) );
      if( widePath.empty() )
      {
          return { -1, -1, -1 };
      }
      const HANDLE handle = ::CreateFileW( widePath.c_str(), FILE_READ_ATTRIBUTES,
                                           FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                                           FILE_FLAG_BACKUP_SEMANTICS, nullptr );
      if( handle == INVALID_HANDLE_VALUE )
      {
          return { -1, -1, -1 };
      }
      FILE_BASIC_INFO          basic{};
      BY_HANDLE_FILE_INFORMATION standard{};
      const bool ok = ::GetFileInformationByHandleEx( handle, FileBasicInfo, &basic, sizeof( basic ) ) != 0
                   && ::GetFileInformationByHandle( handle, &standard ) != 0;
      ::CloseHandle( handle );
      if( !ok )
      {
          return { -1, -1, -1 };
      }
      constexpr long long kWindowsToUnixEpoch100ns = 116444736000000000LL;
      const auto toUnixNs = []( LARGE_INTEGER value ) noexcept -> long long
      {
          if( value.QuadPart < kWindowsToUnixEpoch100ns )
          {
              return -1;
          }
          return ( value.QuadPart - kWindowsToUnixEpoch100ns ) * 100LL;
      };
      const long long size = ( static_cast<long long>( standard.nFileSizeHigh ) << 32 ) | standard.nFileSizeLow;
      LARGE_INTEGER lastWrite{};
      lastWrite.LowPart  = standard.ftLastWriteTime.dwLowDateTime;
      lastWrite.HighPart = standard.ftLastWriteTime.dwHighDateTime;
      return { toUnixNs( lastWrite ), size, toUnixNs( basic.ChangeTime ) };
  }

  inline bool rw_is_regular_file( std::string_view path ) noexcept
  {
      const std::wstring widePath = rw_utf8_to_wide( rw_windows_path_from_msys( path ) );
      if( widePath.empty() )
      {
          return false;
      }
      const DWORD attributes = ::GetFileAttributesW( widePath.c_str() );
      return attributes != INVALID_FILE_ATTRIBUTES && ( attributes & FILE_ATTRIBUTE_DIRECTORY ) == 0;
  }

  inline bool rw_path_exists( std::string_view path ) noexcept
  {
      const std::wstring widePath = rw_utf8_to_wide( rw_native_path( path ) );
      return !widePath.empty() && ::GetFileAttributesW( widePath.c_str() ) != INVALID_FILE_ATTRIBUTES;
  }

  inline bool rw_is_symlink( std::string_view path ) noexcept
  {
      const std::wstring widePath = rw_utf8_to_wide( rw_native_path( path ) );
      if( widePath.empty() )
      {
          return false;
      }
      const HANDLE handle = ::CreateFileW( widePath.c_str(), 0,
                                           FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                                           FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_OPEN_NO_RECALL | FILE_FLAG_BACKUP_SEMANTICS,
                                           nullptr );
      if( handle == INVALID_HANDLE_VALUE )
      {
          return false;
      }
      BY_HANDLE_FILE_INFORMATION info{};
      const bool reparse = ::GetFileInformationByHandle( handle, &info ) != 0
                        && ( info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT ) != 0;
      ::CloseHandle( handle );
      return reparse;
  }

  inline std::int64_t rw_write_fd( int fd, const char* data, std::size_t byte_count ) noexcept
  {
      const unsigned int count = byte_count > 1u << 20 ? 1u << 20 : static_cast<unsigned int>( byte_count );
      return static_cast<std::int64_t>( ::_write( fd, data, count ) );
  }

  inline int rw_close_fd( int fd ) noexcept
  {
      return ::_close( fd );
  }

  struct RwFileIdentity
  {
      bool          valid;
      std::uint64_t volumeId;
      std::uint64_t fileId;
      long long     mtimeSeconds;
      long long     sizeBytes;
  };

  inline RwFileIdentity rw_file_identity_of( std::string_view path ) noexcept
  {
      const std::wstring widePath = rw_utf8_to_wide( rw_windows_path_from_msys( path ) );
      if( widePath.empty() )
      {
          return { false, 0, 0, -1, -1 };
      }
      const HANDLE handle = ::CreateFileW( widePath.c_str(), FILE_READ_ATTRIBUTES,
                                           FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                                           FILE_FLAG_BACKUP_SEMANTICS, nullptr );
      if( handle == INVALID_HANDLE_VALUE )
      {
          return { false, 0, 0, -1, -1 };
      }
      BY_HANDLE_FILE_INFORMATION info{};
      const BOOL ok = ::GetFileInformationByHandle( handle, &info );
      ::CloseHandle( handle );
      if( !ok )
      {
          return { false, 0, 0, -1, -1 };
      }
      ULARGE_INTEGER writeTime{};
      writeTime.LowPart  = info.ftLastWriteTime.dwLowDateTime;
      writeTime.HighPart = info.ftLastWriteTime.dwHighDateTime;
      constexpr std::uint64_t kWindowsToUnixEpoch100ns = 116444736000000000ull;
      const long long mtime = writeTime.QuadPart < kWindowsToUnixEpoch100ns
                            ? -1
                            : static_cast<long long>( ( writeTime.QuadPart - kWindowsToUnixEpoch100ns ) / 10000000ull );
      const std::uint64_t fileId = ( static_cast<std::uint64_t>( info.nFileIndexHigh ) << 32 ) | info.nFileIndexLow;
      const long long size = ( static_cast<long long>( info.nFileSizeHigh ) << 32 ) | info.nFileSizeLow;
      return { true, info.dwVolumeSerialNumber, fileId, mtime, size };
  }

  inline int rw_fseek( std::FILE* stream, std::int64_t offset, int origin ) noexcept
  {
      return stream == nullptr ? -1 : ::_fseeki64( stream, offset, origin );
  }

  inline std::int64_t rw_ftell( std::FILE* stream ) noexcept
  {
      return stream == nullptr ? -1 : static_cast<std::int64_t>( ::_ftelli64( stream ) );
  }

  inline std::vector<std::uint8_t> rw_read_regular_file( std::string_view path, std::size_t max_bytes )
  {
      std::vector<std::uint8_t> bytes;
      std::FILE* file = rw_fopen_utf8( path, "rb" );
      if( file == nullptr || rw_fseek( file, 0, SEEK_END ) != 0 )
      {
          if( file != nullptr ) { std::fclose( file ); }
          return bytes;
      }
      const std::int64_t size = rw_ftell( file );
      if( size <= 0 || static_cast<std::uint64_t>( size ) > max_bytes )
      {
          std::fclose( file );
          return bytes;
      }
      std::rewind( file );
      bytes.resize( static_cast<std::size_t>( size ) );
      const std::size_t read = std::fread( bytes.data(), 1, bytes.size(), file );
      std::fclose( file );
      if( read != bytes.size() )
      {
          bytes.clear();
      }
      return bytes;
  }

  inline unsigned rw_document_worker_count( unsigned hardware, std::size_t item_count ) noexcept
  {
      unsigned count = hardware == 0 ? 1u : hardware;
      if( item_count < count )
      {
          count = static_cast<unsigned>( item_count );
      }
      return count > 8u ? 8u : count;
  }

  /// Keeps XML/stdout byte streams from receiving CRT newline translation on Windows.
  inline void rw_set_stdout_binary() noexcept
  {
      (void)::_setmode( ::_fileno( stdout ), _O_BINARY );
      (void)::_setmode( ::_fileno( stderr ), _O_BINARY );
  }
  }

  /// MSVC's _fstat64 uses its private _stat64 layout, while the portable sources expose struct stat.
  /// Copy the fields consumed by the descriptor callers instead of aliasing incompatible objects.
  inline int rw_fstat( int fd, struct stat* out ) noexcept
  {
      struct _stat64 native{};
      if( ::_fstat64( fd, &native ) != 0 )
      {
          return -1;
      }
      out->st_mode = native.st_mode;
      out->st_size = native.st_size;
      return 0;
  }
  #ifndef fstat
    #define fstat rw_fstat
  #endif

  /// Regular Windows files never expose POSIX descriptor status flags; the SCIP reader only uses these
  /// operations to clear O_NONBLOCK after its non-blocking probe, so both operations are safe no-ops.
  inline int rw_fcntl( int, int command, int /*flags*/ = 0 ) noexcept
  {
      if( command == F_GETFL || command == F_SETFL )
      {
          return 0;
      }
      errno = EINVAL;
      return -1;
  }
  #ifndef fcntl
    #define fcntl rw_fcntl
  #endif

  using ssize_t = SSIZE_T;

  namespace rw::compat
  {
      int rw_flock( int fd, int operation ) noexcept;
      ssize_t rw_pread( int fd, void* buf, std::size_t count, std::uint64_t offset ) noexcept;
      char* rw_realpath( const char* path, char* resolved_path ) noexcept;
      /// Runs the fixed Git ignore query without starting a shell on Windows. Returns the Git exit code,
      /// -1 for a process/pipe failure, and -2 when maxBytes was exceeded while the child was drained.
      int rw_git_ignore_probe( std::string_view root_dir, std::string& output, std::size_t max_bytes );
      std::FILE* rw_popen( const char* command, const char* mode );
      int rw_pclose( std::FILE* stream );
      int rw_system( const char* command ) noexcept;
      std::string rw_self_exe_path();
      std::FILE* rw_open_memstream( char** bufloc, std::size_t* sizeloc );
      int rw_fclose( std::FILE* stream );
      int rw_fflush( std::FILE* stream );
      int rw_close( int fd );
      std::string rw_short_path( const std::string& path );

      inline std::string rw_self_executable_path( const char* /*argv0*/ )
      {
          return rw_self_exe_path();
      }

      /// Publishes a replacement file with bounded retries for transient Windows sharing violations.
      inline int rw_rename( const char* oldname, const char* newname )
      {
          const std::wstring wideOldName = rw_utf8_to_wide( rw_windows_path_from_msys( oldname ? oldname : "" ) );
          const std::wstring wideNewName = rw_utf8_to_wide( rw_windows_path_from_msys( newname ? newname : "" ) );
          if( wideOldName.empty() || wideNewName.empty() )
          {
              errno = EINVAL;
              return -1;
          }
          for( int attempt = 0; attempt < 8; ++attempt )
          {
              if( MoveFileExW( wideOldName.c_str(), wideNewName.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED ) )
              {
                  return 0;
              }
              const DWORD err = GetLastError();
              if( err != ERROR_ACCESS_DENIED && err != ERROR_SHARING_VIOLATION )
              {
                  break;
              }
              Sleep( 5 );
          }
          return -1;
      }

      inline int rw_remove_utf8( std::string_view path )
      {
          const std::wstring widePath = rw_utf8_to_wide( rw_windows_path_from_msys( path ) );
          return widePath.empty() ? -1 : ::_wremove( widePath.c_str() );
      }
  }

  namespace std
  {
      using rw::compat::rw_fclose;
      using rw::compat::rw_fflush;
      using rw::compat::rw_rename;
  }

  using rw::compat::rw_fclose;
  using rw::compat::rw_fflush;
  using rw::compat::rw_close;
  using rw::compat::rw_rename;
  using rw::compat::rw_short_path;

  #ifndef rename
    #define rename rw_rename
  #endif

  // Transparent polyfills for POSIX symbols called as ::popen, ::pread, etc.
  #ifndef popen
    #define popen rw::compat::rw_popen
  #endif
  #ifndef pclose
    #define pclose rw::compat::rw_pclose
  #endif
  #ifndef pread
    #define pread rw::compat::rw_pread
  #endif
  #ifndef realpath
    #define realpath rw::compat::rw_realpath
  #endif
  #ifndef flock
    #define flock rw::compat::rw_flock
  #endif
  #ifndef open_memstream
    #define open_memstream rw::compat::rw_open_memstream
  #endif
  #ifndef fclose
    #define fclose rw_fclose
  #endif
  #ifndef fflush
    #define fflush rw_fflush
  #endif
  /// Closes a CRT descriptor while preserving the separate SOCKET close path.
  inline int close( int fd )
  {
      return rw::compat::rw_close( fd );
  }

  #include <ctime>
  /// Fills a caller-provided tm with local time using the thread-safe MSVC API.
  inline struct tm* rw_localtime_r( const time_t* timer, struct tm* buf ) noexcept
  {
      return localtime_s( buf, timer ) == 0 ? buf : nullptr;
  }
  /// Fills a caller-provided tm with UTC time using the thread-safe MSVC API.
  inline struct tm* rw_gmtime_r( const time_t* timer, struct tm* buf ) noexcept
  {
      return gmtime_s( buf, timer ) == 0 ? buf : nullptr;
  }
  #ifndef localtime_r
    #define localtime_r rw_localtime_r
  #endif
  #ifndef gmtime_r
    #define gmtime_r rw_gmtime_r
  #endif

  /// Adapts POSIX directory creation to the CRT while intentionally ignoring POSIX mode bits.
  inline int mkdir( const char* path, int /*mode*/ )
  {
      return _mkdir( path );
  }

  /// Provides the lstat shape used by the POSIX code through the CRT stat result.
  inline int lstat( const char* path, struct stat* buf )
  {
      return ::stat( path, buf );
  }

  /// Supplies the stable non-root identity used by cache-path code on Windows.
  inline unsigned int getuid() noexcept
  {
      return 1000;
  }

  /// Sleeps for the requested POSIX timespec duration and preserves the zero-success convention.
  inline int nanosleep( const struct timespec* req, struct timespec* /*rem*/ ) noexcept
  {
      if( req )
      {
          DWORD ms = static_cast<DWORD>( req->tv_sec * 1000 + ( req->tv_nsec + 999999 ) / 1000000 );
          Sleep( ms );
      }
      return 0;
  }

  /// Keeps the POSIX permission call harmless where Windows descriptors use a different model.
  inline int fchmod( int /*fd*/, int /*mode*/ ) noexcept
  {
      return 0;
  }

  /// Flushes a Windows CRT descriptor to the underlying file through _commit.
  inline int fsync( int fd ) noexcept
  {
      return _commit( fd );
  }

  using socket_t = SOCKET;
  #define RW_INVALID_SOCKET INVALID_SOCKET

  /// Closes a Winsock handle through closesocket rather than the CRT close function.
  inline int rw_closesocket( SOCKET s ) noexcept
  {
      return ::closesocket( s );
  }

  namespace rw::compat
  {
      inline int rw_socket_last_error() noexcept
      {
          return ::WSAGetLastError();
      }

      /// Converts POSIX timeval receive timeouts to the millisecond form expected by Winsock.
      inline int rw_setsockopt( SOCKET s, int level, int optname, const void* optval, int optlen )
      {
          if( level == SOL_SOCKET && optname == SO_RCVTIMEO && optlen == sizeof( timeval ) )
          {
              const auto* tv = static_cast<const timeval*>( optval );
              DWORD ms = static_cast<DWORD>( tv->tv_sec * 1000 + tv->tv_usec / 1000 );
              return ::setsockopt( s, level, optname, reinterpret_cast<const char*>( &ms ), sizeof( ms ) );
          }
          return ::setsockopt( s, level, optname, static_cast<const char*>( optval ), optlen );
      }
  }

  using rw::compat::rw_setsockopt;

  #ifndef setsockopt
    #define setsockopt rw_setsockopt
  #endif

  #include <format>
  namespace std
  {
  #if defined(_MSC_VER) && ( !defined(__cpp_lib_format) || __cpp_lib_format < 202207L )
      template <class... _Args>
      using format_string = _Fmt_string<_Args...>;
  #endif
  }

#else

  typedef SSIZE_T ssize_t;

#endif // __cplusplus

#else

  #include <unistd.h>
  #include <sys/file.h>
  #include <sys/stat.h>
  #include <fcntl.h>
  #include <climits>
  #include <cstdint>
  #include <cstdio>
  #include <cstdlib>
  #include <cstring>
  #include <algorithm>
  #include <functional>
  #include <pthread.h>
  #include <string>
  #include <string_view>
  #include <thread>
  #include <vector>
  #if defined( __linux__ )
    #include <sys/syscall.h>
  #endif
  #if defined( __APPLE__ )
    #include <mach-o/dyld.h>
  #endif

  #ifdef __cplusplus
  namespace rw::compat
  {
      inline int rw_socket_last_error() noexcept
      {
          return errno;
      }

      inline std::string rw_windows_path_from_msys( std::string_view path )
      {
          return std::string( path );
      }

      inline std::string rw_native_path( std::string_view path )
      {
          return std::string( path );
      }

      inline std::string rw_resolve_executable( std::string_view command );

      inline bool rw_command_available( std::string_view command )
      {
          return !rw_resolve_executable( command ).empty();
      }

      inline bool rw_set_environment( const char* key, const char* value ) noexcept
      {
          return key != nullptr && value != nullptr && ::setenv( key, value, 1 ) == 0;
      }

      inline int rw_binary_open_flags( int flags ) noexcept
      {
          return flags;
      }

      inline std::string rw_resolve_executable( std::string_view command )
      {
          if( command.empty() )
          {
              return {};
          }
          const auto executable = []( const std::string& path ) noexcept
          {
              return ::access( path.c_str(), X_OK ) == 0;
          };
          if( command.find( '/' ) != std::string_view::npos )
          {
              const std::string path( command );
              return executable( path ) ? path : std::string();
          }
          const char* pathEnv = std::getenv( "PATH" );
          std::string_view remaining = pathEnv ? std::string_view( pathEnv ) : std::string_view();
          while( !remaining.empty() )
          {
              const std::size_t split = remaining.find( ':' );
              const std::string_view dir = remaining.substr( 0, split );
              const std::string candidate = std::string( dir.empty() ? "." : dir ) + "/" + std::string( command );
              if( executable( candidate ) )
              {
                  return candidate;
              }
              if( split == std::string_view::npos )
              {
                  break;
              }
              remaining.remove_prefix( split + 1 );
          }
          return {};
      }

      inline int rw_git_ignore_probe( std::string_view root_dir, std::string& output, std::size_t max_bytes )
      {
          output.clear();
          const auto quote = []( std::string_view value )
          {
              std::string result;
              result.reserve( value.size() + 2 );
              result.push_back( '\'' );
              for( const char c : value )
              {
                  if( c == '\'' )
                  {
                      result += "'\\''";
                  }
                  else
                  {
                      result.push_back( c );
                  }
              }
              result.push_back( '\'' );
              return result;
          };
          const std::string cmd = "git -C " + quote( root_dir.empty() ? std::string_view( "." ) : root_dir )
                                + " -c core.quotepath=false ls-files --others --ignored --exclude-standard --directory -z 2>/dev/null";
          std::FILE* pipe = ::popen( cmd.c_str(), "r" );
          if( pipe == nullptr )
          {
              return -1;
          }
          bool overflowed = false;
          bool readFailed = false;
          char chunk[ 8192 ];
          for( std::size_t n = std::fread( chunk, 1, sizeof( chunk ), pipe ); n > 0; n = std::fread( chunk, 1, sizeof( chunk ), pipe ) )
          {
              if( !overflowed )
              {
                  if( n > max_bytes || output.size() > max_bytes - n )
                  {
                      overflowed = true;
                  }
                  else
                  {
                      output.append( chunk, n );
                  }
              }
          }
          readFailed = std::ferror( pipe ) != 0;
          const int status = ::pclose( pipe );
          if( readFailed || status == -1 )
          {
              return -1;
          }
          return overflowed ? -2 : status;
      }

      inline bool rw_path_char_equal( char a, char b ) noexcept
      {
          return a == b;
      }

      inline bool rw_drive_letter_matches( std::string_view /*path*/, std::string_view /*prefix*/ ) noexcept
      {
          return false;
      }

      inline void rw_normalize_msys_drive_paths_in_place( char* /*text*/ ) noexcept
      {
      }

      /// Keeps POSIX worker sizing aligned with the standard library's effective CPU view.
      inline unsigned rw_effective_hardware_concurrency() noexcept
      {
          const unsigned hardware = std::thread::hardware_concurrency();
          return hardware == 0 ? 1u : hardware;
      }

      inline std::uint64_t rw_profile_thread_id() noexcept
      {
#if defined( __APPLE__ )
          std::uint64_t tid = 0;
          ::pthread_threadid_np( nullptr, &tid );
          return tid;
#elif defined( __linux__ )
          return static_cast<std::uint64_t>( ::syscall( SYS_gettid ) );
#else
          return static_cast<std::uint64_t>( std::hash<std::thread::id>{}( std::this_thread::get_id() ) );
#endif
      }

      inline bool rw_profile_is_initial_thread() noexcept
      {
#if defined( __APPLE__ )
          return ::pthread_main_np() != 0;
#elif defined( __linux__ )
          return ::getpid() == static_cast<pid_t>( ::syscall( SYS_gettid ) );
#else
          static const std::thread::id firstCaller = std::this_thread::get_id();
          return std::this_thread::get_id() == firstCaller;
#endif
      }

      inline void rw_profile_copy_thread_name( char* buffer, std::size_t buffer_count ) noexcept
      {
          if( buffer == nullptr || buffer_count == 0 )
          {
              return;
          }
          buffer[ 0 ] = '\0';
#if defined( __APPLE__ ) || defined( __linux__ )
          (void)::pthread_getname_np( ::pthread_self(), buffer, buffer_count );
#else
          (void)buffer_count;
#endif
      }

      /// Keeps the POSIX build on the same compatibility API by forwarding flock unchanged.
      inline int rw_flock( int fd, int operation ) noexcept
      {
          return ::flock( fd, operation );
      }

      /// Keeps the POSIX build on the same compatibility API by forwarding pread unchanged.
      inline ssize_t rw_pread( int fd, void* buf, std::size_t count, std::uint64_t offset ) noexcept
      {
          return ::pread( fd, buf, count, static_cast<off_t>( offset ) );
      }

      /// Keeps the POSIX build on the same compatibility API by forwarding realpath unchanged.
      inline char* rw_realpath( const char* path, char* resolved_path ) noexcept
      {
          return ::realpath( path, resolved_path );
      }

      /// Keeps the POSIX build on the same compatibility API by forwarding popen unchanged.
      inline std::FILE* rw_popen( const char* command, const char* mode )
      {
          return ::popen( command, mode );
      }

      inline int rw_system( const char* command ) noexcept
      {
          return command == nullptr ? -1 : std::system( command );
      }

      /// Keeps path-based file opens on the shared compatibility API; POSIX paths are already UTF-8 byte paths.
      inline std::FILE* rw_fopen_utf8( std::string_view path, std::string_view mode )
      {
          return std::fopen( std::string( path ).c_str(), std::string( mode ).c_str() );
      }

      struct RwFileTimes
      {
          long long mtimeNs;
          long long sizeBytes;
          long long changeTimeNs;
      };


      inline RwFileTimes rw_file_times_of( const std::string& path ) noexcept
      {
          struct stat st{};
          if( ::stat( path.c_str(), &st ) != 0 )
          {
              return { -1, -1, -1 };
          }
#if defined( __APPLE__ ) || defined( __FreeBSD__ ) || defined( __OpenBSD__ ) || defined( __NetBSD__ )
          const long long mtime = static_cast<long long>( st.st_mtimespec.tv_sec ) * 1000000000LL + st.st_mtimespec.tv_nsec;
          const long long ctime = static_cast<long long>( st.st_ctimespec.tv_sec ) * 1000000000LL + st.st_ctimespec.tv_nsec;
#elif defined( __linux__ )
          const long long mtime = static_cast<long long>( st.st_mtim.tv_sec ) * 1000000000LL + st.st_mtim.tv_nsec;
          const long long ctime = static_cast<long long>( st.st_ctim.tv_sec ) * 1000000000LL + st.st_ctim.tv_nsec;
#else
          const long long mtime = static_cast<long long>( st.st_mtime ) * 1000000000LL;
          const long long ctime = static_cast<long long>( st.st_ctime ) * 1000000000LL;
#endif
          return { mtime, static_cast<long long>( st.st_size ), ctime };
      }


      inline bool rw_is_regular_file( std::string_view path ) noexcept
      {
          struct stat st{};
          return ::stat( std::string( path ).c_str(), &st ) == 0 && S_ISREG( st.st_mode );
      }

      inline bool rw_path_exists( std::string_view path ) noexcept
      {
          struct stat st {};
          return ::stat( std::string( path ).c_str(), &st ) == 0;
      }

      inline bool rw_is_symlink( std::string_view path ) noexcept
      {
          struct stat st {};
          return ::lstat( std::string( path ).c_str(), &st ) == 0 && S_ISLNK( st.st_mode );
      }

      inline std::int64_t rw_write_fd( int fd, const char* data, std::size_t byte_count ) noexcept
      {
          return static_cast<std::int64_t>( ::write( fd, data, byte_count ) );
      }

      inline int rw_close_fd( int fd ) noexcept
      {
          return ::close( fd );
      }

      struct RwFileIdentity
      {
          bool          valid;
          std::uint64_t volumeId;
          std::uint64_t fileId;
          long long     mtimeSeconds;
          long long     sizeBytes;
      };

      inline RwFileIdentity rw_file_identity_of( std::string_view path ) noexcept
      {
          struct stat st{};
          if( ::stat( std::string( path ).c_str(), &st ) != 0 )
          {
              return { false, 0, 0, -1, -1 };
          }
          return { true, static_cast<std::uint64_t>( st.st_dev ), static_cast<std::uint64_t>( st.st_ino ),
                   static_cast<long long>( st.st_mtime ), static_cast<long long>( st.st_size ) };
      }

      inline int rw_fseek( std::FILE* stream, std::int64_t offset, int origin ) noexcept
      {
          return stream == nullptr ? -1 : ::fseeko( stream, static_cast<off_t>( offset ), origin );
      }

      inline std::int64_t rw_ftell( std::FILE* stream ) noexcept
      {
          return stream == nullptr ? -1 : static_cast<std::int64_t>( ::ftello( stream ) );
      }

      inline std::vector<std::uint8_t> rw_read_regular_file( std::string_view path, std::size_t max_bytes )
      {
          std::vector<std::uint8_t> bytes;
          const std::string pathString( path );
          const int indexFd = ::open( pathString.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC );
          if( indexFd < 0 )
          {
              return bytes;
          }
          struct stat indexStat {};
          const int statusFlags = ( ::fstat( indexFd, &indexStat ) == 0 && S_ISREG( indexStat.st_mode ) ) ? ::fcntl( indexFd, F_GETFL ) : -1;
          std::FILE* file = ( statusFlags >= 0 && ::fcntl( indexFd, F_SETFL, statusFlags & ~O_NONBLOCK ) == 0 )
                          ? ::fdopen( indexFd, "rb" ) : nullptr;
          if( file == nullptr )
          {
              ::close( indexFd );
              return bytes;
          }
          if( rw_fseek( file, 0, SEEK_END ) != 0 ) { std::fclose( file ); return bytes; }
          const std::int64_t size = rw_ftell( file );
          if( size <= 0 || static_cast<std::uint64_t>( size ) > max_bytes ) { std::fclose( file ); return bytes; }
          std::rewind( file );
          bytes.resize( static_cast<std::size_t>( size ) );
          const std::size_t read = std::fread( bytes.data(), 1, bytes.size(), file );
          std::fclose( file );
          if( read != bytes.size() ) { bytes.clear(); }
          return bytes;
      }

      inline unsigned rw_document_worker_count( unsigned hardware, std::size_t item_count ) noexcept
      {
          unsigned count = hardware == 0 ? 1u : hardware;
          if( item_count < count )
          {
              count = static_cast<unsigned>( item_count );
          }
          return count;
      }

      /// Removes a UTF-8 path through the same compatibility API on both platforms.
      inline int rw_remove_utf8( std::string_view path )
      {
          return std::remove( std::string( path ).c_str() );
      }

      /// Renames a path through the same compatibility API on both platforms.
      inline int rw_rename( const char* oldname, const char* newname )
      {
          return std::rename( oldname, newname );
      }

      /// Keeps the POSIX build on the same compatibility API by forwarding pclose unchanged.
      inline int rw_pclose( std::FILE* stream )
      {
          return ::pclose( stream );
      }

      /// Returns no executable override on POSIX, where the native path helper is unnecessary.
      inline std::string rw_self_exe_path()
      {
          return {};
      }

      inline std::string rw_self_executable_path( const char* argv0 )
      {
#if defined( __APPLE__ )
          char          buf[ PATH_MAX ];
          std::uint32_t size = sizeof( buf );
          if( ::_NSGetExecutablePath( buf, &size ) == 0 )
          {
              char resolved[ PATH_MAX ];
              if( ::realpath( buf, resolved ) )
              {
                  return std::string( resolved );
              }
              return std::string( buf );
          }
#elif defined( __linux__ )
          char          buf[ PATH_MAX ];
          const ssize_t byteCount = ::readlink( "/proc/self/exe", buf, sizeof( buf ) - 1 );
          if( byteCount > 0 )
          {
              buf[ byteCount ] = '\0';
              char resolved[ PATH_MAX ];
              if( ::realpath( buf, resolved ) )
              {
                  return std::string( resolved );
              }
              return std::string( buf );
          }
#endif
          char resolved[ PATH_MAX ];
          if( argv0 && ::realpath( argv0, resolved ) )
          {
              return std::string( resolved );
          }
          if( argv0 && *argv0 && !std::strchr( argv0, '/' ) )
          {
              const char* pathEnv = std::getenv( "PATH" );
              std::string_view remaining = pathEnv ? std::string_view( pathEnv ) : std::string_view();
              while( !remaining.empty() )
              {
                  const std::size_t split = remaining.find( ':' );
                  const std::string_view dir = remaining.substr( 0, split );
                  const std::string candidate = std::string( dir.empty() ? "." : dir ) + "/" + argv0;
                  if( ::realpath( candidate.c_str(), resolved ) && ::access( resolved, X_OK ) == 0 )
                  {
                      return std::string( resolved );
                  }
                  if( split == std::string_view::npos )
                  {
                      break;
                  }
                  remaining.remove_prefix( split + 1 );
              }
          }
          return {};
      }

      /// POSIX stdout already writes bytes without newline translation.
      inline void rw_set_stdout_binary() noexcept
      {
      }
  }

  using socket_t = int;
  #define RW_INVALID_SOCKET ( -1 )
  /// Closes the POSIX socket descriptor through close.
  inline int rw_closesocket( int s ) noexcept
  {
      return ::close( s );
  }
  #endif
#endif

#ifdef __cplusplus

  #include <algorithm>
  #include <chrono>
  #if !defined( _WIN32 )
    #include <poll.h>
    #include <signal.h>
    #include <sys/wait.h>
  #endif
  #include <vector>
  #include "Diagnostics.h"

namespace rw::compat
{

struct RwFsWatcher
{
#if defined( _WIN32 )
    HANDLE             directory   = INVALID_HANDLE_VALUE;
    HANDLE             eventHandle = nullptr;
    OVERLAPPED         overlapped{};
    std::vector<std::uint8_t> buffer;
#else
    int              kq = -1;
    std::vector<int> dirFds;
#endif
    bool healthy   = false;
    bool lastEvent = false;

    RwFsWatcher() = default;
    RwFsWatcher( const RwFsWatcher& ) = delete;
    RwFsWatcher& operator=( const RwFsWatcher& ) = delete;
    ~RwFsWatcher() { reset(); }

    void reset() noexcept
    {
#if defined( _WIN32 )
        if( directory != INVALID_HANDLE_VALUE )
        {
            ::CancelIoEx( directory, &overlapped );
            ::CloseHandle( directory );
        }
        if( eventHandle != nullptr )
        {
            ::CloseHandle( eventHandle );
        }
        directory   = INVALID_HANDLE_VALUE;
        eventHandle = nullptr;
        overlapped  = OVERLAPPED{};
        buffer.clear();
#else
        for( const int fd : dirFds )
        {
            if( fd >= 0 )
            {
                ::close( fd );
            }
        }
        dirFds.clear();
        if( kq >= 0 )
        {
            ::close( kq );
        }
        kq = -1;
#endif
        healthy   = false;
        lastEvent = false;
    }

    void arm( const std::vector<std::string>& dirs )
    {
        reset();
#if defined( _WIN32 )
        if( dirs.empty() )
        {
            return;
        }
        const auto rootIt = std::min_element( dirs.begin(), dirs.end(), []( const std::string& a, const std::string& b )
        {
            return a.size() < b.size();
        } );
        const std::string& watchedRoot = *rootIt;
        for( const std::string& dir : dirs )
        {
            const bool same = dir.size() == watchedRoot.size() && _stricmp( dir.c_str(), watchedRoot.c_str() ) == 0;
            const bool child = dir.size() > watchedRoot.size()
                            && _strnicmp( dir.c_str(), watchedRoot.c_str(), watchedRoot.size() ) == 0
                            && ( dir[ watchedRoot.size() ] == '/' || dir[ watchedRoot.size() ] == '\\' );
            if( !same && !child )
            {
                return;
            }
        }
        const std::wstring wideRoot = rw_utf8_to_wide( rw_windows_path_from_msys( watchedRoot ) );
        if( wideRoot.empty() )
        {
            return;
        }
        directory = ::CreateFileW( wideRoot.c_str(), FILE_LIST_DIRECTORY,
                                   FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
                                   FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, nullptr );
        if( directory == INVALID_HANDLE_VALUE )
        {
            return;
        }
        eventHandle = ::CreateEventW( nullptr, TRUE, FALSE, nullptr );
        if( eventHandle == nullptr )
        {
            reset();
            return;
        }
        try
        {
            buffer.resize( 64u * 1024u );
        }
        catch( ... )
        {
            reset();
            return;
        }
        overlapped        = OVERLAPPED{};
        overlapped.hEvent = eventHandle;
        constexpr DWORD notifyFilter = FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME
                                     | FILE_NOTIFY_CHANGE_LAST_WRITE | FILE_NOTIFY_CHANGE_SIZE
                                     | FILE_NOTIFY_CHANGE_CREATION | FILE_NOTIFY_CHANGE_ATTRIBUTES;
        if( !::ReadDirectoryChangesW( directory, buffer.data(), static_cast<DWORD>( buffer.size() ), TRUE,
                                      notifyFilter, nullptr, &overlapped, nullptr ) )
        {
            reset();
            return;
        }
        healthy = true;
#elif RW_PLATFORM_HAS_KQUEUE
        kq = ::kqueue();
        if( kq < 0 )
        {
            DEGRADED_PATH_ALERT( "mcp watcher: kqueue() unavailable — falling back to stat-sweep freshness" );
            return;
        }
        dirFds.reserve( dirs.size() );
        for( const std::string& dir : dirs )
        {
            const int fd = ::open( dir.c_str(), O_RDONLY | O_CLOEXEC );
            bool registered = fd >= 0;
            if( registered )
            {
                struct kevent event;
                EV_SET( &event, fd, EVFILT_VNODE, EV_ADD | EV_CLEAR,
                        NOTE_WRITE | NOTE_DELETE | NOTE_RENAME | NOTE_EXTEND, 0, nullptr );
                const struct timespec zero = { 0, 0 };
                if( ::kevent( kq, &event, 1, nullptr, 0, &zero ) < 0 )
                {
                    ::close( fd );
                    registered = false;
                }
            }
            if( !registered )
            {
                DEGRADED_PATH_ALERT( "mcp watcher: dir watch failed (fd limit or unopenable dir) — falling back to stat-sweep freshness" );
                reset();
                return;
            }
            dirFds.push_back( fd );
        }
        healthy = true;
#else
        (void)dirs;
#endif
    }

    bool drainHadEvent() noexcept
    {
#if defined( _WIN32 )
        if( !healthy || directory == INVALID_HANDLE_VALUE || eventHandle == nullptr )
        {
            lastEvent = true;
            return true;
        }
        DWORD bytes = 0;
        if( !::GetOverlappedResult( directory, &overlapped, &bytes, FALSE ) )
        {
            if( ::GetLastError() == ERROR_IO_INCOMPLETE )
            {
                lastEvent = false;
                return false;
            }
            healthy   = false;
            lastEvent = true;
            return true;
        }
        ::ResetEvent( eventHandle );
        overlapped        = OVERLAPPED{};
        overlapped.hEvent = eventHandle;
        constexpr DWORD notifyFilter = FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME
                                     | FILE_NOTIFY_CHANGE_LAST_WRITE | FILE_NOTIFY_CHANGE_SIZE
                                     | FILE_NOTIFY_CHANGE_CREATION | FILE_NOTIFY_CHANGE_ATTRIBUTES;
        if( !::ReadDirectoryChangesW( directory, buffer.data(), static_cast<DWORD>( buffer.size() ), TRUE,
                                      notifyFilter, nullptr, &overlapped, nullptr ) )
        {
            healthy   = false;
            lastEvent = true;
            return true;
        }
        lastEvent = true;
        return true;
#elif RW_PLATFORM_HAS_KQUEUE
        if( kq < 0 )
        {
            lastEvent = true;
            return true;
        }
        struct kevent events[ 32 ];
        const struct timespec zero = { 0, 0 };
        bool any = false;
        for( ;; )
        {
            const int count = ::kevent( kq, nullptr, 0, events, 32, &zero );
            if( count < 0 )
            {
                lastEvent = true;
                return true;
            }
            if( count == 0 )
            {
                break;
            }
            any = true;
            if( count < 32 )
            {
                break;
            }
        }
        lastEvent = any;
        return any;
#else
        lastEvent = true;
        return true;
#endif
    }
};

} // namespace rw::compat

namespace rw::compat
{

inline std::string rw_cache_dir_ladder( std::string_view application_name )
{
    if( application_name.empty() )
    {
        return {};
    }
#if defined( _WIN32 )
    std::string d;
    const char* tmpDir       = std::getenv( "TMPDIR" );
    const char* localAppData = std::getenv( "LOCALAPPDATA" );
    const char* tempDir      = std::getenv( "TEMP" );
    if( !tempDir )
    {
        tempDir = std::getenv( "TMP" );
    }
    if( tmpDir && *tmpDir )
    {
        d = rw_windows_path_from_msys( tmpDir );
    }
    else if( const char* xdgCache = std::getenv( "XDG_CACHE_HOME" ); xdgCache && *xdgCache )
    {
        d = rw_windows_path_from_msys( xdgCache );
    }
    else if( localAppData && *localAppData )
    {
        d = localAppData;
    }
    else if( tempDir && *tempDir )
    {
        d = tempDir;
    }
    else
    {
        d = "C:/Windows/Temp";
    }
    while( d.size() > 1 && ( d.back() == '/' || d.back() == '\\' ) )
    {
        d.pop_back();
    }
    d += "/" + std::string( application_name );

    const std::wstring wideDir = rw_utf8_to_wide( d );
    if( wideDir.empty() )
    {
        return "NUL";
    }
    SECURITY_ATTRIBUTES security{ sizeof( SECURITY_ATTRIBUTES ), nullptr, FALSE };
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    if( !ConvertStringSecurityDescriptorToSecurityDescriptorW( L"D:P(A;OICI;GA;;;OW)(A;OICI;GA;;;BA)",
                                                                SDDL_REVISION_1, &descriptor, nullptr ) )
    {
        return "NUL";
    }
    security.lpSecurityDescriptor = descriptor;
    const BOOL created             = ::CreateDirectoryW( wideDir.c_str(), &security );
    const DWORD createError       = created ? ERROR_SUCCESS : ::GetLastError();
    if( !created && createError != ERROR_ALREADY_EXISTS )
    {
        ::LocalFree( descriptor );
        return "NUL";
    }
    HANDLE directoryHandle = rw_windows_open_safe_directory( d );
    if( directoryHandle == INVALID_HANDLE_VALUE )
    {
        ::LocalFree( descriptor );
        return "NUL";
    }
    if( !created )
    {
        PACL existingDacl = nullptr;
        BOOL present = FALSE;
        BOOL defaulted = FALSE;
        if( !::GetSecurityDescriptorDacl( descriptor, &present, &existingDacl, &defaulted ) || !present || !existingDacl
            || ::SetSecurityInfo( directoryHandle, SE_FILE_OBJECT,
                                   DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
                                   nullptr, nullptr, existingDacl, nullptr ) != ERROR_SUCCESS )
        {
            ::CloseHandle( directoryHandle );
            ::LocalFree( descriptor );
            return "NUL";
        }
    }
    ::LocalFree( descriptor );

    HANDLE token = nullptr;
    if( !::OpenProcessToken( ::GetCurrentProcess(), TOKEN_QUERY, &token ) )
    {
        ::CloseHandle( directoryHandle );
        return "NUL";
    }
    DWORD tokenLength = 0;
    ::GetTokenInformation( token, TokenUser, nullptr, 0, &tokenLength );
    if( tokenLength == 0 )
    {
        ::CloseHandle( token );
        ::CloseHandle( directoryHandle );
        return "NUL";
    }
    std::vector<BYTE> tokenBuffer( tokenLength );
    if( !::GetTokenInformation( token, TokenUser, tokenBuffer.data(), tokenLength, &tokenLength ) )
    {
        ::CloseHandle( token );
        ::CloseHandle( directoryHandle );
        return "NUL";
    }
    const TOKEN_USER* tokenUser = reinterpret_cast<const TOKEN_USER*>( tokenBuffer.data() );
    PSID owner = nullptr;
    PSECURITY_DESCRIPTOR ownerDescriptor = nullptr;
    const DWORD ownerResult = ::GetSecurityInfo( directoryHandle, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION,
                                                 &owner, nullptr, nullptr, nullptr, &ownerDescriptor );
    bool ownerMatch = ownerResult == ERROR_SUCCESS && owner != nullptr
                   && ::EqualSid( owner, tokenUser->User.Sid ) != FALSE;
    if( !ownerMatch && ownerResult == ERROR_SUCCESS && owner != nullptr )
    {
        SID_IDENTIFIER_AUTHORITY authority = SECURITY_NT_AUTHORITY;
        PSID administrators = nullptr;
        if( ::AllocateAndInitializeSid( &authority, 2, SECURITY_BUILTIN_DOMAIN_RID, DOMAIN_ALIAS_RID_ADMINS,
                                        0, 0, 0, 0, 0, 0, &administrators ) )
        {
            ownerMatch = ::EqualSid( owner, administrators ) != FALSE;
            ::FreeSid( administrators );
        }
    }
    if( ownerDescriptor )
    {
        ::LocalFree( ownerDescriptor );
    }
    ::CloseHandle( token );
    ::CloseHandle( directoryHandle );
    return ownerMatch ? d : "NUL";
#else
    std::string d;
    const char* tmpDir = std::getenv( "TMPDIR" );
    if( tmpDir && *tmpDir )
    {
        d = tmpDir;
        while( d.size() > 1 && d.back() == '/' )
        {
            d.pop_back();
        }
        d += "/" + std::string( application_name );
    }
    else if( const char* xdgCache = std::getenv( "XDG_CACHE_HOME" ); xdgCache && *xdgCache )
    {
        d = std::string( xdgCache ) + "/" + std::string( application_name );
    }
    else
    {
        d = "/tmp/" + std::string( application_name ) + "-" + std::to_string( static_cast<unsigned long long>( ::getuid() ) );
    }
    const int mkdirRc = ::mkdir( d.c_str(), 0700 );
    struct stat st {};
    if( mkdirRc == 0 || ( ::lstat( d.c_str(), &st ) == 0 && S_ISDIR( st.st_mode ) && st.st_uid == ::getuid() ) )
    {
        if( ::chmod( d.c_str(), 0700 ) == 0 && ::lstat( d.c_str(), &st ) == 0 && S_ISDIR( st.st_mode )
            && st.st_uid == ::getuid() && ( st.st_mode & 0777 ) == 0700 )
        {
            return d;
        }
    }
    return "/dev/null/" + std::string( application_name ) + "-cache-unavailable";
#endif
}

} // namespace rw::compat

namespace rw::compat
{

struct RwProcessCapture
{
    bool          isSpawnFailed    = false;
    bool          isTimedOut       = false;
    bool          isExitedNormally = false;
    int           exitCode         = -1;
    int           termSignal       = 0;
    std::uint64_t durationMs       = 0;
    std::uint64_t totalBytes       = 0;
    std::uint64_t droppedBytes     = 0;
    std::string   head;
    std::string   tail;
};

template< typename AppendFn >
RwProcessCapture rw_run_command_capture( const std::string& cmd, std::uint32_t timeout_sec, AppendFn&& append )
{
#if defined( _WIN32 )
    RwProcessCapture cap;
    RwWindowsTemporaryEnvironmentScope temporaryEnvironment;
    if( rw_windows_temporary_environment_is_long() && !temporaryEnvironment.active() )
    {
        cap.isSpawnFailed = true;
        return cap;
    }
    SECURITY_ATTRIBUTES security{};
    security.nLength = sizeof( security );
    security.bInheritHandle = TRUE;
    HANDLE readHandle = nullptr;
    HANDLE writeHandle = nullptr;
    if( !::CreatePipe( &readHandle, &writeHandle, &security, 0 ) )
    {
        cap.isSpawnFailed = true;
        return cap;
    }
    ::SetHandleInformation( readHandle, HANDLE_FLAG_INHERIT, 0 );

    HANDLE childStdin = ::CreateFileW( L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &security,
                                       OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr );
    if( childStdin == INVALID_HANDLE_VALUE )
    {
        ::CloseHandle( readHandle );
        ::CloseHandle( writeHandle );
        cap.isSpawnFailed = true;
        return cap;
    }

    HANDLE job = ::CreateJobObjectW( nullptr, nullptr );
    if( job == nullptr )
    {
        ::CloseHandle( readHandle );
        ::CloseHandle( writeHandle );
        ::CloseHandle( childStdin );
        cap.isSpawnFailed = true;
        return cap;
    }
    {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if( !::SetInformationJobObject( job, JobObjectExtendedLimitInformation, &limits, sizeof( limits ) ) )
        {
            ::CloseHandle( readHandle );
            ::CloseHandle( writeHandle );
            ::CloseHandle( childStdin );
            ::CloseHandle( job );
            cap.isSpawnFailed = true;
            return cap;
        }
    }

    STARTUPINFOW startup{};
    startup.cb = sizeof( startup );
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = childStdin;
    startup.hStdOutput = writeHandle;
    startup.hStdError = writeHandle;

    std::string shellUtf8 = rw_posix_shell_path();
    std::wstring shellPath = rw_utf8_to_wide( shellUtf8 );
    bool hasPosixShell = !shellPath.empty();
    if( !hasPosixShell )
    {
        shellPath.resize( 32768, L'\0' );
        const UINT length = ::GetSystemDirectoryW( shellPath.data(), static_cast<UINT>( shellPath.size() ) );
        if( length == 0 || length >= shellPath.size() )
        {
            ::CloseHandle( readHandle );
            ::CloseHandle( writeHandle );
            ::CloseHandle( childStdin );
            if( job != nullptr ) { ::CloseHandle( job ); }
            cap.isSpawnFailed = true;
            return cap;
        }
        shellPath.resize( length );
        shellPath += L"\\cmd.exe";
        shellUtf8 = rw_wide_to_utf8( shellPath );
    }
    const auto quoteArg = []( std::string_view value )
    {
        std::string quoted;
        quoted.reserve( value.size() + 2 );
        quoted.push_back( '"' );
        std::size_t backslashes = 0;
        for( const char c : value )
        {
            if( c == '\\' )
            {
                ++backslashes;
                continue;
            }
            if( c == '"' )
            {
                quoted.append( backslashes * 2 + 1, '\\' );
                quoted.push_back( '"' );
            }
            else
            {
                quoted.append( backslashes, '\\' );
                quoted.push_back( c );
            }
            backslashes = 0;
        }
        quoted.append( backslashes * 2, '\\' );
        quoted.push_back( '"' );
        return quoted;
    };
    const std::string fullCommand = hasPosixShell
        ? quoteArg( shellUtf8 ) + " -c " + quoteArg( cmd )
        : quoteArg( shellUtf8 ) + " /d /c " + cmd;
    const std::wstring wideCommand = rw_utf8_to_wide( fullCommand );
    if( wideCommand.empty() )
    {
        ::CloseHandle( readHandle );
        ::CloseHandle( writeHandle );
        ::CloseHandle( childStdin );
        if( job != nullptr ) { ::CloseHandle( job ); }
        cap.isSpawnFailed = true;
        return cap;
    }
    std::vector<wchar_t> commandLine( wideCommand.begin(), wideCommand.end() );
    commandLine.push_back( L'\0' );
    const auto started = std::chrono::steady_clock::now();
    const auto elapsedMs = [ & ]() -> std::int64_t
    {
        return std::chrono::duration_cast<std::chrono::milliseconds>( std::chrono::steady_clock::now() - started ).count();
    };
    PROCESS_INFORMATION processInfo{};
    const BOOL created = ::CreateProcessW( shellPath.c_str(), commandLine.data(), nullptr, nullptr, TRUE,
                                           CREATE_SUSPENDED | CREATE_NO_WINDOW, nullptr, nullptr, &startup, &processInfo );
    ::CloseHandle( writeHandle );
    ::CloseHandle( childStdin );
    if( !created )
    {
        ::CloseHandle( readHandle );
        if( job != nullptr ) { ::CloseHandle( job ); }
        cap.isSpawnFailed = true;
        return cap;
    }
    if( !::AssignProcessToJobObject( job, processInfo.hProcess ) )
    {
        ::TerminateProcess( processInfo.hProcess, ERROR_OPERATION_ABORTED );
        ::WaitForSingleObject( processInfo.hProcess, INFINITE );
        ::CloseHandle( processInfo.hThread );
        ::CloseHandle( processInfo.hProcess );
        ::CloseHandle( readHandle );
        ::CloseHandle( job );
        cap.isSpawnFailed = true;
        return cap;
    }
    if( ::ResumeThread( processInfo.hThread ) == static_cast<DWORD>( -1 ) )
    {
        ::TerminateProcess( processInfo.hProcess, ERROR_OPERATION_ABORTED );
        ::WaitForSingleObject( processInfo.hProcess, INFINITE );
        ::CloseHandle( processInfo.hThread );
        ::CloseHandle( processInfo.hProcess );
        ::CloseHandle( readHandle );
        ::CloseHandle( job );
        cap.isSpawnFailed = true;
        return cap;
    }
    ::CloseHandle( processInfo.hThread );
    const std::int64_t timeoutMs = static_cast<std::int64_t>( timeout_sec ) * 1000;
    char buffer[ 65536 ];
    for( ;; )
    {
        const std::int64_t nowMs = elapsedMs();
        if( !cap.isTimedOut && nowMs >= timeoutMs )
        {
            cap.isTimedOut = true;
            if( job != nullptr ) { ::TerminateJobObject( job, 1 ); }
            ::TerminateProcess( processInfo.hProcess, 1 );
        }
        DWORD bytesAvailable = 0;
        if( ::PeekNamedPipe( readHandle, nullptr, 0, nullptr, &bytesAvailable, nullptr ) && bytesAvailable > 0 )
        {
            DWORD bytesRead = 0;
            if( ::ReadFile( readHandle, buffer, sizeof( buffer ), &bytesRead, nullptr ) && bytesRead > 0 )
            {
                append( cap, buffer, static_cast<std::size_t>( bytesRead ) );
                continue;
            }
        }
        const DWORD waitResult = ::WaitForSingleObject( processInfo.hProcess, 15 );
        if( waitResult == WAIT_OBJECT_0 || cap.isTimedOut )
        {
            DWORD bytesRead = 0;
            while( ::PeekNamedPipe( readHandle, nullptr, 0, nullptr, &bytesAvailable, nullptr ) && bytesAvailable > 0 )
            {
                if( ::ReadFile( readHandle, buffer, sizeof( buffer ), &bytesRead, nullptr ) && bytesRead > 0 )
                {
                    append( cap, buffer, static_cast<std::size_t>( bytesRead ) );
                }
                else
                {
                    break;
                }
            }
            break;
        }
    }
    DWORD exitCode = 0;
    ::GetExitCodeProcess( processInfo.hProcess, &exitCode );
    cap.durationMs = static_cast<std::uint64_t>( elapsedMs() );
    if( !cap.isTimedOut )
    {
        cap.isExitedNormally = true;
        cap.exitCode = static_cast<int>( exitCode );
    }
    else
    {
        cap.termSignal = 9;
    }
    ::CloseHandle( readHandle );
    ::CloseHandle( processInfo.hProcess );
    if( job != nullptr ) { ::CloseHandle( job ); }
    return cap;
#else
    RwProcessCapture cap;
    int fds[ 2 ];
    if( ::pipe( fds ) != 0 )
    {
        cap.isSpawnFailed = true;
        return cap;
    }
    const auto started = std::chrono::steady_clock::now();
    const auto elapsedMs = [ & ]() -> std::int64_t
    {
        return std::chrono::duration_cast<std::chrono::milliseconds>( std::chrono::steady_clock::now() - started ).count();
    };
    const pid_t childPid = ::fork();
    if( childPid < 0 )
    {
        ::close( fds[ 0 ] );
        ::close( fds[ 1 ] );
        cap.isSpawnFailed = true;
        return cap;
    }
    if( childPid == 0 )
    {
        ::setpgid( 0, 0 );
        const int devNull = ::open( "/dev/null", O_RDONLY );
        if( devNull >= 0 )
        {
            ::dup2( devNull, STDIN_FILENO );
            ::close( devNull );
        }
        ::dup2( fds[ 1 ], STDOUT_FILENO );
        ::dup2( fds[ 1 ], STDERR_FILENO );
        ::close( fds[ 0 ] );
        ::close( fds[ 1 ] );
        ::execl( "/bin/sh", "sh", "-c", cmd.c_str(), static_cast<char*>( nullptr ) );
        ::_exit( 127 );
    }
    ::setpgid( childPid, childPid );
    ::close( fds[ 1 ] );
    const std::int64_t timeoutMs = static_cast<std::int64_t>( timeout_sec ) * 1000;
    constexpr std::int64_t drainWindowMs = 2000;
    std::int64_t drainDeadlineMs = 0;
    char buffer[ 65536 ];
    for( ;; )
    {
        const std::int64_t nowMs = elapsedMs();
        if( !cap.isTimedOut && nowMs >= timeoutMs )
        {
            cap.isTimedOut = true;
            drainDeadlineMs = nowMs + drainWindowMs;
            ::kill( -childPid, SIGKILL );
            ::kill( childPid, SIGKILL );
        }
        if( cap.isTimedOut && elapsedMs() >= drainDeadlineMs )
        {
            break;
        }
        const std::int64_t untilMs = ( cap.isTimedOut ? drainDeadlineMs : timeoutMs ) - elapsedMs();
        struct pollfd descriptor{ fds[ 0 ], POLLIN, 0 };
        const int ready = ::poll( &descriptor, 1, static_cast<int>( std::clamp<std::int64_t>( untilMs, 0, 1000 ) ) );
        if( ready > 0 )
        {
            const ssize_t bytesRead = ::read( fds[ 0 ], buffer, sizeof( buffer ) );
            if( bytesRead <= 0 ) { break; }
            append( cap, buffer, static_cast<std::size_t>( bytesRead ) );
        }
        else if( ready < 0 && errno != EINTR )
        {
            break;
        }
    }
    ::close( fds[ 0 ] );
    int status = 0;
    for( ;; )
    {
        const pid_t waited = ::waitpid( childPid, &status, cap.isTimedOut ? 0 : WNOHANG );
        if( waited == childPid || waited < 0 )
        {
            break;
        }
        if( elapsedMs() >= timeoutMs )
        {
            cap.isTimedOut = true;
            ::kill( -childPid, SIGKILL );
            ::kill( childPid, SIGKILL );
            continue;
        }
        ::poll( nullptr, 0, 20 );
    }
    cap.durationMs = static_cast<std::uint64_t>( elapsedMs() );
    if( WIFEXITED( status ) )
    {
        cap.isExitedNormally = true;
        cap.exitCode = WEXITSTATUS( status );
    }
    else if( WIFSIGNALED( status ) )
    {
        cap.termSignal = WTERMSIG( status );
    }
    return cap;
#endif
}

} // namespace rw::compat

#endif
