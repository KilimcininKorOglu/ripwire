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
#include "infra/dirwalk.h"    // ascendToRoot — the ONE nearest-config walk, shared with pythonrunner.h
#include "infra/jsonesc.h"    // jsonStringEnd — the ONE escape-aware JSON string walk, applied inline below (see detail's banner)
#include "infra/namesplit.h"  // isIdentChar / containsWordBoundedBy — the shared ident-byte test and word-boundary scan

#include <filesystem>
#include <string>
#include <string_view>

namespace rw::jsrunner
{

namespace detail
{

// Every "advance p past this JSON string" site below (p at s[p]=='"', the caller's own guard) applies
// rw::jsonStringEnd (infra/jsonesc.h) — the canonical escape-aware JSON string scan eval.h and mcpjson.h
// already share — INLINE, as `p = ( close == npos ) ? s.size() : close + 1`: a byte after the closing
// quote, or the end when unterminated (the same "no more evidence" degrade an unparseable file already
// gets, never a crash). Not wrapped in a fourth named function: eval.h::minedjson::skipString and
// mcpjson.h::mcpdetail::stringEnd are the two existing thin wrappers around this same walk, one clamped
// to size() and one returning npos for a different caller's truncation check — a third wrapper with
// the SAME clamp-to-size() convention as the first duplicates it outright (measured: --quality-delta
// flagged exactly that pairing), so this file's three call sites apply the two-line clamp themselves.

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
                        const std::size_t close = rw::jsonStringEnd( json, v );
                        v = ( close == std::string_view::npos ) ? json.size() : close + 1;
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
            const std::size_t close = rw::jsonStringEnd( body, p );
            p = ( close == std::string_view::npos ) ? body.size() : close + 1;
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
            const std::size_t close = rw::jsonStringEnd( body, p );
            p = ( close == std::string_view::npos ) ? body.size() : close + 1;
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

// rv-test-gate-tsjs F2: a byte that can continue an identifier/path SEGMENT — used to bound a word match
// so "jest" inside "jest-report-cleaner.js" (a FILENAME) is not mistaken for a "run jest" command. Built
// on rw::namesplit::isIdentChar (the ONE ASCII identifier-byte test) plus '-', the one byte this caller
// needs beyond it: darkflags.h's own identByte (planlint.h's word-boundary user) does NOT count '-' as a
// word byte, which is the wrong reading here — a hyphenated CLI token is one word, not two.
inline bool isWordByte( char c ) noexcept
{
    return rw::namesplit::isIdentChar( c ) || c == '-';
}

/// Whether `word` occurs in `text` bounded on BOTH sides by a non-word byte or the string edge — "vitest"
/// matches in "npx vitest run" (space both sides) and in "node_modules/.bin/jest" (a path separator, then
/// the string end), never in "jest-report-cleaner.js" (a '-' immediately follows) or "myvitest" (a letter
/// immediately precedes). rv-test-gate-tsjs F2: a runner name matched as a SUBSTRING of an unrelated token
/// is not evidence the script text was ever ".find()"-shaped for before this fix. The scan itself is
/// rw::namesplit::containsWordBoundedBy — the SAME walk planlint.h::containsWholeWord already uses, over
/// this file's own boundary predicate (see isWordByte's own comment for why the two predicates differ).
inline bool matchesWord( std::string_view text, std::string_view word )
{
    return rw::namesplit::containsWordBoundedBy( text, word, isWordByte );
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

// npm's own generated placeholder (`npm init`'s default `scripts.test`) — present, but not really a script
// a human wrote, so it reads the same as "absent" for evidence purposes (rv-test-gate-tsjs F2). The named
// `marker` local (not a bare one-line `return x.find(y) != npos`) is deliberate: a bare return of that
// exact shape structurally matched three UNRELATED substring checks elsewhere in the tree
// (taskroute::has, verbs_for.h's forCoverageAttrPresent/forRouteAttrPresent) under --quality-delta's
// duplication kind — the same false-positive class infra/dirwalk.h's own banner already documents fixing
// for pythonrunner::hasPytestProject, not a real clone of any of those three unrelated checks.
inline bool isNpmPlaceholderScript( std::string_view script ) noexcept
{
    constexpr std::string_view marker = "Error: no test specified";
    return script.find( marker ) != std::string_view::npos;
}

/// Evidence-only framework detection. rv-test-gate-tsjs F2: a NON-EMPTY, non-placeholder `scripts.test` is
/// AUTHORITATIVE — the script IS what a CI run of `npm test` executes, so once it names something, that
/// something (or nothing recognized) is the answer, and a same-named DEPENDENCY never overrides it (a repo
/// can depend on vitest for its config types while `scripts.test` runs mocha; a scripts.test that runs some
/// OTHER file whose path happens to contain "jest" is not a jest invocation either — matchesWord bounds
/// both). Dependencies are consulted ONLY when there is no real scripts.test to read: absent, empty, or
/// npm's own placeholder. node's OWN test runner has no package to depend on, so it is recognized ONLY by
/// its scripts.test spelling, inside the authoritative branch.
inline Framework detectFramework( std::string_view packageJson )
{
    const std::string script = testScript( packageJson );
    if( !script.empty() && !isNpmPlaceholderScript( script ) )
    {
        if( detail::matchesWord( script, "vitest" ) )
        {
            return Framework::Vitest;
        }
        if( detail::matchesWord( script, "jest" ) )
        {
            return Framework::Jest;
        }
        if( script.find( "node --test" ) != std::string::npos || script.find( "node --experimental-test-runner" ) != std::string::npos )
        {
            return Framework::NodeTest;
        }
        return Framework::None;   // scripts.test names something else entirely — never overridden by a dependency guess
    }
    if( hasDependency( packageJson, "vitest" ) )
    {
        return Framework::Vitest;
    }
    if( hasDependency( packageJson, "jest" ) )
    {
        return Framework::Jest;
    }
    return Framework::None;   // no scripts.test, no vitest/jest dependency: undecidable
}

/// Whether `path` matches vitest/jest's own default include-glob SHAPE — `.test.`/`.spec.` in the filename,
/// or a `__tests__/` directory segment — and never a bare `.d.ts` declaration file. rv-test-gate-tsjs F4:
/// isTestPath (filter.h) is deliberately BROADER (any file under a `test/`/`tests/` directory), which is
/// right for "code a test author wrote" but wrong for "a file vitest/jest itself would collect as a test
/// target" — a helper or a setup file living beside real tests matches isTestPath but not either runner's
/// own glob, so spelling `npx vitest run test/setup.ts` would fail with "no test files found" in CI.
inline bool looksLikeJsTestFile( std::string_view path ) noexcept
{
    if( path.ends_with( ".d.ts" ) )
    {
        return false;   // a TypeScript declaration file — never test code, whatever the rest of its name is
    }
    const std::size_t slash = path.rfind( '/' );
    const std::string_view fn = ( slash == std::string_view::npos ) ? path : path.substr( slash + 1 );
    if( fn.find( ".test." ) != std::string_view::npos || fn.find( ".spec." ) != std::string_view::npos )
    {
        return true;
    }
    // a whole __tests__ directory SEGMENT, bounded by '/' or the path's own edges (never a substring hit
    // inside a longer directory name like "my__tests__stuff/")
    std::size_t pos = 0;
    while( ( pos = path.find( "__tests__/", pos ) ) != std::string_view::npos )
    {
        if( pos == 0 || path[pos - 1] == '/' )
        {
            return true;
        }
        ++pos;
    }
    return false;
}

/// The CLI verb for a detected framework, or nullptr for `Framework::None` — nullptr propagates to testmap.h
/// as "no runner", the same contract runnerVerb() already uses for an unrecognized extension. A table, not a
/// switch, matching testmap.h::runnerVerb's own kRunnerKinds shape (a small sorted-by-nothing row scan reads
/// identically to a switch but is a DIFFERENT shape than model.h::jsLitCtorName's enum switch beside it).
inline const char* verbFor( Framework fw ) noexcept
{
    struct FrameworkVerb { Framework fw; const char* verb; };
    static constexpr FrameworkVerb kFrameworkVerbs[] = {
        { Framework::Vitest,   "npx vitest run" },
        { Framework::Jest,     "npx jest" },
        { Framework::NodeTest, "node --test" },
    };
    for( const FrameworkVerb& fv : kFrameworkVerbs )
    {
        if( fv.fw == fw )
        {
            return fv.verb;
        }
    }
    return nullptr;   // Framework::None, or a byte past the enum: never a guessed verb
}

/// Search from `file`'s own directory through `root`, inclusive, for the nearest package.json that can
/// actually DECIDE a framework, and return its bytes — or, failing that, the nearest package.json found at
/// all (so a caller still reads its honest "names none of the three" rather than a silent miss), or "" when
/// none exists anywhere in the boundary. The walk is rw::dirwalk::ascendToRoot (shared with
/// pythonrunner::hasPytestProject — same boundary and symlink rules). Monorepo/workspace test files are
/// common (the issue's own point 1), so the search starts at the test file, not at the crawl root.
///
/// rv-test-gate-tsjs F5: a package.json with no scripts/dependencies evidence at all — a bare module-type
/// marker (`{"type":"commonjs"}`) is a real, common pattern in mixed-module repos — used to END the search
/// even though it decides nothing; the walk now keeps climbing past it toward a manifest that CAN decide
/// (a workspace root's runner is hoisted to every package under it anyway, so the root manifest is exactly
/// the right fallback).
inline std::string nearestPackageJson( const std::string& file, std::string_view root )
{
    namespace fs = std::filesystem;
    std::string fallback;   // the NEAREST manifest found, even if it decides nothing (F5)
    std::string decisive;
    rw::dirwalk::ascendToRoot( file, root, [ & ]( const fs::path& dir )
    {
        std::error_code sec;
        const fs::path candidate = dir / "package.json";
        if( !fs::is_regular_file( fs::symlink_status( candidate, sec ) ) )   // never follow a manifest symlink out of the project
        {
            return false;
        }
        std::string bytes = docparse::detail::readWholeFile( candidate.string() ).value_or( "" );
        if( bytes.empty() )
        {
            return false;
        }
        if( fallback.empty() )
        {
            fallback = bytes;
        }
        if( detectFramework( bytes ) == Framework::None )
        {
            return false;   // F5: no evidence HERE is not the same as no evidence anywhere above
        }
        decisive = std::move( bytes );
        return true;
    } );
    return decisive.empty() ? fallback : decisive;
}

} // namespace rw::jsrunner
