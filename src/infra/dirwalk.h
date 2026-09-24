#pragma once

// dirwalk.h — the ONE "walk up from a file to a crawl-root boundary, testing each directory" primitive.
//
// pythonrunner.h's hasPytestProject (nearest pytest config: pytest.ini / conftest.py / a recognized
// pyproject.toml or setup.cfg section) and jsrunner.h's nearestPackageJson (#323, nearest package.json)
// are the SAME walk over two different per-directory predicates: start at a file's own directory, climb
// to the crawl root inclusive, stop at the first directory that matches. --quality-delta's duplication
// kind flagged the pair the moment jsrunner.h landed — the same shape jsonesc.h's own W2-M0 note
// describes for jsonStringEnd, and the same fix: the walk moves here, once, and each caller keeps its
// own predicate and its own return type (a bool for "found", a string for "found — here are its bytes").

#include <filesystem>
#include <string>
#include <string_view>

namespace rw::dirwalk
{

/// Call `atDir` for each directory from `file`'s own parent up to `root`, inclusive, in that order,
/// stopping at the first one `atDir` returns true for (and returning true). Paths are normalized
/// lexically; an empty or unresolvable `root`, or a `file` outside it, visits no directory and returns
/// false. `atDir` must not throw and must not retain the path past its own call.
template<class AtDirPredicate>
inline bool ascendToRoot( const std::string& file, std::string_view root, AtDirPredicate atDir )
{
    namespace fs = std::filesystem;
    if( root.empty() )
    {
        return false;   // no known crawl boundary: never search past it (never inherit an unrelated parent)
    }
    std::error_code ec;
    fs::path boundary = fs::absolute( fs::path( root ), ec ).lexically_normal();
    if( ec )
    {
        return false;
    }
    // absolute(".") normalizes to a trailing separator, while parent_path() does not. They are one root.
    if( boundary.has_relative_path() && boundary.filename().empty() )
    {
        boundary = boundary.parent_path();
    }
    fs::path dir = fs::absolute( fs::path( file ), ec ).lexically_normal().parent_path();
    const fs::path relative = dir.lexically_relative( boundary );
    if( ec || relative.empty() || *relative.begin() == ".." )
    {
        return false;
    }
    for( ;; dir = dir.parent_path() )
    {
        if( atDir( dir ) )
        {
            return true;
        }
        if( dir == boundary || dir == dir.parent_path() )
        {
            return false;
        }
    }
}

} // namespace rw::dirwalk
