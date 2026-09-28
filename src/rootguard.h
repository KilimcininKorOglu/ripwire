#pragma once

// rootguard.h — #350 layer 1: a root nobody chose is never crawled when it is a home or system directory.
//
// The incident behind it: an MCP server started in a home directory that was not a git repository crawled the whole
// tree for seven hours and reached a 67 GB footprint. A root the user did not name — the MCP server's launch
// directory, a CLI run with no positional root — is refused when it IS $HOME (a dotfiles git repository included:
// being a repository does not make a home directory a project), a filesystem or drive root, or one of the operating
// system's own trees (os::path_is_system_dir). The refusal is one line that names the directory and the fix.
//
// EXPLICIT IS HONOURED. `ripwire ~`, `ripwire / --grep=x`, `ripwire <root> --mcp` and an MCP request's `path=` are all
// choices somebody typed, and they are answered — the memory guard (memguard.h) is what protects those runs.
// Subdirectories (~/code/proj, /usr/local/src/x) are ordinary directories and never refused here.

#include <climits>
#include <cstdlib>
#include <string>

#include "infra/os.h"   // rw::os::realpath / getcwd / path_is_system_dir

namespace rw
{

// the realpath of `path` when it resolves, else `path` as given
inline std::string rootGuardCanon( const char* path )
{
    char buf[ PATH_MAX ];
    if( path != nullptr && os::realpath( path, buf ) != nullptr )
    {
        return std::string( buf );
    }
    return path != nullptr ? std::string( path ) : std::string();
}

// the canonical current directory, or "" when getcwd fails
inline std::string rootGuardCwd()
{
    char buf[ PATH_MAX ];
    if( os::getcwd( buf, sizeof( buf ) ) == nullptr )
    {
        return {};
    }
    return rootGuardCanon( buf );
}

// "" when `canonDir` may serve as an implicit root; otherwise the one-line reason it may not. `canonDir` is already
// canonical (rootGuardCanon / rootGuardCwd), and so is the $HOME it is compared with.
inline std::string noProjectRootReason( const std::string& canonDir )
{
    if( canonDir.empty() )
    {
        return {};
    }
    const char* const home   = std::getenv( "HOME" );
    const bool        isHome = home != nullptr && *home != '\0' && canonDir == rootGuardCanon( home );
    if( !isHome && !os::path_is_system_dir( canonDir ) )
    {
        return {};
    }
    return "no project root: " + canonDir + " is a home/system directory; pass a project path";
}

}   // namespace rw
