// fuzz_reader.cpp — the libFuzzer entry point for ONE reader, chosen at compile time by RIPWIRE_FUZZ_READER (see
// add_ripwire_reader_fuzzer in CMakeLists.txt). The reader bodies live in readers_*.cpp, compiled once each into
// the ripwire_fuzz_readers static library, so N targets cost N tiny compiles, not N copies of quality.h.

#include <cstddef>
#include <cstdint>

#if !defined( RIPWIRE_FUZZ_READER )
#error "RIPWIRE_FUZZ_READER must name one rwfuzz:: reader entry point (readers_*.cpp)"
#endif

namespace rwfuzz
{
int RIPWIRE_FUZZ_READER( const std::uint8_t* data, std::size_t size );
}

extern "C" int LLVMFuzzerTestOneInput( const std::uint8_t* data, std::size_t size )
{
    return rwfuzz::RIPWIRE_FUZZ_READER( data, size );
}
