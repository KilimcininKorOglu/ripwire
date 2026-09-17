#pragma once

// regexguard.h — THE owner of user-authored regular expressions: the structural screen, the compile, and the
// match. Every pattern a user writes — `--regex`, `--graph-query file()`, an `--arch` path-rule, a `#match?` /
// `#not-match?` predicate in `--match` or `--lint-rules` — is compiled by compileGuardedRegex and matched
// through a GuardedRegex. No other file in src/ spells std::regex (test/regexguardcheck.sh arm (c)).
//
// WHY A SEAM. The screen used to live in src/search.h beside `--regex`, the one entry point that called it. The
// other three handed a user's pattern straight to the standard library, and a regex_error thrown there had no
// handler:
//
//     ripwire <dir> --graph-query='file(all,"(a+)+z")'          rc=134  uncaught std::regex_error (libc++)
//     ripwire <dir> --arch=rules   (deny path zz/.* -> (a+)+z)   rc=134  the same abort
//     ripwire <dir> --match='… (#match? @id "(a+)+z")'           rc=0    the throw was swallowed, the row KEPT
//
// Each copy of "compile a user's regex" had grown its own policy — screened or not, catch the compile or not,
// catch the match or not, keep or drop on a throw — and the differences were the bugs. One owner gives every
// entry point the same three verdicts: a named refusal before any engine sees the pattern, a named refusal
// when the engine gives up mid-match, or an answer.
//
// WHAT A CALL SITE GETS
//   compileGuardedRegex( pattern, syntax ) → { regex, refusal, isScreened }. `refusal` is the SAME text
//       `--regex` has always printed after "refused, nothing was scanned:" — the screen's message, or the
//       engine's own diagnostic. `isScreened` says which, for a caller whose malformed-pattern wording predates
//       the screen and is pinned (--arch). The screen runs FIRST, so its verdict is identical on every standard
//       library: a pattern one engine abandons and the other backtracks on forever gets one answer, not two.
//   GuardedRegex::search / forEachMatch → RegexVerdict { Miss, Hit, Exhausted }. Exhausted is a regex_error
//       thrown DURING the match (libc++'s error_complexity / error_stack): the screen is a static
//       approximation, and overlapping alternation — (a|a)+z — passes it. It is never Miss. METHODOLOGY §9: an
//       abandoned match is "unknown", and a caller that folds it into "no hit" reports a zero it did not
//       measure. Every entry point refuses on it by name, quoting kRegexAbandonedReason.
//
// THE ONE EXCEPTION BOUNDARY. std::regex reports through exceptions — regex_error from the parser and from the
// matcher, bad_alloc from either — and this codebase avoids exception handling (CONTRIBUTING §3: a recoverable
// error is a value, returned; RAII, not catch blocks, owns cleanup). So this header is the only place in src/
// that catches either, and it catches exactly those two, by type, and converts them to VALUES: a refusal
// string, or RegexVerdict::Exhausted. No catch(...) — a throw of any other type is not something a regex
// engine raises, and swallowing it would hide a bug rather than disclose a limit. Every public entry point is
// noexcept, so nothing above the seam ever sees an exception from the engine, and a call site holds no try.
// (Building a refusal string can itself allocate; under noexcept an allocation failure there terminates,
// which is the house rule that throws belong to the operator new seam alone.) Nothing here owns a resource
// a handler would have to release: the compiled regex is a value member, destroyed by its owner.
//
// COST. The screen is one linear pass over the pattern, once per compile, and a compile happens exactly where
// one happened before (once per query, per rule, per grep worker — never per file or per hit). The try around a
// match is table-based: nothing runs on the non-throwing path. The fault switch below is `constexpr false`
// under NDEBUG, so the branch and the getenv are deleted from a release build. Measured in the lane that made
// this seam: byte-identical output on every touched verb, release __text size in the CHANGELOG entry.
//
// THE ALLOWLIST, and why it is one row. src/redact.h compiles a CONSTANT rule table written in its own file, once,
// on the redaction hot path, so it keeps std::regex directly (arm (c) names the reason). src/skillscan.h was the
// second row until its patterns moved behind this header: a skill file is untrusted input, so an abandoned match
// there must fail closed rather than abort wrap's noexcept scan. A new constant table may join redact.h only on the
// same argument; a pattern a user can type may not.

