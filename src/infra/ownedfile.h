#pragma once

// ownedfile.h — the ONE owner of a stdio stream. The destructor closes it, so no exit path can skip the close.
//
// WHY A TYPE AND NOT A HABIT. A raw `std::FILE*` is closed by whichever line the author remembered, and the line
// that forgets is the one nobody reads again: `const bool ok = ( got == want ) && ( std::fclose( fp ) == 0 );`
// short-circuits past the close on every short read, compiles clean, passes every test that reads a whole file,
// and leaks one descriptor per truncated file until a long-lived process cannot open anything. An owner makes
// that shape unwritable: the close belongs to the scope, not to a boolean expression.
//
// THE CONTRACT
//   - move-constructible only; a moved-from owner holds nothing and closes nothing;
//   - `close()` closes NOW and reports whether fclose succeeded — the one question a destructor cannot answer
//     (a writer that must know its buffered bytes reached the file asks here; a reader rarely needs to);
//   - nothing here throws, and nothing here allocates.
//
// A file DESCRIPTOR that is never wrapped in a stream wants a descriptor owner, not this one.

#include <cstdio>
#include <utility>

namespace rw
{

struct OwnedFile
{
    std::FILE* file = nullptr;

    OwnedFile() noexcept = default;
    explicit OwnedFile( std::FILE* opened ) noexcept : file( opened ) {}
    OwnedFile( const OwnedFile& )            = delete;
    OwnedFile& operator=( const OwnedFile& ) = delete;
    OwnedFile( OwnedFile&& other ) noexcept : file( std::exchange( other.file, nullptr ) ) {}
    OwnedFile& operator=( OwnedFile&& ) = delete;   // one owner per stream for its whole life: nothing reseats one
    ~OwnedFile() { (void)close(); }

    explicit operator bool() const noexcept { return file != nullptr; }

    // Close now. True when there was nothing to close or fclose succeeded; the owner is empty afterwards either way.
    bool close() noexcept
    {
        if( file == nullptr )
        {
            return true;
        }
        const bool closedOk = std::fclose( file ) == 0;
        file                = nullptr;
        return closedOk;
    }
};

// The spelling new code opens a stream with: the handle is owned before any other line can run.
inline OwnedFile openOwnedFile( const char* path, const char* mode ) noexcept
{
    return OwnedFile( std::fopen( path, mode ) );
}

}   // namespace rw
