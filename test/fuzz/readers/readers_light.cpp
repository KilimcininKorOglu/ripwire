// readers_light.cpp — crash-fuzz entry points for the readers that live in small self-contained headers:
// the MCP JSON-RPC field scanner, the document extractors, the --from-trace frame parsers and the skill scanner.
// Oracle: no sanitizer report, no hardening trap, no ASSUME, no uncaught exception. Correctness oracles belong to
// the correctness fuzzers (help-wanted issue #149), not here.

#include "fuzzsupport.h"

#include "mcpjson.h"
#include "docparse.h"
#include "tracein.h"
#include "skillscan.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rwfuzz
{

// One JSON-RPC frame as mcp.h's dispatch reads it: the framing gate, the id, the method, params and its arguments
// object, then every array-shaped argument a verb reads, and a decode at every quote of the frame.
int mcpjson( const std::uint8_t* data, std::size_t size )
{
    using namespace rw::mcpdetail;
    const std::string line = bytesOf( data, size );
    noteAccepted( !findString( line, "method" ).empty() );
    (void)checkFrame( line );
    (void)findRawId( line );
    (void)findRawValue( line, "id" );
    (void)findString( line, "method" );
    (void)objectKeys( line );
    const std::string params = findObject( line, "params" );
    const std::string args   = findObject( params, "arguments" );
    for( const std::string* span : { &line, &params, &args } )
    {
        (void)objectKeys( *span );
        (void)findString( *span, "name" );
        (void)arrayStrings( *span, "paths" );
        (void)arrayStrings( *span, "symbols" );
        const std::string arr = findArray( *span, "queries" );
        (void)arrayObjects( arr );
        (void)arrayTopLevelElements( arr );
        const std::string edits = findArray( *span, "edits" );
        for( const std::string& obj : arrayObjects( edits ) )
        {
            (void)findString( obj, "new_body" );
            (void)objectKeys( obj );
        }
        forEachTopLevelKey( *span, 0, []( const auto&, const auto& ) { return false; } );
    }
    long long whole = 0;
    (void)parseWholeInt( std::string_view( line ).substr( 0, 32 ), whole );
    std::size_t decoded = 0;
    for( std::size_t at = line.find( '"' ); at != std::string::npos && decoded < 256; at = line.find( '"', at + 1 ), ++decoded )
    {
        (void)decodeStringAt( line, at );
        (void)stringEnd( line, at );
        (void)containerSpanAt( line, at, '{', '}' );
    }
    return 0;
}

// Repository documents: .ipynb JSON, HTML, CSV, and the generated-document classifier over markdown text.
int docparse( const std::uint8_t* data, std::size_t size )
{
    using namespace rw::docparse;
    std::string_view in( reinterpret_cast<const char*>( data ), size );
    const std::uint8_t pick = takeByte( in );
    switch( pick % 4 )
    {
        case 0: noteAccepted( !extractIpynb( in ).empty() ); break;
        case 1: noteAccepted( !extractHtml( in ).empty() ); break;
        case 2: noteAccepted( !extractCsv( in ).empty() ); break;
        default:
        {
            const MarkdownFenceScan scan = scanMarkdownFences( in );
            (void)fencedLineFraction( scan );
            (void)classifyGeneratedDoc( in, in.size(), 1024, 8 );
            noteAccepted( !in.empty() );
            break;
        }
    }
    return 0;
}

// --from-trace text: every frame parser, whole-trace extraction and the format vote.
int tracein( const std::uint8_t* data, std::size_t size )
{
    using namespace rw::tracein;
    const std::string_view text( reinterpret_cast<const char*>( data ), size );
    const FrameScan        scan = extractFrames( text );
    noteAccepted( !scan.frames.empty() );
    (void)dominantFormat( scan.frames );
    std::size_t lineStart = 0;
    for( std::size_t lineIndex = 0; lineStart <= text.size() && lineIndex < 64; ++lineIndex )
    {
        std::size_t lineEnd = text.find( '\n', lineStart );
        if( lineEnd == std::string_view::npos )
        {
            lineEnd = text.size();
        }
        const std::string_view line = text.substr( lineStart, lineEnd - lineStart );
        (void)detail::parsePython( line );
        (void)detail::parseAsan( line );
        (void)detail::parseNode( line );
        (void)detail::parseCompiler( line );
        (void)detail::parseGeneric( line );
        (void)isFrameShapedLine( line );
        lineStart = lineEnd + 1;
    }
    return 0;
}

// An untrusted SKILL.md: the injection/exfiltration scanner `ripwire wrap` and --scan-skills run before install.
int skillscan( const std::uint8_t* data, std::size_t size )
{
    const std::string_view text( reinterpret_cast<const char*>( data ), size );
    (void)rw::scanSkillText( text );
    noteAccepted( text.starts_with( "---" ) );
    return 0;
}

}   // namespace rwfuzz