#include "infra/emit.h"   // rw::faultSwitchOn — the one reader every non-NDEBUG fault switch goes through

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <new>        // std::bad_alloc — the one other exception type the engine raises, caught here by type
#include <optional>
#include <regex>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// L5 (Linux runtime probe) — the ONE place the two standard libraries disagree about what a valid pattern
// IS, closed here so the binary answers the same question on both.
//
// ECMAScript's IdentityEscape forbids `\<letter>` for any letter that is not a recognised escape, and libc++
// enforces it: `--regex='\Q\E'` is refused on macOS. libstdc++ does not — on Ubuntu the same pattern
// COMPILES, with `\Q` silently meaning the literal letter Q. That is the worse half of the split: the
// lenient side does not error, it answers a DIFFERENT question and hands the result back as a measurement.
//
// So the pattern is screened before either engine sees it, against the escapes libc++ actually accepts
// (measured with a probe, not inferred from the grammar): `\b \B \d \D \s \S \w \W \f \n \r \t \v` alone,
// plus `\c \x \u`, whose TAILS the engine still validates. Everything else after a backslash — digits
// (back-references), `$`, `_`, punctuation, any non-ASCII byte — is left entirely to the engine, which
// agrees about all of it. So this rejects EXACTLY the set libc++ already rejected and nothing more: no
// pattern that searches on macOS today stops searching, and Linux stops silently misreading the Perl-isms.
inline constexpr std::string_view kPortableRegexLetterEscapes = "bBdDsSwWfnrtv";   // valid on their own
inline constexpr std::string_view kPortableRegexPrefixEscapes = "cxu";             // valid with a tail the engine checks

inline std::optional<std::string> nonPortableRegexEscape( const std::string& pat )
{
    for( std::size_t i = 0; i + 1 < pat.size(); ++i )
    {
        if( pat[i] != '\\' )
        {
            continue;
        }

        const char escaped = pat[ i + 1 ];
        ++i;                                                                          // consume it: `\\Q` is an escaped backslash then a plain Q, not an escaped Q
        const bool isAsciiLetter =    ( escaped >= 'a' && escaped <= 'z' )
                                   || ( escaped >= 'A' && escaped <= 'Z' );
        if( !isAsciiLetter )
        {
            continue;
        }
        if( kPortableRegexLetterEscapes.find( escaped ) != std::string_view::npos )
        {
            continue;
        }
        if( kPortableRegexPrefixEscapes.find( escaped ) != std::string_view::npos )
        {
            continue;
        }

        return   std::string( "unsupported escape sequence '\\" ) + escaped + "' — the portable ECMAScript escapes are "
                 "\\b \\B \\d \\D \\s \\S \\w \\W \\f \\n \\r \\t \\v \\cX \\xHH \\uHHHH (some C++ standard libraries accept '\\"
               + escaped + "' and silently read it as the literal '" + escaped + "', so it is refused rather than answered differently per platform)";
    }
    return std::nullopt;
}

