#pragma once

// githarden.h — the git-config trust boundary (harvest round 2026-09-09).
//
// ripwire shells out to READ-ONLY git inside the analysed checkout: `status --porcelain` for the +dirty stamp
// (gitstamp.h), `ls-files --others --ignored` for the crawl's ignore set (ingest_crawl.h), `log`, `diff --numstat`,
// `archive`, `rev-parse` — 82 calls across a 13-verb sweep, logged through a PATH shim. Git honours the checkout's
// OWN .git/config, and one key there turns a read-only call into arbitrary code: a HOOK-form `core.fsmonitor` — any
// value that is not a boolean is a COMMAND git runs on every status / diff / ls-files. Measured 2026-09-09
// (test/githardencheck.sh arms A/B): a fixture hook fired three times per --situ and once per default map.
// `git clone` never copies .git/config, so a fresh clone is safe; a tarball-delivered tree, a copied worktree or a
// shared checkout is not — and ripwire runs unattended inside agent loops over directories nobody inspected.
//
// The mitigation is ONE site, applied once at process start, BEFORE any thread exists (setenv is not thread-safe)
// and before the first git child: probe each crawl root's core.fsmonitor with `git config --get` (measured inert —
// it runs no hook on the very fixture whose hook fires under `git status`); if any root configures the HOOK form,
// append `core.fsmonitor=false` to git's GIT_CONFIG_COUNT / GIT_CONFIG_KEY_n / GIT_CONFIG_VALUE_n environment
// override, which every git child inherits, and DISCLOSE it: one stderr line per root carrying
// git_harden=fsmonitor-hook, and --doctor's git-config-trust row. The environment override is scoped to the hook
// form, and a caller's own GIT_CONFIG_COUNT block is preserved; ours is appended after it, never in place of it.
//
// DETECTION IS THE DISCLOSURE; THE BOUNDARY IS THE COMMAND LINE. The neutralisation itself is the prefix every
// git child now carries (gitcmd.h: --no-optional-locks -c core.fsmonitor=false, for every form of the key, in
// every directory). What this header does is TELL the user when a root they pointed at carries the hook form,
// and keep the env override as a second layer there. Because the governing config need not sit in `root/.git`
// — it can live up the parent chain, or in a per-worktree gitdir plus a shared commondir — `gitResolvedConfigDirs`
// asks git itself (`rev-parse --absolute-git-dir --git-common-dir`, the hook disabled on that probe's OWN
// command line) which dir governs the root, and the probe and disclosure run for THAT repo whatever its depth.
//
// The trust decision is PER PROCESS: a long-lived --mcp server probes its roots once at start. A config edited
// under a running server is not re-read — the same freshness contract every other startup-only fact has here.
//
// NOT covered, and measured NOT to fire here: a `post-index-change` hook under `git status --porcelain` (git 2.50.1,
// the same fixture). Hooks are the same trust class as config, but an arm that cannot be observed to fire is not
// asserted (CONTRIBUTING §2) — so nothing is claimed for hooks. Revisit when a git version is shown to run one on
// a read-only call. The `ext::` transport is already refused at the one place a URL reaches git (main.cpp's clone).

