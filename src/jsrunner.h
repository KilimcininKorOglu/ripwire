#pragma once

// jsrunner.h — #323: TS/JS test-runner evidence. Before this file, testmap.h's TestRunnerIndex derived a
// runner for exactly two script kinds (bash .sh, python3/pytest .py) — no .ts/.js/.tsx/.jsx entry existed,
// so every TS/JS test row carried run_unknown="1" forever (testmap.h's own M21(b) disclosure), even after
// the suite had been run and passed. The reporter's own measurement: 154 of 154 --test-gate runs over three
// days on a vitest project hit this, because the gate exits 4 whenever the tests-to-run list is non-empty
// and no TS/JS row could ever clear it.
//
// EVIDENCE, NEVER A GUESS — same rule pythonrunner.h already applies to Python: a runner is derived ONLY
// from bytes actually present in the repo (here, the nearest package.json's own "scripts"/"dependencies"/
// "devDependencies"), and an absent or inconclusive manifest yields NO command, exactly like a Python test
// file with no main-guard and no pytest project — testmap.h's runHint family turns that "" into
// run_unknown="1", never a fabricated default. The three cases this derives are the three the issue names
// and nothing else: `vitest` or `jest` named as a scripts.test runner or a dependency/devDependency ⇒ the
// corresponding CLI invocation; a scripts.test that runs node's OWN built-in runner (`node --test`) names
// itself directly — there is no package to depend on for it.
//
// NEAREST MANIFEST, WALKING UP (mirrors pythonrunner::hasPytestProject exactly): monorepo/workspace layouts
// are common (the issue's own point 1), so the search starts at the test file's own directory and climbs to
// the crawl root, inclusive, stopping at the first package.json found. The command is still spelled ROOT-
// RELATIVE, same as every other run= this codebase emits (testmap.h::spellUncached) — a package.json found
// in a subdirectory is evidence of WHICH runner, not a cd target; running the emitted command may need the
// reader's own shell to be inside that subdirectory on a workspace where the runner is not hoisted to the
// crawl root's node_modules. That is a stated scope limit (see the fix report), not a silent one: it is the
// SAME limit testmap.h's Python branch already carries (a nested pyproject.toml is evidence, not a `cd`).
//
// LANGUAGE NEUTRALITY (BRIEF_COMMON, standing house rule): the mechanism — walk up from a test file to the
// nearest project manifest and read its OWN declared scripts/dependencies as evidence, never guess — is the
// same shape pythonrunner.h already uses for Python (nearest pytest config) and the one testmap.h's shell
// branch trivially satisfies (a runnable script IS its own runner, no manifest needed). It is NOT extended
// here to the other languages testmap.h indexes test files for (Kotlin, Java, Ruby, Go, Rust, Swift, C#,
// Bash beyond .sh): Bash's .sh case above already has a runner (verb="bash", no evidence needed beyond the
// extension); Kotlin/Java build their test command from Gradle/Maven, not a single JSON manifest this file's
// shape can read; Ruby's is a Gemfile plus a Rakefile, same shape gap; Go's `go test` needs no manifest
// evidence at all (there is only ever the one command, so `go.mod`'s presence would be sufficient, but no
// issue reports that gap and it is out of scope for #323, which is TS/JS only); Rust/Swift/C# were not
// reported and are not audited here. This is a stated scope limit, not a silent one — see the fix report.

#include "docparse.h"

#include <filesystem>
#include <string>
#include <string_view>