// M2 (Linux runtime probe) — the SECOND thing the two standard libraries disagree about, and the worse
// one. `--regex='(a+)+b'` over a long run of 'a' with no 'b' is the textbook catastrophic-backtracking
// shape: every way of splitting the run between the inner and the outer repetition is a distinct path,
// so a backtracking engine explores O(2^n) of them before it can report no-match.
//
// Apple libc++ has a complexity budget and gives up in well under a second with
// regex_error(error_complexity), which grepScanText's catch turned into a skipped file — the original
// A4-F10 "degrade, don't die" contract, and the only behaviour this repo had ever observed (a skipped file
// is a silent floor; GuardedRegex below now turns it into a refusal by name). libstdc++ has
// NO such budget: it never throws, so that catch is never reached and the process simply backtracks. The
// first real Linux run (Ubuntu 24.04, clang 18 + libstdc++) was still CPU-bound at 560 s on the very
// fixture the gate uses, i.e. on Linux a pathological --regex does not degrade — it hangs the tool.
//
// So the pattern is screened HERE, structurally, before either engine is handed it, for the same reason
// and in the same shape as the L5 escape screen above: the verdict must be a pure function of the pattern
// text, not of whose backtracker is linked in and not of what happens to be in the corpus. Refusal is the
// right outcome rather than a silent skip — a skipped file reads as a measurement, an exit-1 refusal that
// names the construct cannot.
//
// M2-b (Linux RE-smoke) — the first cut of this screen refused only an unbounded quantifier over a group
// that repeated WITHOUT bound inside it, and let (a?)+ and (a{1,3})+ through as "bounded inner, cannot
// blow up". That was libc++ behaviour written down as a law. On Ubuntu 24.04 / clang 18 / libstdc++ both
// of those patterns HANG — the re-smoke killed them on the harness's wall-clock cap, on the same fixture
// and in the same way as (a+)+b, and they had been shipping as this gate's "must still scan" controls.
// BOUNDED IS NOT UNAMBIGUOUS: '(a?)+' splits a run of 'a' in as many ways as '(a+)+' does, because the
// inner may also match EMPTY, and '(a{1,3})+' because the inner's width varies. So the screen is widened
// rather than the verdict split per platform.
//
// WHAT IS CAUGHT: an unbounded quantifier ('*', '+', '{n,}') applied to a group that contains ANY
// quantifier anywhere inside it, at any nesting depth — bounded ones included. (X+)+, (X*)*, (X+)*,
// (X{n,})+, ((X+))+, ((X)+)+, (X+|Y)+ as before, and now (X?)+, (X{m,n})+, ((X)?)+ and (X{n})+ too.
// Exact '{n}' is in ON PURPOSE: a fixed-count inner is only unambiguous when what it repeats is itself
// fixed-width, and '((ab|c){2})+d' is a real bomb that reading the quantifier alone cannot tell apart from
// '(a{3})+b'. A screen that must return ONE verdict on two different backtrackers cannot make that call.
//
// WHAT IS DELIBERATELY NOT CAUGHT, so the guard does not quietly eat working patterns: a group with no
// quantifier inside passes however it is quantified, so (abc)+, (a|b)+ and (a)+b pass; a BOUNDED outer
// quantifier passes whatever the group contains, which is what keeps the workaround this very message
// suggests — '(\s*\w+){1,20}' — legal; an UNQUANTIFIED group passes whatever it contains, so (a+)b, (a?)b
// and (a+)(b)+ pass; '+' inside a character class or behind a backslash is a literal, so [a+]+ and (\+)+
// pass; and the '?' that opens '(?:', '(?=' or '(?!' is a group MODIFIER, not a quantifier, so (?:abc)+
// passes while (?:a+)+b is still refused. The known GAP is overlapping alternation — (a|a)+b is a real
// bomb whose branches only overlap semantically — which is why GuardedRegex's match-time catch below is kept
// as belt-and-braces rather than removed. Every one of these cases is an arm of test/regexbombcheck.sh.
//
// Scope: EVERY user-authored pattern, through compileGuardedRegex below — --regex, --graph-query file(), the
// --arch path-rules and the #match?/#not-match? predicates of --match and --lint-rules. This paragraph used to
// scope the screen to --regex alone, on the reasoning that --arch rules "come from a committed rules file, not
// from the command line"; that exemption is how `file(all,"(a+)+z")` and `deny path zz/.* -> (a+)+z` reached
// the engine unscreened and aborted the process (rc 134 on libc++). A rules file is user-authored text exactly
// as an argument is.
struct RegexQuantifier { bool isPresent; bool isUnbounded; std::size_t lengthCount; };