#include "arch.h"            // rw::ciEqualAscii — the case-insensitive ASCII compare the tree already has (reused, not re-rolled)
#include "docparse.h"        // docparse::detail::readWholeFile — the canonical whole-file byte read (reused, not re-rolled)
#include "gitmine.h"         // rw::popenTrimmed — the one popen-and-trim shape in the tree (never a second)
#include "infra/emit.h"      // rw::emitTo — the house emitter; no new printf-family site
#include "gitcmd.h"         // rw::gitCmd — every git child starts with --no-optional-locks -c core.fsmonitor=false
#include "infra/jsonesc.h"   // rw::shSingleQuote

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw::githarden
{

// ── the four things core.fsmonitor can be ───────────────────────────────────────────────────────────────

enum class FsmonitorForm : std::uint8_t { Unset, Builtin, Off, Hook };

inline const char* fsmonitorFormName( FsmonitorForm form ) noexcept
{
    switch( form )
    {
        case FsmonitorForm::Unset:   { return "unset"; }
        case FsmonitorForm::Builtin: { return "builtin"; }
        case FsmonitorForm::Off:     { return "off"; }
        case FsmonitorForm::Hook:    { return "hook"; }
    }
    return "unset";
}

// git-config(1) "boolean": true/yes/on/1 and false/no/off/0, case-insensitive; a bare key (empty value) is true.
// Every other string is the hook COMMAND form. ciEqualAscii lowercases the VALUE against these lowercase spellings.
inline FsmonitorForm classifyFsmonitorValue( std::string_view value ) noexcept
{
    if( value.empty() )
    {
        return FsmonitorForm::Builtin;
    }
    for( std::string_view t : { "true", "yes", "on", "1" } )
    {
        if( ciEqualAscii( value, t ) ) { return FsmonitorForm::Builtin; }
    }
    for( std::string_view f : { "false", "no", "off", "0" } )
    {
        if( ciEqualAscii( value, f ) ) { return FsmonitorForm::Off; }
    }
    return FsmonitorForm::Hook;
}

// ── the probe ────────────────────────────────────────────────────────────────────────────────────────────
//
// `git config --get` reads config only (an include is a file read) and runs no hook — measured inert. The exit code
// travels in-band because popenTrimmed drops it, and "unset" (rc 1, empty) must be told apart from "a bare key"
// (rc 0, empty). Any failure to run git at all reads as Unset: nothing to neutralise, nothing to claim.
inline FsmonitorForm probeFsmonitorForm( const std::string& root )
{
    const std::string out  = popenTrimmed( "git -C " + shSingleQuote( root ) + " config --get core.fsmonitor 2>/dev/null; printf '\\nrc=%s' \"$?\"" );
    const std::size_t rcAt = out.rfind( "rc=" );
    if( rcAt == std::string::npos )
    {
        return FsmonitorForm::Unset;
    }
    if( std::string_view( out ).substr( rcAt + 3 ) != "0" )
    {
        return FsmonitorForm::Unset;
    }
    std::string_view value = std::string_view( out ).substr( 0, rcAt );
    while( !value.empty() && ( value.back() == '\n' || value.back() == '\r' || value.back() == ' ' ) )
    {
        value.remove_suffix( 1 );
    }
    return classifyFsmonitorValue( value );
}

// ── the cheap tier: could a LOCAL config file even carry the key? ────────────────────────────────────────────
//
// git's startup is ~10 ms on macOS (measured 2026-09-09: `git config --get` 9.9 ms median against a 68.5 ms warm
// default map — a 14% tax on the one path this tool exists to keep cheap). So the subprocess runs only when a local
// config file could possibly carry the key: the checkout's own config — `.git/config` (or, when `.git` is a FILE,
// the `gitdir:` it names, its `config.worktree`, and the `commondir` config a linked worktree shares) — contains
// the bytes "fsmonitor" or "include", case-insensitively (config keys are). A hostile value must spell the key in
// one of those files or reach it through an include/includeIf, so this is a SOUND gate on the subprocess, not a
// substitute for it: the authoritative answer is still git's (test/githardencheck.sh arms H and I pin the include
// and the worktree shapes). A global or system config is the user's own writing and is not scanned.
inline std::string trimmedFirstLine( std::string_view text )
{
    const std::size_t nl = text.find( '\n' );
    std::string_view  line = nl == std::string_view::npos ? text : text.substr( 0, nl );
    while( !line.empty() && ( line.front() == ' ' || line.front() == '\t' ) ) { line.remove_prefix( 1 ); }
    while( !line.empty() && ( line.back() == ' ' || line.back() == '\t' || line.back() == '\r' ) ) { line.remove_suffix( 1 ); }
    return std::string( line );
}

// The prefix every PROBE git call carries. The two startup probes (governing-gitdir resolution and the
// authoritative value read) run BEFORE the environment override below is installed, so each one disables
// the hook form on its OWN command line — `-c core.fsmonitor=false` — and the resolution therefore cannot
// itself trigger the very hook it is looking for. `git config --get core.fsmonitor` is the one exception:
// it must NOT carry the flag, because a command-line `-c core.fsmonitor=false` would BE the value it read
// back and mask the real one — and a plain `git config --get` refreshes no index, so it runs no hook.
inline std::string hardenedGitPrefix( const std::string& root )
{
    return gitCmd( " -C " ) + shSingleQuote( root );
}

// Resolve the GOVERNING git directory for any crawl root by asking git itself, with the hook neutralised on
// the probe's own command line, so the disclosure names the repository that actually governs the root
// whatever its depth. `--absolute-git-dir` yields the per-worktree gitdir; `--git-common-dir` yields the
// shared dir a linked worktree's config lives beside. Both are canonicalised against `root` (git's CWD) when
// git prints a relative form. The hand-rolled `root/.git` inspection below is a git-absent fallback for the
// repo-root and worktree-root shapes. Empty ⇒ not a repository, or git could not answer — nothing to probe.
inline std::vector<std::filesystem::path> gitResolvedConfigDirs( const std::string& root )
{
    std::vector<std::filesystem::path> dirs;
    const std::string out = popenTrimmed( hardenedGitPrefix( root )
                                          + " rev-parse --absolute-git-dir --git-common-dir 2>/dev/null" );
    if( out.empty() )
    {
        return dirs;
    }
    std::error_code       ec;
    const std::filesystem::path rootPath( root );
    std::size_t                 start = 0;
    while( start <= out.size() )
    {
        const std::size_t nl   = out.find( '\n', start );
        const std::size_t stop = nl == std::string::npos ? out.size() : nl;
        std::string_view  line = std::string_view( out ).substr( start, stop - start );
        while( !line.empty() && ( line.back() == '\r' || line.back() == ' ' ) ) { line.remove_suffix( 1 ); }
        if( !line.empty() )
        {
            std::filesystem::path dir( line );
            if( dir.is_relative() ) { dir = rootPath / dir; }                       // git printed it relative to its -C CWD
            dir = std::filesystem::weakly_canonical( dir, ec );
            if( ec ) { dir = std::filesystem::path( line ); ec.clear(); }
            if( std::find( dirs.begin(), dirs.end(), dir ) == dirs.end() ) { dirs.push_back( dir ); }
        }
        if( nl == std::string::npos ) { break; }
        start = nl + 1;
    }
    return dirs;
}

inline std::vector<std::filesystem::path> localConfigCandidates( const std::filesystem::path& root )
{
    std::vector<std::filesystem::path> out;

    // Authoritative first: git resolves the governing gitdir/commondir for ANY root, subdirectory and
    // worktree and GIT_DIR included. Its config, its per-worktree config.worktree, and the shared common
    // config are the files a hook value could be spelled in (directly or through an include the cheap scan
    // also catches).
    for( const std::filesystem::path& dir : gitResolvedConfigDirs( root.string() ) )
    {
        out.push_back( dir / "config" );
        out.push_back( dir / "config.worktree" );
    }
    if( !out.empty() )
    {
        return out;
    }

    // Fallback for a tree git cannot speak for (git absent, or an unreadable repo): the original root/.git
    // inspection. It handles the repo-root and worktree-root shapes only — which is why the git resolution
    // above leads, and this remains just so a git-less environment still degrades sanely.
    const std::filesystem::path        dotGit = root / ".git";
    std::error_code                    ec;
    if( std::filesystem::is_directory( dotGit, ec ) && !ec )
    {
        out.push_back( dotGit / "config" );
        out.push_back( dotGit / "config.worktree" );
        return out;
    }
    const std::string head = docparse::detail::readWholeFile( dotGit.string() ).value_or( std::string() );
    if( !head.starts_with( "gitdir:" ) )
    {
        return out;   // not a repository at all — nothing for git to read, nothing to probe
    }
    std::filesystem::path gitDir = trimmedFirstLine( std::string_view( head ).substr( 7 ) );
    if( gitDir.is_relative() )
    {
        gitDir = root / gitDir;
    }
    out.push_back( gitDir / "config" );
    out.push_back( gitDir / "config.worktree" );
    if( const std::optional<std::string> common = docparse::detail::readWholeFile( ( gitDir / "commondir" ).string() ) )
    {
        std::filesystem::path commonDir = trimmedFirstLine( *common );
        if( commonDir.is_relative() )
        {
            commonDir = gitDir / commonDir;
        }
        out.push_back( commonDir / "config" );
    }
    return out;
}

inline bool localConfigMayCarryFsmonitor( const std::string& root )
{
    for( const std::filesystem::path& candidate : localConfigCandidates( root ) )
    {
        std::optional<std::string> bytes = docparse::detail::readWholeFile( candidate.string() );
        if( !bytes )
        {
            continue;
        }
        for( char& c : *bytes )
        {
            if( c >= 'A' && c <= 'Z' ) { c = static_cast<char>( c + ( 'a' - 'A' ) ); }
        }
        if( bytes->find( "fsmonitor" ) != std::string::npos || bytes->find( "include" ) != std::string::npos )
        {
            return true;
        }
    }
    return false;
}

// ── the environment override block (git's own mechanism, git-config(1) ENVIRONMENT) ───────────────────────

inline unsigned long gitConfigCount() noexcept
{
    const char* raw = std::getenv( "GIT_CONFIG_COUNT" );
    if( raw == nullptr || *raw == '\0' )
    {
        return 0;
    }
    unsigned long n = 0;
    for( const char* p = raw; *p != '\0'; ++p )
    {
        if( *p < '0' || *p > '9' )
        {
            return 0;   // git itself rejects a non-numeric count; we then start our own block at 0 rather than guess
        }
        n = n * 10 + static_cast<unsigned long>( *p - '0' );
    }
    return n;
}

// Append one key=value AFTER whatever block the caller already set. Returns false only if setenv itself failed.
inline bool appendGitConfigOverride( const char* key, const char* value )
{
    const unsigned long n     = gitConfigCount();
    const std::string   keyN  = "GIT_CONFIG_KEY_" + std::to_string( n );
    const std::string   valN  = "GIT_CONFIG_VALUE_" + std::to_string( n );
    const std::string   count = std::to_string( n + 1 );
    return ::setenv( keyN.c_str(), key, 1 ) == 0 && ::setenv( valN.c_str(), value, 1 ) == 0 && ::setenv( "GIT_CONFIG_COUNT", count.c_str(), 1 ) == 0;
}

// ── the startup record, kept so --doctor reports the SAME probe main() acted on ─────────────────────────────
//
// --doctor cannot re-probe: once the override is in the environment, `git config --get` returns "false" for the very
// root whose file says hook — the override is designed to win. So the form seen BEFORE the override is recorded here,
// per root, and doctor reads it. One write, at startup, before any thread.
struct Report
{
    std::vector<std::pair<std::string, FsmonitorForm>> forms;      // every directory root probed, in argv order
    bool                                               applied = false;
};

inline Report g_startup;

inline FsmonitorForm startupFormFor( std::string_view root ) noexcept
{
    for( const auto& [ r, form ] : g_startup.forms )
    {
        if( r == root )
        {
            return form;
        }
    }
    return FsmonitorForm::Unset;
}

// Call ONCE from main(), after parseArgs and before any thread or git subprocess. A root that is not a directory
// (a git URL, which git itself clones fresh — its config is never hostile) is skipped.
inline const Report& hardenForRoots( std::span<const std::string_view> roots )
{
    Report& r = g_startup;
    r.forms.clear();
    r.applied = false;
    bool anyHook = false;
    for( std::string_view root : roots )
    {
        std::error_code ec;
        if( root.empty() || !std::filesystem::is_directory( std::filesystem::path( root ), ec ) || ec )
        {
            continue;
        }
        const std::string   rootStr = std::string( root );
        const FsmonitorForm form    = localConfigMayCarryFsmonitor( rootStr ) ? probeFsmonitorForm( rootStr ) : FsmonitorForm::Unset;
        r.forms.emplace_back( rootStr, form );
        anyHook = anyHook || form == FsmonitorForm::Hook;
    }
    if( !anyHook )
    {
        return r;
    }
    r.applied = appendGitConfigOverride( "core.fsmonitor", "false" );
    for( const auto& [ root, form ] : r.forms )
    {
        if( form == FsmonitorForm::Hook )
        {
            emitTo( stderr, "ripwire: git: {} configures core.fsmonitor as a hook COMMAND — neutralised for this run (git_harden=fsmonitor-hook): ripwire's git calls are read-only, and every one runs with core.fsmonitor=false\n", root );
        }
    }
    return r;
}

}   // namespace rw::githarden
