// regexlines_harness.cpp — the differential oracle behind test/regexguardcheck.sh arm (j).
//
// src/regexguard.h answers some matches WITHOUT std::regex: a literal plan (a literal, or literals joined by `|`, one of
// them optionally `^`/`$`-anchored) is found with byte kernels, and a line holding none of a pattern's required literals
// is never handed to the engine. Each is a claim that the answer is the engine's own, so this harness asks the engine.
// For every pattern (a hand-written adversarial set, the corpus file the gate extracts from docs/skills/tests/lint
// packs, and generated ones) under both syntax sets the tree uses (ECMAScript|optimize, and |icase), over generated
// texts (CRLF and bare LF, empty lines, with and without a final newline, and the pattern's own literal text spliced in
// at line starts, ends and overlaps):
//
//   LINES   forEachLineMatch with the literal paths ON and OFF both equal a reference built here from nothing but
//           std::cregex_iterator over each line — the same (line, offset) list, in the same order.
//   SEARCH  GuardedRegex::search( s ) equals std::regex_search( s ) on every line and on the whole text.
//   SKIP    with a 6-byte engine bound: the paths-OFF scan skips exactly the lines longer than 6 bytes and matches the
//           rest as the reference does; the paths-ON scan reports only reference matches, every one on a line of 6
//           bytes or fewer, and skips no more lines than the paths-OFF scan.
//
// A pattern either std::regex or the screen refuses is not a case; a case whose reference the engine abandoned
// (libc++'s complexity budget) is counted and not compared. Exit 0 only with 0 mismatches AND the coverage floors met
// (so a corpus that stopped exercising a literal plan or a required literal fails instead of passing vacuously).
//
// Usage: regexlines_harness [corpus-file] [generated-pattern-count]

#include "regexguard.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <random>
#include <regex>
#include <string>
#include <vector>

namespace
{

struct Site
{
    std::uint32_t line;
    std::size_t   offset;
    bool operator==( const Site& ) const = default;
};

struct Scan
{
    std::vector<Site> sites;
    std::uint32_t     skipped     = 0;
    bool              isExhausted = false;
};

// The reference: split exactly as grep reads lines, and ask the engine about each one. No literal path exists here.
Scan referenceScan( const std::regex& re, const std::string& text, std::size_t maxLineBytes )
{
    Scan        out;
    std::size_t begin = 0;
    std::uint32_t line = 1;
    while( !text.empty() )
    {
        const std::size_t nl  = text.find( '\n', begin );
        std::size_t       end = nl == std::string::npos ? text.size() : nl;
        if( end > begin && text[ end - 1 ] == '\r' )
        {
            --end;
        }
        if( end - begin > maxLineBytes )
        {
            ++out.skipped;
        }
        else
        {
            try
            {
                for( auto it = std::cregex_iterator( text.data() + begin, text.data() + end, re ); it != std::cregex_iterator(); ++it )
                {
                    out.sites.push_back( { line, begin + std::size_t( it->position() ) } );
                }
            }
            catch( const std::exception& )
            {
                out.isExhausted = true;
                return out;
            }
        }
        if( nl == std::string::npos || nl + 1 >= text.size() )
        {
            break;
        }
        begin = nl + 1;
        ++line;
    }
    return out;
}

Scan guardedScan( const rw::GuardedRegex& re, const std::string& text, rw::RegexLinePolicy policy )
{
    Scan                    out;
    const rw::RegexLineScan scan = re.forEachLineMatch( text, policy, [ & ]( std::uint32_t line, std::size_t offset )
    {
        out.sites.push_back( { line, offset } );
        return true;
    } );
    out.skipped     = scan.skippedLineCount;
    out.isExhausted = scan.verdict == rw::RegexVerdict::Exhausted;
    return out;
}

std::vector<std::string> linesOf( const std::string& text )
{
    std::vector<std::string> lines;
    std::size_t              begin = 0;
    while( !text.empty() )
    {
        const std::size_t nl  = text.find( '\n', begin );
        std::size_t       end = nl == std::string::npos ? text.size() : nl;
        if( end > begin && text[ end - 1 ] == '\r' )
        {
            --end;
        }
        lines.push_back( text.substr( begin, end - begin ) );
        if( nl == std::string::npos || nl + 1 >= text.size() )
        {
            break;
        }
        begin = nl + 1;
    }
    return lines;
}

// The bytes a pattern would match literally: its plain characters, with identity escapes resolved.
std::string literalBitsOf( const std::string& pat )
{
    std::string bits;
    for( std::size_t i = 0; i < pat.size(); ++i )
    {
        const char c = pat[ i ];
        if( c == '\\' && i + 1 < pat.size() )
        {
            const char e = pat[ ++i ];
            bits.push_back( e == 'n' ? '\n' : e == 'r' ? '\r' : e == 't' ? '\t' : e );
        }
        else if( std::string_view( "^$.*+?()[]{}|" ).find( c ) == std::string_view::npos )
        {
            bits.push_back( c );
        }
    }
    return bits;
}

const char* const kAdversarial[] = {
    "a", "ab", "aa", "aaa", "abc", "a.b", "a\\.b", "\\.", "\\|", "\\\\", "a\\|b", "a|b", "ab|a", "a|ab", "ab|abc|a", "b|ab",
    "abc|bcd", "aa|a", "x|xx|xxx", "|a", "a|", "a||b", "^a", "a$", "^a$", "^ab$", "^$", "^", "$", "^a|b", "a|b$", "a$|b",
    "^\\.$", "\\n", "a\\nb", "\\r", "a\\r", "\\t", "a\\tb", "ab*", "a*b", "ab+c", "ab?c", "a{2}", "a{1,2}b", "(ab)c", "(?:ab)c",
    "c(ab)", "[ab]c", "a[b]", "[]a", "[^]a", "a\\bb", "\\ba", "a\\B", "(?=a)a", "(?!b)ab", "(a)\\1", "foo.*bar", "A", "aB",
    "Ab|b", "^A", "B$", "a.*", ".*a", "a+", "(a|b)c", "c(a|b)", "a(b|c)d", "\\x41", "\\u0041b", "\\d", "a\\d", "[[:alpha:]]b",
    "a]", "a}", "a{", "a{,2}", "\\cJ", "\\0", "a b", " ", "  a", "a\\ b", "\\-", "a-b", "\\/", "=", "a=b|b=a", "\\?", "\\*a",
    "\\(a\\)", "\\[a\\]", "\\{a\\}", "\\^a", "a\\$", "\\$a", "$a", "a^",
};

const char* const kGeneratedTokens[] = {
    "a", "b", "ab", "A", "x", " ", "\\.", "\\|", "\\\\", ".", "[ab]", "[^a]", "\\d", "\\w", "^", "$", "|", "(", ")", "(?:",
    "*", "+", "?", "{2}", "{1,2}", "*?", "\\b", "(?=a)", "(?!b)", "\\1", "\\n", "\\r", "\\t", "-", "=",
};

}   // namespace