// reads the quantifier at `at`, if there is one. '?' and '{n,m}' are quantifiers but BOUNDED; anything
// that is not a well-formed '{' interval is not a quantifier at all, just a literal brace.
inline RegexQuantifier regexQuantifierAt( const std::string& pat, std::size_t at )
{
    if( at >= pat.size() )
    {
        return { false, false, 0 };
    }
    if( pat[at] == '*' || pat[at] == '+' )
    {
        return { true, true, 1 };
    }
    if( pat[at] == '?' )
    {
        return { true, false, 1 };
    }
    if( pat[at] != '{' )
    {
        return { false, false, 0 };
    }

    std::size_t cursor         = at + 1;
    std::size_t lowerDigitCount = 0;
    while( cursor < pat.size() && pat[ cursor ] >= '0' && pat[ cursor ] <= '9' ) { ++cursor; ++lowerDigitCount; }
    if( lowerDigitCount == 0 )
    {
        return { false, false, 0 };
    }
    if( cursor < pat.size() && pat[cursor] == '}' )
    {
        return { true, false, ( cursor + 1 ) - at }; // {n} — exact, bounded
    }
    if( cursor >= pat.size() || pat[cursor] != ',' )
    {
        return { false, false, 0 };
    }

    ++cursor;
    std::size_t upperDigitCount = 0;
    while( cursor < pat.size() && pat[ cursor ] >= '0' && pat[ cursor ] <= '9' ) { ++cursor; ++upperDigitCount; }
    if( cursor >= pat.size() || pat[cursor] != '}' )
    {
        return { false, false, 0 };
    }

    return { true, upperDigitCount == 0, ( cursor + 1 ) - at };                                           // {n,} unbounded, {n,m} bounded
}

// '(?:' / '(?=' / '(?!' — a '?' immediately after '(' opens a NON-CAPTURING or lookaround group. It is a
// group MODIFIER, not a quantifier, and reading it as one (which M2-b's widened flag otherwise would)
// refuses every '(?:abc)+' ever written. Returns how many characters the scan must step over.
inline std::size_t regexGroupModifierLength( const std::string& pat, std::size_t openAt )
{
    return ( openAt + 1 < pat.size() && pat[ openAt + 1 ] == '?' ) ? 1 : 0;
}

// The one refusal this screen emits, kept out of the scan loop so the loop reads as the small state
// machine it is. `outerQuant` is the quantifier character that was applied to the offending group.
inline std::string catastrophicRegexMessage( char outerQuant )
{
    return   std::string( "catastrophic backtracking: the unbounded quantifier '" ) + outerQuant + "' is applied to a group whose contents "
             "already repeat (the (X+)+ / (X*)* / (X+)* / (X{n,})+ family, and equally the bounded-inner (X?)+ / (X{m,n})+ / (X{n})+ one). "
             "Every way of splitting the input between the inner and the outer repetition is a separate path, so matching a non-matching "
             "line costs time exponential in its length; a BOUNDED inner is no defence, because it is ambiguity and not unboundedness that "
             "multiplies the paths. std::regex has no backtracking budget you can set, and the standard libraries do not agree about it — "
             "libc++ abandons the match in under a second, libstdc++ never gives up at all (measured on Ubuntu 24.04 / clang 18 / libstdc++: "
             "'(a+)+b' still running after 560 s, and '(a?)+b' and '(a{1,3})+b' both still running when the harness killed them) — so this "
             "is refused rather than answered differently per platform. Workaround: collapse the two repetitions into one, since the outer "
             "adds no string the inner does not already match ('(a+)+' is the language of 'a+', '(a?)+' of 'a*', '(a{1,3})+' of 'a+'), or "
             "make the OUTER bounded with an explicit interval ('(\\s*\\w+){1,20}')";
}

