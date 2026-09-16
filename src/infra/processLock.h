#pragma once

#include "Diagnostics.h"
#include "os.h"

#include <cerrno>
#include <cstdio>
#include <string>

namespace rw::infra
{

// A stable lockfile whose inode survives cache publishes. The kernel releases the lock when the owning
// process exits, so a crashed caller cannot leave a stale lock that blocks future runs.
class ProcessLock
{
public:
    explicit ProcessLock( const std::string& lockPath )
    {
        fd_ = rw::os::open( lockPath.c_str(), O_RDWR | O_CREAT | O_CLOEXEC, 0600 );
        if( fd_ < 0 )
        {
            DEGRADED_PATH_ALERT( "process lockfile open failed; continuing without cross-process serialization" );
            std::fprintf( stderr, "process lock unavailable; continuing without cross-process serialization\n" );
            return;
        }

        for( ;; )
        {
            if( rw::os::flock( fd_, LOCK_EX ) == 0 )
            {
                locked_ = true;
                return;
            }
            if( errno != EINTR )
            {
                DEGRADED_PATH_ALERT( "process lock acquire failed; continuing without cross-process serialization" );
                std::fprintf( stderr, "process lock acquire failed; continuing without cross-process serialization\n" );
                return;
            }
        }
    }

    ~ProcessLock()
    {
        if( fd_ >= 0 )
        {
            if( locked_ )
            {
                rw::os::flock( fd_, LOCK_UN );
            }
            rw::os::close( fd_ );
        }
    }

    ProcessLock( const ProcessLock& )            = delete;
    ProcessLock& operator=( const ProcessLock& ) = delete;

private:
    int  fd_     = -1;
    bool locked_ = false;
};

}   // namespace rw::infra
