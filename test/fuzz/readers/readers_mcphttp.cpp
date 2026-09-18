// readers_mcphttp.cpp — crash-fuzz entry point for `ripwire --mcp --listen`'s HTTP request reader. The input is
// written into one end of a connected socket pair and the write side shut down, so readRequest sees exactly the
// bytes a client sent and then EOF — never a stall. Oracle: no sanitizer report, no trap, no ASSUME, no throw.

#include "fuzzsupport.h"

#include "editpreview.h"   // main.cpp includes it before mcp.h, which reads editpreview:: — the same order here
#include "mcpserver.h"

#include <cstddef>
#include <cstdint>
#include <sys/socket.h>
#include <unistd.h>

namespace rwfuzz
{

namespace
{

// Both ends of a socket pair, closed on every path.
struct SocketPair
{
    int fds[ 2 ] = { -1, -1 };
    SocketPair()
    {
        if( ::socketpair( AF_UNIX, SOCK_STREAM, 0, fds ) != 0 )
        {
            std::abort();
        }
        const int bufBytes = 1 << 20;
        (void)::setsockopt( fds[ 0 ], SOL_SOCKET, SO_SNDBUF, &bufBytes, sizeof( bufBytes ) );
        (void)::setsockopt( fds[ 1 ], SOL_SOCKET, SO_RCVBUF, &bufBytes, sizeof( bufBytes ) );
    }
    ~SocketPair()
    {
        for( const int fd : fds )
        {
            if( fd >= 0 )
            {
                ::close( fd );
            }
        }
    }
    SocketPair( const SocketPair& )            = delete;
    SocketPair& operator=( const SocketPair& ) = delete;
};

}   // namespace

int mcphttp( const std::uint8_t* data, std::size_t size )
{
    if( size > ( 1u << 19 ) )
    {
        return 0;   // stays under the socket buffer, so the single-threaded write below cannot block
    }
    SocketPair  pair;
    std::size_t written = 0;
    while( written < size )
    {
        const ssize_t n = ::write( pair.fds[ 0 ], data + written, size - written );
        if( n <= 0 )
        {
            std::abort();
        }
        written += std::size_t( n );
    }
    ::shutdown( pair.fds[ 0 ], SHUT_WR );
    bool tooManyHeaderBytes = false;
    bool tooLargeBody       = false;
    noteAccepted( rw::mcphttp::readRequest( pair.fds[ 1 ], tooManyHeaderBytes, tooLargeBody ).ok );
    return 0;
}

}   // namespace rwfuzz