inline std::optional<std::string> catastrophicRegexConstruct( const std::string& pat )
{
    // one flag per OPEN group: does anything inside it, at any depth, carry a quantifier — of ANY kind?
    // (M2-b: this used to track only UNBOUNDED inner repetition, which let the libstdc++-hanging (a?)+ and
    // (a{1,3})+ through. Unbounded is a subset of "any", so widening the flag is the whole behaviour change
    // — the refusal condition below still requires the OUTER quantifier to be unbounded.)
    std::vector<char> hasQuantifierInsideGroup;
    bool              isInsideClass = false;

    for( std::size_t i = 0; i < pat.size(); ++i )
    {
        const char c = pat[ i ];

        // the two contexts where a quantifier character is just a character
        if( c == '\\' )     { ++i; continue; }                                         // '\+' is a literal plus
        if( isInsideClass )
        {
            if( c == ']' )
            {
                isInsideClass = false;
            }
            continue;
        } // '[a+]' is a literal plus
        if( c == '[' )      { isInsideClass = true; continue; }

        // group open / close — the close is where the whole verdict is made
        if( c == '(' ) { hasQuantifierInsideGroup.push_back( 0 ); i += regexGroupModifierLength( pat, i ); continue; }
        if( c == ')' )
        {
            if( hasQuantifierInsideGroup.empty() )
            {
                continue; // unbalanced: the compile probe below owns that error
            }

            const bool isRepeatingInside = hasQuantifierInsideGroup.back() != 0;
            hasQuantifierInsideGroup.pop_back();
            const RegexQuantifier quant = regexQuantifierAt( pat, i + 1 );

            if( quant.isPresent && quant.isUnbounded && isRepeatingInside )
            {
                return catastrophicRegexMessage( pat[ i + 1 ] );
            }

            // the group is now an ATOM of its parent: a quantifier anywhere inside it — or ON it — is a
            // quantifier inside the parent too, which is what makes ((a+))+, ((a)+)+ and ((a)?)+ visible
            if( !hasQuantifierInsideGroup.empty() && ( isRepeatingInside || quant.isPresent ) )
            {
                hasQuantifierInsideGroup.back() = 1;
            }
            if( quant.isPresent )
            {
                i += quant.lengthCount; // step over the quantifier we just judged
            }
            continue;
        }

        // a plain quantifier: it marks the innermost enclosing group, if any (top-level repetition is fine)
        const RegexQuantifier quant = regexQuantifierAt( pat, i );
        if( quant.isPresent && !hasQuantifierInsideGroup.empty() )
        {
            hasQuantifierInsideGroup.back() = 1;
        }
        if( quant.isPresent )
        {
            i += quant.lengthCount - 1;
        }
    }
    return std::nullopt;
}

// ── STACK: both standard libraries' regex PARSERS recurse, so a long or deeply nested pattern overflows the stack ──
//
// Measured 2026-09-16 with a standalone probe (compile + destroy one pattern, binary search for the first signal death):
//
//     smallest crash            Apple libc++, std::thread (512 KiB)   libstdc++ 13, 8 MiB     libstdc++ 13, 512 KiB
//     nested groups  ((( a )))           3,392 deep                         15,616 deep             960 deep
//     literal atoms  aaaa…              16,896 bytes                        58,368 bytes          3,648 bytes
//     alternatives   a|a|…               8,448 alternatives           (NFA-state refusal first)        —
//
// A grep worker, an --arch/astquery compile thread and every other std::thread runs on the 512 KiB default on macOS,
// which is how `--regex=<20,000 bytes of a>` died with SIGBUS (rc 138) in a worker after the main thread's probe
// compile had passed it. So the screen bounds the pattern BEFORE any parser sees it: at most kRegexMaxPatternBytes
// bytes and kRegexMaxGroupDepth nested groups. Both sit under the smallest crash in every column above (the tightest,
// libstdc++ on a 512 KiB stack, by 1.78x on bytes and 15x on depth), are far above any pattern this tree's gates or
// rule tables write, and are one verdict on every platform. The MATCHER is a different story on libstdc++ — its DFS
// executor recurses per consumed character — and a pattern bound cannot reach it; that residual is disclosed in the
// lane report, not claimed fixed here.
inline constexpr std::size_t kRegexMaxPatternBytes = 2048;   // a longer pattern is REFUSED by name, never truncated — the compile-recursion stack bound
inline constexpr std::size_t kRegexMaxGroupDepth   = 64;     // deeper group nesting is REFUSED by name — the same stack bound, for nesting

