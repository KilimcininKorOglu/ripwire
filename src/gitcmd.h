#pragma once

// gitcmd.h — THE one spelling of how ripwire starts a git child.
//
// Every git command this tool runs begins with gitCmd(), so the git-config trust boundary (githarden.h) is a
// property of the command line rather than of anything a caller has to detect first. The prefix is two
// policy options, applied to every invocation:
//
//   --no-optional-locks       ripwire's git calls are read-only. Without this, a `git status` that refreshes
//                             stat data opportunistically REWRITES the index — and with the monitor disabled
//                             that rewrite drops the index's fsmonitor extension, so the user's next status
//                             pays a full re-sync (measured, git 2.50.1). With it, the index is never written
//                             and ripwire never contends for index.lock with the user's own git.
//   -c core.fsmonitor=false   the command-line form governs the directory whatever config file would
//                             otherwise apply, and git passes it on to any git it spawns. The builtin daemon
//                             is not consulted by ripwire's own few calls either — their cost is a stat pass
//                             of the same order as the crawl ripwire already makes.
//
// The ONE git command that must not carry the prefix is githarden's `git config --get core.fsmonitor` probe:
// a command-line value would BE the answer it reads back. A config read refreshes no index and runs no hook.
// Strings that merely SHOW a git command to the user (a `next=` hint, a printed shell snippet) are not
// invocations and keep their plain spelling.
//
// Gated by test/githardencheck.sh: behavioural arms run the git-backed verbs through several root shapes and
// the MCP and --plan-lint entry points and assert a hook-form core.fsmonitor stays unfired; a PATH shim arm
// asserts every git child carries the prefix; a structural arm refuses an executed git command spelled
// outside gitCmd().

#include <string>
#include <string_view>

namespace rw
{

inline constexpr std::string_view kGitCmdPrefix = "git --no-optional-locks -c core.fsmonitor=false";

// `rest` is everything after the program name and the two policy options, starting with its own leading space
// (" -c core.quotepath=false -C "), exactly as the call site spelled it after "git" before this header existed.
inline std::string gitCmd( std::string_view rest )
{
    std::string cmd;
    cmd.reserve( kGitCmdPrefix.size() + rest.size() );
    cmd += kGitCmdPrefix;
    cmd += rest;
    return cmd;
}

}   // namespace rw