int main( int argc, char** argv )
{
    std::vector<std::string> patterns( std::begin( kAdversarial ), std::end( kAdversarial ) );
    std::size_t corpusCount = 0;
    if( argc > 1 )
    {
        std::ifstream corpus( argv[ 1 ] );
        for( std::string line; std::getline( corpus, line ); )
        {
            if( !line.empty() )
            {
                patterns.push_back( line );
                ++corpusCount;
            }
        }
    }
    const std::size_t generatedCount = argc > 2 ? std::size_t( std::stoul( argv[ 2 ] ) ) : 1500;
    std::mt19937_64   rng( 0x5eed2026u );
    const auto        pick = [ & ]( std::size_t n ) { return std::size_t( rng() % n ); };
    for( std::size_t g = 0; g < generatedCount; ++g )
    {
        std::string pat;
        for( std::size_t t = 1 + pick( 6 ); t > 0; --t )
        {
            pat += kGeneratedTokens[ pick( std::size( kGeneratedTokens ) ) ];
        }
        patterns.push_back( pat );
    }

    const std::string alphabet = "aabbAB.x|\\ -=\t\r";
    std::uint64_t cases = 0, mismatches = 0, exhausted = 0, compiled = 0, withPlan = 0, withRequired = 0, skipCases = 0;
    const rw::RegexSyntax syntaxes[] = { rw::kRegexEcmaScript | rw::kRegexOptimize, rw::kRegexEcmaScript | rw::kRegexOptimize | rw::kRegexIcase };
    for( const std::string& pat : patterns )
    {
        const std::string bits = literalBitsOf( pat );
        for( const rw::RegexSyntax syntax : syntaxes )
        {
            std::regex raw;
            try
            {
                raw.assign( pat, syntax );
            }
            catch( const std::exception& )
            {
                continue;
            }
            const rw::RegexCompile guarded = rw::compileGuardedRegex( pat, syntax );
            if( guarded.refusal )
            {
                continue;
            }
            ++compiled;
            withPlan     += rw::regexLiteralPlanOf( pat, syntax ).alternatives.empty() ? 0 : 1;
            withRequired += rw::regexRequiredLiteralsOf( pat, syntax ).anyOf.empty() ? 0 : 1;
            for( int s = 0; s < 48; ++s )
            {
                std::string text;
                for( std::size_t lineCount = pick( 5 ); lineCount > 0; --lineCount )
                {
                    std::string line;
                    for( std::size_t n = pick( 14 ); n > 0; --n )
                    {
                        const std::size_t roll = pick( 10 );
                        if( roll < 3 && !bits.empty() )
                        {
                            const std::size_t from = pick( bits.size() );
                            line += bits.substr( from, 1 + pick( bits.size() - from ) );   // a slice of the pattern's own text
                        }
                        else if( roll == 3 && !bits.empty() )
                        {
                            std::string folded = bits;                                   // the same text, case flipped
                            for( char& c : folded )
                            {
                                c = ( c >= 'a' && c <= 'z' ) ? char( c - 0x20 ) : ( c >= 'A' && c <= 'Z' ) ? char( c + 0x20 ) : c;
                            }
                            line += folded;
                        }
                        else
                        {
                            line.push_back( alphabet[ pick( alphabet.size() ) ] );
                        }
                    }
                    text += line;
                    text += pick( 4 ) == 0 ? "\r\n" : "\n";
                }
                if( !text.empty() && pick( 2 ) == 0 )
                {
                    text.pop_back();                                                     // no final newline (maybe a bare \r)
                }
                ++cases;
                const Scan ref = referenceScan( raw, text, SIZE_MAX );
                if( ref.isExhausted )
                {
                    ++exhausted;
                    continue;
                }
                const Scan on  = guardedScan( guarded.regex, text, { SIZE_MAX, true } );
                const Scan off = guardedScan( guarded.regex, text, { SIZE_MAX, false } );
                const auto report = [ & ]( const char* what )
                {
                    if( ++mismatches <= 12 )
                    {
                        std::printf( "MISMATCH %s: pattern=[%s] icase=%d text=[", what, pat.c_str(), ( syntax & rw::kRegexIcase ) ? 1 : 0 );
                        for( const char c : text ) { std::printf( c == '\n' ? "\\n" : c == '\r' ? "\\r" : "%c", c ); }
                        std::printf( "]\n" );
                    }
                };
                if( on.isExhausted || off.isExhausted )
                {
                    ++exhausted;
                    continue;
                }
                if( on.sites != ref.sites ) { report( "LINES paths-on" ); }
                if( off.sites != ref.sites ) { report( "LINES paths-off" ); }
                if( on.skipped != 0 || off.skipped != 0 ) { report( "LINES skipped with no bound" ); }

                std::vector<std::string> subjects = linesOf( text );
                subjects.push_back( text );
                for( const std::string& subject : subjects )
                {
                    const rw::RegexVerdict verdict = guarded.regex.search( subject );
                    bool                   expect  = false;
                    try
                    {
                        expect = std::regex_search( subject, raw );
                    }
                    catch( const std::exception& )
                    {
                        continue;
                    }
                    if( verdict == rw::RegexVerdict::Exhausted || ( verdict == rw::RegexVerdict::Hit ) != expect )
                    {
                        report( "SEARCH" );
                        break;
                    }
                }

                ++skipCases;
                constexpr std::size_t kBound = 6;
                const Scan refBound = referenceScan( raw, text, kBound );
                const Scan offBound = guardedScan( guarded.regex, text, { kBound, false } );
                const Scan onBound  = guardedScan( guarded.regex, text, { kBound, true } );
                if( offBound.sites != refBound.sites || offBound.skipped != refBound.skipped ) { report( "SKIP paths-off" ); }
                const std::vector<std::string> lines = linesOf( text );
                bool isSubset = onBound.skipped <= offBound.skipped;
                for( const Site& site : onBound.sites )
                {
                    isSubset = isSubset && std::find( ref.sites.begin(), ref.sites.end(), site ) != ref.sites.end();
                }
                for( const Site& site : ref.sites )
                {
                    const bool isShortLine = lines[ site.line - 1 ].size() <= kBound;
                    isSubset = isSubset && ( !isShortLine || std::find( onBound.sites.begin(), onBound.sites.end(), site ) != onBound.sites.end() );
                }
                if( !isSubset ) { report( "SKIP paths-on" ); }
            }
        }
    }
    const bool coverage = compiled >= 1000 && withPlan >= 150 && withRequired >= 300 && corpusCount + 1 > ( argc > 1 ? 1u : 0u );
    std::printf( "regexlines: patterns=%zu (corpus %zu) compiled=%llu literal_plan=%llu required_literals=%llu cases=%llu skip_cases=%llu "
                 "engine_abandoned=%llu mismatches=%llu coverage=%s\n",
                 patterns.size(), corpusCount, (unsigned long long)compiled, (unsigned long long)withPlan, (unsigned long long)withRequired,
                 (unsigned long long)cases, (unsigned long long)skipCases, (unsigned long long)exhausted, (unsigned long long)mismatches,
                 coverage ? "met" : "NOT MET" );
    return ( mismatches == 0 && coverage ) ? 0 : 1;
}