inline std::optional<std::string> regexSizeRefusal( const std::string& pattern )
{
    if( pattern.size() > kRegexMaxPatternBytes )
    {
        return "the pattern is " + std::to_string( pattern.size() ) + " bytes and the limit is " + std::to_string( kRegexMaxPatternBytes )
             + ": std::regex compiles by recursion, and a longer pattern can overflow a worker thread's stack (a 16,896-byte literal "
               "killed a 512 KiB libc++ thread, a 3,648-byte one a libstdc++ thread of the same size) — split it into several shorter "
               "patterns or searches";
    }
    std::size_t depth = 0, deepest = 0;
    bool        isInsideClass = false;
    for( std::size_t i = 0; i < pattern.size(); ++i )
    {
        const char c = pattern[i];
        if( c == '\\' )
        {
            ++i;
            continue;
        }
        if( isInsideClass )
        {
            isInsideClass = ( c != ']' );
            continue;
        }
        isInsideClass = ( c == '[' );
        depth         = ( c == '(' ) ? depth + 1 : ( c == ')' && depth > 0 ) ? depth - 1 : depth;
        deepest       = std::max( deepest, depth );
    }
    if( deepest > kRegexMaxGroupDepth )
    {
        return "groups nest " + std::to_string( deepest ) + " deep and the limit is " + std::to_string( kRegexMaxGroupDepth )
             + ": std::regex compiles nested groups by recursion, and a deeper pattern can overflow a worker thread's stack (960 nested "
               "groups killed a 512 KiB libstdc++ thread) — flatten the nesting";
    }
    return std::nullopt;
}

// The structural screens, in order: the size bounds first (the stack reason above, and cheap), then the two
// `--regex` has always applied — the portability screen (L5), then the backtracking screen (M2). A pure function of
// the pattern TEXT, so every verdict is the same on every standard library.
inline std::optional<std::string> screenRegexPattern( const std::string& pattern ) noexcept
{
    if( std::optional<std::string> size = regexSizeRefusal( pattern ) )
    {
        return size;
    }
    if( std::optional<std::string> portability = nonPortableRegexEscape( pattern ) )
    {
        return portability;
    }
    return catastrophicRegexConstruct( pattern );
}

// ── the vocabulary a call site spells instead of the standard library's ─────────────────────────────────────
using RegexSyntax   = std::regex_constants::syntax_option_type;
using RegexCaptures = std::cmatch;   // captures over a std::string_view subject; the subject must outlive them

inline constexpr RegexSyntax kRegexEcmaScript = std::regex_constants::ECMAScript;   // std::regex's own default
inline constexpr RegexSyntax kRegexOptimize   = std::regex_constants::optimize;
inline constexpr RegexSyntax kRegexIcase      = std::regex_constants::icase;

enum class RegexVerdict : std::uint8_t
{
    Miss,
    Hit,
    Exhausted,   // the engine gave up DURING the match (regex_error or bad_alloc) — the answer is unknown, never a miss
};

// The one sentence every entry point quotes when a match is abandoned, so a reader (and a gate) meets the same
// words whichever verb it asked. Platform-independent on purpose: the engine's own what() differs per standard
// library, and this refusal must read the same on every one that can produce it.
inline constexpr std::string_view kRegexAbandonedReason =
    "the regex engine abandoned the match (std::regex gave up part-way through it: the backtracking the structural "
    "screen cannot see, such as overlapping alternation like (a|a)+z where two branches match the same text, or "
    "its stack or memory limit)";

struct RegexCompile;

// A compiled user pattern. Default-constructed it is an EMPTY slot (a member waiting to be filled); only
// compileGuardedRegex fills one, which is what keeps the screen in front of every engine that can be reached.
class GuardedRegex
{
public:
    GuardedRegex() = default;

    RegexVerdict search( std::string_view subject ) const noexcept
    {
        try
        {
            throwIfMatchFaultInjected();
            return std::regex_search( subject.data(), subject.data() + subject.size(), engine ) ? RegexVerdict::Hit : RegexVerdict::Miss;
        }
        catch( const std::regex_error& ) { return RegexVerdict::Exhausted; }   // error_complexity / error_stack
        catch( const std::bad_alloc& )   { return RegexVerdict::Exhausted; }   // the matcher's state stack outgrew memory
    }

    // `captures` index into `subject`'s bytes, so the subject must outlive every read of them.
    RegexVerdict search( std::string_view subject, RegexCaptures& captures ) const noexcept
    {
        try
        {
            throwIfMatchFaultInjected();
            return std::regex_search( subject.data(), subject.data() + subject.size(), captures, engine ) ? RegexVerdict::Hit : RegexVerdict::Miss;
        }
        catch( const std::regex_error& ) { return RegexVerdict::Exhausted; }
        catch( const std::bad_alloc& )   { return RegexVerdict::Exhausted; }
    }

