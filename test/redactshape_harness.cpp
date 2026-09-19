// redactshape_harness.cpp — the oracle behind test/regexguardcheck.sh arm (o).
//
// src/redact.h answers its nine prefixed rules structurally (redactdetail::shapeMatchLength) instead of with std::regex,
// because libstdc++'s matcher recurses once per state and a long token run overflowed Linux's stack on a default run.
// The claim is that the structural answer IS the regex's answer, so this harness asks the regex: for every rule, at
// every position whose byte can start that rule, regex_search( match_continuous ) on the rule's own table pattern must
// give the same match length (0 for no match) over generated text built from the rules' own prefixes, separators and
// class runs at and around every threshold (4, 10, 16, 20, 35), plus PEM banners with 0-4 words and decoy words.
// Runs stay short (<= 60 bytes) so the regex itself cannot recurse deep. Exit 0 only with 0 mismatches and every rule
// matched at least 100 times (so a generator that stopped producing a shape fails instead of passing vacuously).
//
// Usage: redactshape_harness [text-count]

#include "redact.h"

#include <array>
#include <cstdint>
#include <cstdio>
#include <random>
#include <regex>
#include <string>

int main( int argc, char** argv )
{
    const std::size_t textCount = argc > 1 ? std::size_t( std::stoul( argv[ 1 ] ) ) : 30000;
    constexpr std::size_t kShapeRules = 9;
    std::array<std::regex, kShapeRules> oracle;
    for( std::size_t r = 0; r < kShapeRules; ++r )
    {
        oracle[ r ] = std::regex( rw::kRedactRules[ r ].pattern, std::regex::ECMAScript | std::regex::optimize );
    }
    const char* const pieces[] = {
        "AKIA", "-----BEGIN ", "PRIVATE KEY-----", "PRIVATE ", "KEY-----", "RSA ", "OPENSSH ", "EC ", "A ", "KEY ", "BEGIN",
        "gh", "ghp_", "gho_", "ghx_", "ghs", "_", "github_pat_", "github_pat", "xox", "xoxb-", "xoxq-", "xoxp", "AIza",
        "sk-", "sk-ant-", "sk-ant", "ant-", "eyJ", "eyJhbG", ".", "..", "-", " ", "\n", "=", "+", "/", "a", "Z", "9",
    };
    const char* const classes[] = {
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ",                                   // UpperDigit
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_",        // Word
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-",        // SlackBody
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-",       // KeyBody
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ",                                             // PEM words
    };
    const std::size_t runLengths[] = { 0, 1, 3, 4, 5, 9, 10, 11, 15, 16, 17, 19, 20, 21, 34, 35, 36, 40, 60 };
    std::mt19937_64   rng( 0x5eedfee1u );
    const auto        pick = [ & ]( std::size_t n ) { return std::size_t( rng() % n ); };
    const char        firstByte[ kShapeRules ] = { 'A', '-', 'g', 'g', 'x', 'A', 's', 's', 'e' };

    std::uint64_t checks = 0, mismatches = 0;
    std::array<std::uint64_t, kShapeRules> hits{};
    for( std::size_t t = 0; t < textCount; ++t )
    {
        std::string text;
        for( std::size_t n = 2 + pick( 14 ); n > 0; --n )
        {
            const std::size_t roll = pick( 6 );
            if( roll == 0 )
            {
                // a planted shape: a rule's own prefix followed by a run of its class near its threshold, or a PEM banner
                const std::size_t r      = pick( kShapeRules );
                const char* const stems[ kShapeRules ] = { "AKIA", "-----BEGIN ", "gh?_", "github_pat_", "xox?-", "AIza", "sk-ant-", "sk-", "eyJ" };
                const std::size_t clsOf[ kShapeRules ] = { 0, 4, 1, 1, 2, 3, 3, 3, 3 };
                std::string stem = stems[ r ];
                for( char& c : stem ) { c = c == '?' ? "posurxba"[ pick( 8 ) ] : c; }
                text += stem;
                const std::string cls = classes[ clsOf[ r ] ];
                const auto run = [ & ]( std::size_t length ) { for( ; length > 0; --length ) { text.push_back( cls[ pick( cls.size() ) ] ); } };
                if( r == 1 )
                {
                    for( std::size_t w = pick( 5 ); w > 0; --w ) { run( 1 + pick( 7 ) ); text += pick( 5 ) == 0 ? "-" : " "; }
                    text += pick( 4 ) == 0 ? "PRIVATE KEY----" : "PRIVATE KEY-----";
                }
                else if( r == 8 )
                {
                    for( int seg = 0; seg < 3; ++seg ) { if( seg > 0 ) { text += pick( 6 ) == 0 ? "-" : "."; } run( 2 + pick( 6 ) ); }
                }
                else
                {
                    run( runLengths[ 5 + pick( std::size( runLengths ) - 5 ) ] );
                }
            }
            else if( roll < 3 )
            {
                text += pieces[ pick( std::size( pieces ) ) ];
            }
            else
            {
                const std::string cls = classes[ pick( std::size( classes ) ) ];
                for( std::size_t k = runLengths[ pick( std::size( runLengths ) ) ]; k > 0; --k )
                {
                    text.push_back( cls[ pick( cls.size() ) ] );
                }
            }
        }
        for( std::size_t pos = 0; pos < text.size(); ++pos )
        {
            for( std::size_t r = 0; r < kShapeRules; ++r )
            {
                if( text[ pos ] != firstByte[ r ] )
                {
                    continue;
                }
                std::cmatch m;
                const char* const begin  = text.c_str();
                const std::size_t expect = std::regex_search( begin + pos, begin + text.size(), m, oracle[ r ],
                                                              std::regex_constants::match_continuous ) ? std::size_t( m.length( 0 ) ) : 0;
                const std::size_t got    = rw::redactdetail::shapeMatchLength( r, text, pos );
                ++checks;
                hits[ r ] += expect != 0 ? 1 : 0;
                if( got != expect && ++mismatches <= 10 )
                {
                    std::printf( "MISMATCH rule %zu (%s) at %zu: regex %zu, shape %zu, text=[", r, rw::kRedactRules[ r ].pattern, pos, expect, got );
                    for( const char c : text ) { std::printf( c == '\n' ? "\\n" : "%c", c ); }
                    std::printf( "]\n" );
                }
            }
        }
    }
    std::uint64_t leastHits = hits[ 0 ];
    for( const std::uint64_t h : hits ) { leastHits = h < leastHits ? h : leastHits; }
    const bool coverage = leastHits >= 100;
    std::printf( "redactshape: per-rule matches" );
    for( const std::uint64_t h : hits ) { std::printf( " %llu", (unsigned long long)h ); }
    std::printf( "\n" );
    std::printf( "redactshape: texts=%zu checks=%llu least_rule_matches=%llu mismatches=%llu coverage=%s\n", textCount,
                 (unsigned long long)checks, (unsigned long long)leastHits, (unsigned long long)mismatches, coverage ? "met" : "NOT MET" );
    return ( mismatches == 0 && coverage ) ? 0 : 1;
}
