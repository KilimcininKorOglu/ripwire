// readers_domain.cpp — crash-fuzz entry points for the readers that live in the domain headers main.cpp includes:
// the SCIP protobuf decoder, tsconfig.json/go.mod alias parsers, --lint-rules files, the quality-cache blobs
// (qsnap, qchurn), the git-history oracle cache, and the committed sidecars (.ripwire_notes, the quality acks
// ledger, the quality baseline, .ripwire_config, --arch rules).
//
// CHECKSUMMED BLOBS. qsnap, qchurn and the history cache end in an fnv1a64 over every byte before it, and qsnap and
// qchurn open with a key digest. Random bytes would stop at those guards forever, so each harness takes the fuzz
// input as the BODY, puts the real header in front of it (built by the real serializer from an empty object, so a
// format change moves the harness with it) and appends the real checksum. What the reader sees is exactly what a
// crafted blob with rebuilt digests would carry — the case the digests do not protect against.
//
// Oracle: no sanitizer report, no hardening trap, no ASSUME, no uncaught exception.

#include "fuzzsupport.h"

#include "scip.h"
#include "resolve.h"
#include "lintrules.h"
#include "quality.h"
#include "gitoracle.h"
#include "notes.h"
#include "arch.h"

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>
#include <string_view>
#include <vector>

namespace rwfuzz
{

namespace
{

void appendPod( std::string& out, const auto& v )
{
    out.append( reinterpret_cast<const char*>( &v ), sizeof( v ) );
}

}   // namespace

// --scip=FILE: the protobuf wire decoder, then the descriptor walk every occurrence's symbol goes through.
int scip( const std::uint8_t* data, std::size_t size )
{
    std::vector<rw::ScipDocument> docs;
    noteAccepted( rw::scipDecodeIndex( data, size, docs ) && !docs.empty() );
    for( const rw::ScipDocument& doc : docs )
    {
        for( const rw::ScipOccurrence& occ : doc.occurrences )
        {
            (void)rw::scipDescriptorTail( occ.symbol );
            (void)rw::scipDescriptorName( occ.symbol );
        }
    }
    return 0;
}

// Workspace config evidence read from the tree: tsconfig.json `paths` and go.mod `replace` (first byte picks).
int resolvecfg( const std::uint8_t* data, std::size_t size )
{
    std::string_view in( reinterpret_cast<const char*>( data ), size );
    const std::uint8_t          pick = takeByte( in );
    const std::string           bytes( in );
    std::vector<rw::ConfigAlias> out;
    if( ( pick & 1 ) == 0 )
    {
        rw::parseTsconfigPaths( bytes, 0, "/fuzz/root", out );
    }
    else
    {
        rw::parseGoModReplaces( bytes, 0, "/fuzz/root", out );
    }
    noteAccepted( !out.empty() );
    return 0;
}

// A --lint-rules directory's rule file (YAML-shaped text: rules, query blocks, message templates).
int lintrules( const std::uint8_t* data, std::size_t size )
{
    std::vector<rw::LintRule> rules;
    noteAccepted( rw::parseLintRuleFile( "fuzz.yml", std::string_view( reinterpret_cast<const char*>( data ), size ), rules ) && !rules.empty() );
    return 0;
}

// ripwire-qsnap-*: the computed HEAD snapshot --quality-delta reuses.
int qsnap( const std::uint8_t* data, std::size_t size )
{
    static const std::string headSha = "0123456789abcdef0123456789abcdef01234567";
    static const std::string header  = []()
    {
        const std::string empty = rw::quality::serializeSnapshot( rw::quality::Snapshot{}, headSha );
        // an empty snapshot is the header, ten zero u32 counts and the u64 checksum
        return empty.substr( 0, empty.size() - 10 * sizeof( std::uint32_t ) - sizeof( std::uint64_t ) );
    }();
    std::string blob = header + bytesOf( data, size );
    appendPod( blob, rw::fnv1a64( blob ) );
    rw::quality::Snapshot out;
    noteAccepted( rw::quality::deserializeSnapshot( blob, headSha, out ) );
    return 0;
}

// ripwire-qchurn-*: the raw commit stream the churn kinds are computed from.
int qchurn( const std::uint8_t* data, std::size_t size )
{
    static const std::string keyMat = "fuzz-key-material";
    static const std::string header = []()
    {
        const std::string empty = rw::quality::serializeRawCommitStream( rw::RawCommitStream{}, keyMat );
        return empty.substr( 0, empty.size() - sizeof( std::uint32_t ) - sizeof( std::uint64_t ) );   // minus count, checksum
    }();
    std::string blob = header + bytesOf( data, size );
    appendPod( blob, rw::fnv1a64( blob ) );
    rw::RawCommitStream out;
    noteAccepted( rw::quality::deserializeRawCommitStream( blob, keyMat, out ) );
    return 0;
}

// ripwire-qhist-*: the git-history oracle cache (--whereis / the removed-name probe).
int oracle( const std::uint8_t* data, std::size_t size )
{
    std::string blob;
    appendPod( blob, rw::gitoracle::kOracleCacheMagic );
    appendPod( blob, rw::gitoracle::kOracleCacheScheme );
    blob += bytesOf( data, size );
    appendPod( blob, rw::fnv1a64( blob ) );
    rw::gitoracle::HistoryIndex idx;
    noteAccepted( rw::gitoracle::loadOracleCache( writeScratch( "qhist.bin", blob ), idx ) );
    return 0;
}

// Committed sidecars, each read through its real path-taking reader (first byte picks the reader).
int sidecars( const std::uint8_t* data, std::size_t size )
{
    std::string_view in( reinterpret_cast<const char*>( data ), size );
    const std::uint8_t pick = takeByte( in );
    switch( pick % 5 )
    {
        case 0:
        {
            std::vector<rw::notes::Note> notes = rw::notes::readNotes( writeScratch( ".ripwire_notes", in ) );
            noteAccepted( !notes.empty() );
            (void)rw::notes::buildNoteIndex( std::move( notes ) );
            break;
        }
        case 1:
        {
            std::size_t badLines = 0;
            noteAccepted( !rw::quality::readAckRecords( writeScratch( ".ripwire_quality_acks", in ), badLines ).empty() );
            break;
        }
        case 2:
        {
            rw::quality::Snapshot           snap;
            rw::quality::BaselineReadStats  stats;
            const std::string               path = writeScratch( ".ripwire_quality_baseline", in );
            noteAccepted( rw::quality::readBaseline( path, snap, stats ) );
            (void)rw::quality::readBaselineHeadSha( path );
            (void)rw::quality::readBaselineAbsorbed( path );
            break;
        }
        case 3:
        {
            (void)writeScratch( ".ripwire_config", in );
            noteAccepted( !rw::quality::readRegisterMacrosConfig( ScratchDir::get().path() ).names.empty() );
            break;
        }
        default:
        {
            noteAccepted( rw::parseArchRules( writeScratch( "arch.rules", in ) ).loaded );
            break;
        }
    }
    return 0;
}

// --quality-delta --scope=SPEC: a user-typed scope expression.
int qscope( const std::uint8_t* data, std::size_t size )
{
    noteAccepted( rw::quality::parseScope( std::string_view( reinterpret_cast<const char*>( data ), size ) ).active() );
    return 0;
}

}   // namespace rwfuzz