    // Every non-overlapping match in [first, last), in order: onMatch( offsetFromFirst ) returns false to stop.
    // Exhausted means the matches reported before the engine gave up are the ones that exist so far and no more
    // is known. onMatch runs inside the boundary, so an allocation failure in it (a caller appending the site)
    // is an unfinished scan too, and reads the same way; it must throw nothing else.
    template<typename OnMatch>
    RegexVerdict forEachMatch( const char* first, const char* last, OnMatch&& onMatch ) const noexcept
    {
        try
        {
            throwIfMatchFaultInjected();
            RegexVerdict verdict = RegexVerdict::Miss;
            for( auto it = std::cregex_iterator( first, last, engine ); it != std::cregex_iterator(); ++it )
            {
                verdict = RegexVerdict::Hit;
                if( !onMatch( std::size_t( it->position() ) ) )
                {
                    break;
                }
            }
            return verdict;
        }
        catch( const std::regex_error& ) { return RegexVerdict::Exhausted; }
        catch( const std::bad_alloc& )   { return RegexVerdict::Exhausted; }
    }

private:
    friend RegexCompile compileGuardedRegex( const std::string& pattern, RegexSyntax syntax ) noexcept;

    // FAULT INJECTION, because the only real trigger is one standard library's budget and the other has none:
    // RIPWIRE_FAULT_REGEX_MATCH=1 makes every guarded match throw regex_error(error_complexity) inside its own try,
    // so every entry point's Exhausted path is reachable on every platform. Non-NDEBUG only (rw::faultSwitchOn is
    // `constexpr false` under NDEBUG, and the static is then a constant — no guard, no getenv, no branch in
    // release), read ONCE per process (determinism), exact "1" (the rule faultSwitchOn owns). Called ONLY inside
    // the try of a noexcept member above, so the throw it raises never leaves the seam.
    static void throwIfMatchFaultInjected()
    {
        static const bool isOn = rw::faultSwitchOn( "RIPWIRE_FAULT_REGEX_MATCH" );
        if( isOn )
        {
            throw std::regex_error( std::regex_constants::error_complexity );
        }
    }

    std::regex engine;
};

struct RegexCompile
{
    GuardedRegex               regex;                // an empty slot whenever `refusal` is set — never matched
    std::optional<std::string> refusal;              // the named reason, in the words --regex has always printed
    bool                       isScreened = false;   // true ⇒ a structural screen refused it; false ⇒ the engine's parser did
};

// Screen, then compile. The screen's verdict is platform-independent, so it decides first; only a pattern it
// passes is handed to the engine's parser, whose diagnostic is returned verbatim — or, when the parser ran out
// of memory (a huge bracket expression or repeat count), a fixed sentence saying so. The value carries the
// verdict; nothing is thrown past this function.
inline RegexCompile compileGuardedRegex( const std::string& pattern, RegexSyntax syntax ) noexcept
{
    RegexCompile out;
    out.refusal = screenRegexPattern( pattern );
    if( out.refusal )
    {
        out.isScreened = true;
        return out;
    }
    try                                { out.regex.engine.assign( pattern, syntax ); }
    catch( const std::regex_error& e ) { out.refusal = std::string( e.what() ); }
    catch( const std::bad_alloc& )     { out.refusal = std::string( "invalid regular expression: the engine ran out of memory compiling it" ); }
    return out;
}

// The boundary, held by the compiler rather than by this comment: every entry point a call site can reach is
// noexcept, so a future edit that lets an engine exception escape the seam fails to build instead of shipping.
static_assert( noexcept( compileGuardedRegex( std::declval<const std::string&>(), kRegexEcmaScript ) ) );
static_assert( noexcept( std::declval<const GuardedRegex&>().search( std::string_view() ) ) );
static_assert( noexcept( std::declval<const GuardedRegex&>().search( std::string_view(), std::declval<RegexCaptures&>() ) ) );
static_assert( noexcept( std::declval<const GuardedRegex&>().forEachMatch( nullptr, nullptr, []( std::size_t ) { return true; } ) ) );

}   // namespace rw
