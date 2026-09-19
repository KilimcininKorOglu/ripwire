// fuzzsupport.h — shared plumbing for the reader fuzz harnesses (test/fuzz/readers/). Not linked into ripwire.
//
// A reader that takes a PATH gets its input through ScratchFile: one file per process under a private
// directory, rewritten per input. The directory is made once, owned by an RAII holder, and removed at exit.
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <string_view>
#include <system_error>
#include <unistd.h>

namespace rwfuzz
{

// The input as a std::string (the readers' own currency), never aliasing libFuzzer's buffer.
inline std::string bytesOf( const std::uint8_t* data, std::size_t size )
{
    return std::string( reinterpret_cast<const char*>( data ), size );
}

// A private per-process directory, created once, removed at exit. TMPDIR is pointed at it on first use so the
// readers' own cache-directory ladder (quality::cacheDirLadder) lands inside it too, never in the shared per-user
// cache every other ripwire process on the machine reads.
class ScratchDir
{
public:
    static ScratchDir& get()
    {
        static ScratchDir dir;
        return dir;
    }
    const std::string& path() const noexcept { return m_path; }

    ScratchDir( const ScratchDir& )            = delete;
    ScratchDir& operator=( const ScratchDir& ) = delete;

private:
    ScratchDir()
    {
        std::string templ = std::filesystem::temp_directory_path().string() + "/rwfuzz.XXXXXX";
        if( ::mkdtemp( templ.data() ) == nullptr )
        {
            std::abort();   // the harness cannot run without it; a fuzz run is never a degrade path
        }
        m_path = templ;
        ::setenv( "TMPDIR", m_path.c_str(), 1 );
    }
    ~ScratchDir()
    {
        std::error_code ec;
        std::filesystem::remove_all( m_path, ec );
    }
    std::string m_path;
};

// Write `bytes` to `<scratch>/<name>` (truncating) and return the path. Aborts on a failed write: an input the
// reader never saw must not be counted as an input it survived.
inline std::string writeScratch( std::string_view name, std::string_view bytes )
{
    const std::string path = ScratchDir::get().path() + "/" + std::string( name );
    std::FILE*        fp   = std::fopen( path.c_str(), "wb" );
    if( fp == nullptr )
    {
        std::abort();
    }
    const bool wrote = bytes.empty() || std::fwrite( bytes.data(), 1, bytes.size(), fp ) == bytes.size();
    if( std::fclose( fp ) != 0 || !wrote )
    {
        std::abort();
    }
    return path;
}

// LIVENESS. A harness whose header, checksum or selector is wrong makes its reader refuse EVERY input, and a crash
// fuzzer over a reader that refuses everything reports "no crash" forever. So each harness says, per input, whether
// the reader ACCEPTED it; under RWFUZZ_LIVENESS=1 that goes to stderr, and run.sh's replay fails a reader that
// accepted none of its valid seeds. Off by default: nothing is printed while fuzzing.
inline void noteAccepted( bool accepted ) noexcept
{
    static const bool enabled = std::getenv( "RWFUZZ_LIVENESS" ) != nullptr;
    if( enabled )
    {
        std::fputs( accepted ? "RWFUZZ accepted=1\n" : "RWFUZZ accepted=0\n", stderr );
    }
}

// Consume `n` leading bytes as a little-endian selector, advancing the view.
inline std::uint8_t takeByte( std::string_view& in ) noexcept
{
    if( in.empty() )
    {
        return 0;
    }
    const std::uint8_t b = std::uint8_t( in.front() );
    in.remove_prefix( 1 );
    return b;
}

}   // namespace rwfuzz