namespace rw::jsrunner
{

namespace detail
{

// Advance `p` (at the opening quote) past a JSON string; malformed input (no closing quote) advances to
// the end, which the caller's loop treats as "no more evidence", the same degrade an unparseable file gets.
inline void skipString( std::string_view s, std::size_t& p ) noexcept
{
    if( p >= s.size() || s[p] != '"' )
    {
        return;
    }
    ++p;
    while( p < s.size() && s[p] != '"' )
    {
        p += ( s[p] == '\\' && p + 1 < s.size() ) ? 2 : 1;
    }
    if( p < s.size() )
    {
        ++p;
    }
}

// Read the JSON string starting at `p` (the opening quote) and advance `p` past its closing quote.
// Minimal unescaping (the same "keep the byte after a backslash" rule resolve.h::parseTsconfigPaths uses) —
// package.json keys and the evidence values this file compares are all plain ASCII in every real corpus.
inline std::string readQuoted( std::string_view s, std::size_t& p )
{
    std::string out;
    if( p >= s.size() || s[p] != '"' )
    {
        return out;
    }
    ++p;
    while( p < s.size() && s[p] != '"' )
    {
        if( s[p] == '\\' && p + 1 < s.size() )
        {
            out.push_back( s[p + 1] );
            p += 2;
            continue;
        }
        out.push_back( s[p] );
        ++p;
    }
    if( p < s.size() )
    {
        ++p;
    }
    return out;
}

// The byte range (begin,end) of the FIRST top-level `"key": { ... }` object VALUE in `json` — package.json's
// own top level ("scripts", "dependencies", "devDependencies" are SIBLINGS, never nested in one another), so
// only a depth-1 key is a match; a same-named key inside some other object (e.g. a "scripts" key nested
// inside an unrelated config blob) is not evidence. A non-object value (or an absent key) yields npos/npos.
struct ObjSpan
{
    std::size_t begin = std::string_view::npos;
    std::size_t end   = std::string_view::npos;
};

inline ObjSpan topLevelObjectBody( std::string_view json, std::string_view key )
{
    std::size_t p     = 0;
    int         depth = 0;
    while( p < json.size() )
    {
        const char c = json[p];
        if( c == '"' )
        {
            const std::string k = readQuoted( json, p );
            if( depth == 1 && k == key )
            {
                std::size_t colon = json.find( ':', p );
                if( colon == std::string_view::npos )
                {
                    return {};
                }
                std::size_t v = colon + 1;
                while( v < json.size() && ( json[v] == ' ' || json[v] == '\t' || json[v] == '\n' || json[v] == '\r' ) )
                {
                    ++v;
                }
                if( v >= json.size() || json[v] != '{' )
                {
                    return {};   // scripts/dependencies must be an object; anything else is not this shape
                }
                const std::size_t objStart = v + 1;
                int                d       = 0;
                for( ; v < json.size(); ++v )
                {
                    if( json[v] == '"' )
                    {
                        skipString( json, v );
                        --v;   // the for-loop's ++v re-lands exactly past the string
                        continue;
                    }
                    if( json[v] == '{' )
                    {
                        ++d;
                    }
                    else if( json[v] == '}' )
                    {
                        --d;
                        if( d == 0 )
                        {
                            return { objStart, v };
                        }
                    }
                }
                return {};   // unterminated object: malformed input, no evidence
            }
            continue;   // p already advanced past this string by readQuoted
        }
        if( c == '{' || c == '[' )
        {
            ++depth;
        }
        else if( c == '}' || c == ']' )
        {
            --depth;
        }
        ++p;
    }
    return {};
}

// Whether `body` (an object's byte span, exclusive of its braces) declares `name` as one of its OWN keys.
// Values are skipped whole (string or otherwise) so a version specifier that happens to contain `name` as a
// substring (a scoped package, a git URL) is never mistaken for a key match.
inline bool hasKey( std::string_view body, std::string_view name )
{
    std::size_t p = 0;
    while( p < body.size() )
    {
        while( p < body.size() && ( body[p] == ' ' || body[p] == '\t' || body[p] == '\n' || body[p] == '\r' || body[p] == ',' ) )
        {
            ++p;
        }
        if( p >= body.size() || body[p] != '"' )
        {
            break;   // not a key-shaped byte: malformed or exhausted — no more evidence to read
        }
        const std::string key = readQuoted( body, p );
        const std::size_t colon = body.find( ':', p );
        if( colon == std::string_view::npos )
        {
            break;
        }
        p = colon + 1;
        while( p < body.size() && ( body[p] == ' ' || body[p] == '\t' ) )
        {
            ++p;
        }
        if( key == name )
        {
            return true;
        }
        if( p < body.size() && body[p] == '"' )
        {
            skipString( body, p );
        }
        else
        {
            while( p < body.size() && body[p] != ',' && body[p] != '}' )   // a non-string value: skip to its end
            {
                ++p;
            }
        }
    }
    return false;
}

// The string VALUE of `body`'s `key` entry, or "" when absent or not a string (an object/array/number test
// script is not a shape this tool spells, and "" is exactly the "no evidence" reading every other caller here
// already uses for an absent field).
inline std::string stringValue( std::string_view body, std::string_view key )
{
    std::size_t p = 0;
    while( p < body.size() )
    {
        while( p < body.size() && ( body[p] == ' ' || body[p] == '\t' || body[p] == '\n' || body[p] == '\r' || body[p] == ',' ) )
        {
            ++p;
        }
        if( p >= body.size() || body[p] != '"' )
        {
            break;
        }
        const std::string k     = readQuoted( body, p );
        const std::size_t colon = body.find( ':', p );
        if( colon == std::string_view::npos )
        {
            break;
        }
        p = colon + 1;
        while( p < body.size() && ( body[p] == ' ' || body[p] == '\t' ) )
        {
            ++p;
        }
        const bool isStr = p < body.size() && body[p] == '"';
        if( k == key )
        {
            return isStr ? readQuoted( body, p ) : std::string();
        }
        if( isStr )
        {
            skipString( body, p );
        }
        else
        {
            while( p < body.size() && body[p] != ',' && body[p] != '}' )
            {
                ++p;
            }
        }
    }
    return {};
}

} // namespace detail

/// Whether `dependencies` or `devDependencies` (either one — testmap.h's callers do not care which) names
/// `pkg` as a declared package. package.json bytes are external input; unparseable or absent input reads as
/// "no evidence", the same degrade the caller (detectFramework) already returns for every other miss.
inline bool hasDependency( std::string_view packageJson, std::string_view pkg )
{
    for( std::string_view key : { std::string_view( "dependencies" ), std::string_view( "devDependencies" ) } )
    {
        const detail::ObjSpan obj = detail::topLevelObjectBody( packageJson, key );
        if( obj.begin != std::string_view::npos && detail::hasKey( packageJson.substr( obj.begin, obj.end - obj.begin ), pkg ) )
        {
            return true;
        }
    }
    return false;
}

/// The literal `scripts.test` command string, or "" when package.json has no such field.
inline std::string testScript( std::string_view packageJson )
{
    const detail::ObjSpan obj = detail::topLevelObjectBody( packageJson, "scripts" );
    if( obj.begin == std::string_view::npos )
    {
        return {};
    }
    return detail::stringValue( packageJson.substr( obj.begin, obj.end - obj.begin ), "test" );
}

// The three runners #323 names, and nothing else — a fourth framework (mocha, ava, tap, jasmine…) is a
// bigger ask than "a package.json reader" and stays run_unknown="1" until its own issue asks for it (the
// issue's own wording: "any ONE of these would help", not "every framework").
enum class Framework : std::uint8_t { None, Vitest, Jest, NodeTest };

/// Evidence-only framework detection: `scripts.test` naming a framework wins over a bare dependency (a repo
/// can depend on vitest for its config types while its actual `test` script still runs something else), and
/// node's OWN test runner has no package to depend on, so it is recognized ONLY by its scripts.test spelling.
inline Framework detectFramework( std::string_view packageJson )
{
    const std::string script = testScript( packageJson );
    if( script.find( "vitest" ) != std::string::npos )
    {
        return Framework::Vitest;
    }
    if( script.find( "jest" ) != std::string::npos )
    {
        return Framework::Jest;
    }
    if( script.find( "node --test" ) != std::string::npos || script.find( "node --experimental-test-runner" ) != std::string::npos )
    {
        return Framework::NodeTest;
    }
    if( hasDependency( packageJson, "vitest" ) )
    {
        return Framework::Vitest;
    }
    if( hasDependency( packageJson, "jest" ) )
    {
        return Framework::Jest;
    }
    return Framework::None;   // no scripts.test naming a known runner, no vitest/jest dependency: undecidable
}

/// The CLI verb for a detected framework, or nullptr for `Framework::None` — nullptr propagates to testmap.h
/// as "no runner", the same contract runnerVerb() already uses for an unrecognized extension.
inline const char* verbFor( Framework fw ) noexcept
{
    switch( fw )
    {
        case Framework::Vitest:   return "npx vitest run";
        case Framework::Jest:     return "npx jest";
        case Framework::NodeTest: return "node --test";
        case Framework::None:     return nullptr;
    }
    return nullptr;   // a byte past the enum; a new Framework is a -Werror=switch error above, never a silent guess
}

/// Search from `file`'s own directory through `root`, inclusive, for the nearest package.json and return its
/// bytes, or "" when none is found. Mirrors pythonrunner::hasPytestProject's walk exactly (same boundary and
/// symlink rules) — monorepo/workspace test files are common (the issue's own point 1), so the search starts
/// at the test file, not at the crawl root, and stops at the FIRST manifest found on the way up.
inline std::string nearestPackageJson( const std::string& file, std::string_view root )
{
    namespace fs = std::filesystem;
    if( root.empty() )
    {
        return {};   // no known crawl boundary: do not read a manifest outside it (pythonrunner's same rule)
    }
    std::error_code ec;
    fs::path boundary = fs::absolute( fs::path( root ), ec ).lexically_normal();
    if( ec )
    {
        return {};
    }
    if( boundary.has_relative_path() && boundary.filename().empty() )   // absolute(".") keeps a trailing separator
    {
        boundary = boundary.parent_path();
    }
    fs::path dir = fs::absolute( fs::path( file ), ec ).lexically_normal().parent_path();
    const fs::path relative = dir.lexically_relative( boundary );
    if( ec || relative.empty() || *relative.begin() == ".." )
    {
        return {};
    }
    for( ;; dir = dir.parent_path() )
    {
        std::error_code sec;
        const fs::path candidate = dir / "package.json";
        if( fs::is_regular_file( fs::symlink_status( candidate, sec ) ) )   // never follow a manifest symlink out of the project
        {
            if( std::string bytes = docparse::detail::readWholeFile( candidate.string() ).value_or( "" ); !bytes.empty() )
            {
                return bytes;
            }
        }
        if( dir == boundary || dir == dir.parent_path() )
        {
            return {};
        }
    }
}

} // namespace rw::jsrunner
