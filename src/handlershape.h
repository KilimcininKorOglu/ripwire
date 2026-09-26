#pragma once

// handlershape.h — structural shapes read off ONE parsed tree, for --quality-delta:
//
//   ERROR-MASKING, widened (kind error-masking; the empty/pass/comment-only rows stay in lintrules.h's
//   kErrorMaskRules query table):
//     log-only      a handler whose body is ONLY logging/print calls and never names the caught error —
//                   log-and-continue, the message survives and the error does not. Broad handlers only
//                   (one that catches everything, or the language's root error type): a narrow
//                   `except FileNotFoundError: print("no config, using defaults")` states its cause in its
//                   own type, and counting it would be the false positive this shape cannot afford.
//     rethrow-only  the ONLY handler of its try re-throws the error it caught, unchanged — a try/catch
//                   that does nothing. Sole handler, because `catch( Specific e ) { throw e; }` ahead of a
//                   `catch( Exception e )` sibling is the idiom that routes one type PAST the broad
//                   handler, and that is not redundant.
//
// WHY A WALK AND NOT A QUERY. Each shape is a question about ALL of a block's statements ("every statement
// is a log call") or about a name NOT occurring below a node ("the caught identifier is never read"), and
// a tree-sitter pattern can state neither. It rides the same read, parse and newline index as the query
// groups (AstWalk::HandlerShapes), so it costs a traversal, never a second parse.
//
// PRECISION BEFORE RECALL, by construction: every test below answers "not this shape" when it cannot
// decide — an unrecognised callee is not a log call, a destructured catch binding is not judged, a name
// inside a string counts as a reference. Each of those is a miss, never a finding.
// Measured precision per shape and language is in docs/EVALS.md ("error-masking widened"); the table
// kHandlerShapeGates in lintrules.h decides which shapes gate.

#include <cctype>
#include <cstdint>
#include <cstring>
#include <string_view>
#include <vector>

#include <tree_sitter/api.h>

#include "infra/Diagnostics.h"   // ASSUME
#include "infra/tschildren.h"
#include "model.h"   // Lang

namespace rw::hshape
{

// The two tags a hit carries; lintrules.h counts both under error-masking.
inline constexpr std::string_view kLogOnly     = "log-only";
inline constexpr std::string_view kRethrowOnly = "rethrow-only";

struct ShapeSpan
{
    std::uint32_t    startByte = 0;
    std::uint32_t    endByte   = 0;
    std::string_view tag;   // one of the two constants above — static storage, never a view into the file
};

// ── small readers ─────────────────────────────────────────────────────────────────────────────────────

// Every reader below is NULL-SAFE, because tree-sitter's are not: ts_node_end_byte and
// ts_node_child_by_field_name dereference the node's subtree/tree, so a missing optional field (a catch
// with no parameter, a raise with no argument) handed to either crashes the walk.
inline std::string_view nodeText( TSNode n, std::string_view src ) noexcept
{
    if( ts_node_is_null( n ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( n ), b = ts_node_end_byte( n );
    return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view();
}

inline TSNode namedChild( TSNode n, std::uint32_t index ) noexcept
{
    return ( ts_node_is_null( n ) || index >= ts_node_named_child_count( n ) ) ? TSNode{} : ts_node_named_child( n, index );
}

inline std::uint32_t namedCount( TSNode n ) noexcept
{
    return ts_node_is_null( n ) ? 0u : ts_node_named_child_count( n );
}

inline bool typeIs( TSNode n, const char* type ) noexcept
{
    return !ts_node_is_null( n ) && std::strcmp( ts_node_type( n ), type ) == 0;
}

inline bool isCommentNode( TSNode n ) noexcept
{
    return std::strstr( ts_node_type( n ), "comment" ) != nullptr;
}

inline TSNode field( TSNode n, const char* name ) noexcept
{
    if( ts_node_is_null( n ) )
    {
        return n;
    }
    return ts_node_child_by_field_name( n, name, static_cast<std::uint32_t>( std::strlen( name ) ) );
}

// The named, non-comment children of a statement container — the statements a shape judges. A comment
// is not a statement: `catch( e ) { // retry later <NL> log.warn( "x" ) }` is still log-only.
inline void statementsOf( TSNode body, std::vector<TSNode>& out )
{
    out.clear();
    if( ts_node_is_null( body ) )
    {
        return;
    }
    ChildCursor cursor( body );
    forEachNamedChild( body, cursor.cur, [ & ]( TSNode c )
    {
        if( !isCommentNode( c ) )
        {
            out.push_back( c );
        }
        return true;
    } );
}

// Does any NAMED LEAF below n spell `name`? Identifiers in every grammar are leaves, so this reads an
// f-string's `{e}`, a template's `${e}`, a Kotlin `"$e"` and a plain argument alike. A leaf inside a string
// literal that happens to equal the name also answers yes — a miss, never a finding.
inline bool mentionsName( TSNode n, std::string_view src, std::string_view name )
{
    if( name.empty() )
    {
        return false;
    }
    if( namedCount( n ) == 0 )
    {
        return !ts_node_is_null( n ) && ts_node_is_named( n ) && nodeText( n, src ) == name;
    }
    return anyChildBelow( n, -1, true, [ & ]( TSNode c )
                          { return ts_node_named_child_count( c ) == 0 && nodeText( c, src ) == name; } );
}

// The spellings that carry the CURRENT error without naming the caught identifier: Python's
// `exc_info=True` / `stack_info=` / `sys.exc_info()` / `traceback.format_exc()`, and Ruby's `$!`. A log
// call that passes one of them logs the error, so the handler is not log-only.
inline constexpr std::string_view kErrorCarriers[] = { "exc_info", "stack_info", "traceback", "format_exc", "print_exc", "$!", "$ERROR_INFO" };

inline bool mentionsError( TSNode body, std::string_view src, std::string_view name )
{
    if( mentionsName( body, src, name ) )
    {
        return true;
    }
    for( std::string_view carrier : kErrorCarriers )
    {
        if( mentionsName( body, src, carrier ) )
        {
            return true;
        }
    }
    return false;
}

// ── the handler, read per grammar ─────────────────────────────────────────────────────────────────────

struct Handler
{
    TSNode           body     = {};   // the statement container; null = no body at all
    std::string_view name;            // the caught identifier; empty = none bound
    bool             broad    = false;// catches everything, or the language's root error type
    bool             sole     = false;// the only handler its try has
    bool             filtered = false;// a C# `when` filter — the handler is conditional, never judged
};

// How many siblings of n (n included) share n's node type — "is this the only catch of its try".
inline std::uint32_t siblingsOfSameType( TSNode n )
{
    const TSNode parent = ts_node_parent( n );
    if( ts_node_is_null( parent ) )
    {
        return 1;
    }
    std::uint32_t count = 0;
    const char*   type  = ts_node_type( n );
    ChildCursor   cursor( parent );
    forEachNamedChild( parent, cursor.cur, [ & ]( TSNode c ) { count += std::strcmp( ts_node_type( c ), type ) == 0 ? 1u : 0u; return true; } );
    return count;
}

// The root error types a "broad" handler may name, across the grammars below. A qualified spelling is
// judged by its last segment (java.lang.Exception, System.Exception, ::std::exception).
inline bool isRootErrorType( std::string_view t ) noexcept
{
    const std::size_t cut = t.find_last_of( ".:" );
    if( cut != std::string_view::npos )
    {
        t = t.substr( cut + 1 );
    }
    return t == "Exception" || t == "BaseException" || t == "Throwable" || t == "RuntimeException" || t == "StandardError"
        || t == "exception";
}

inline void readPythonHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode value = field( n, "value" );
    TSNode       type  = value;
    if( typeIs( value, "as_pattern" ) )
    {
        type                = namedChild( value, 0 );
        const TSNode target = field( value, "alias" );
        const TSNode ident  = namedChild( target, 0 );
        h.name              = typeIs( ident, "identifier" ) ? nodeText( ident, src ) : std::string_view();
    }
    h.broad = ts_node_is_null( type ) || ( ( typeIs( type, "identifier" ) || typeIs( type, "attribute" ) ) && isRootErrorType( nodeText( type, src ) ) );
    h.body  = firstChildOfKind( n, true, { "block" } );
    const TSNode tryNode = ts_node_parent( n );
    h.sole  = siblingsOfSameType( n ) == 1 && ( ts_node_is_null( tryNode ) || ts_node_is_null( firstChildOfKind( tryNode, true, { "except_group_clause" } ) ) );
}

inline void readJavaScriptHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode param = field( n, "parameter" );
    h.name  = typeIs( param, "identifier" ) ? nodeText( param, src ) : std::string_view();
    h.broad = ts_node_is_null( param ) || typeIs( param, "identifier" );   // a JS catch catches everything; a destructured one is not judged
    h.body  = field( n, "body" );
    h.sole  = true;                                                        // a JS try has at most one catch
}

inline void readJavaHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode param = firstChildOfKind( n, true, { "catch_formal_parameter" } );
    if( ts_node_is_null( param ) )
    {
        return;
    }
    const TSNode name  = field( param, "name" );
    const TSNode types = firstChildOfKind( param, true, { "catch_type" } );
    h.name  = nodeText( name, src );
    h.broad = namedCount( types ) == 1 && isRootErrorType( nodeText( types, src ) );
    h.body  = field( n, "body" );
    h.sole  = siblingsOfSameType( n ) == 1;
}

inline void readCSharpHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode decl = firstChildOfKind( n, true, { "catch_declaration" } );
    h.filtered        = !ts_node_is_null( firstChildOfKind( n, true, { "catch_filter_clause" } ) );
    h.name            = ts_node_is_null( decl ) ? std::string_view() : nodeText( field( decl, "name" ), src );
    h.broad           = ts_node_is_null( decl ) || isRootErrorType( nodeText( field( decl, "type" ), src ) );
    h.body            = field( n, "body" );
    h.sole            = siblingsOfSameType( n ) == 1;
}

inline void readKotlinHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode ident = firstChildOfKind( n, true, { "simple_identifier" } );
    const TSNode type  = firstChildOfKind( n, true, { "user_type" } );
    h.name  = nodeText( ident, src );
    h.broad = !ts_node_is_null( type ) && isRootErrorType( nodeText( type, src ) );
    h.body  = firstChildOfKind( n, true, { "statements" } );
    h.sole  = siblingsOfSameType( n ) == 1;
}

inline void readRubyHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode exceptions = field( n, "exceptions" );
    const TSNode variable   = field( n, "variable" );
    const TSNode ident      = namedChild( variable, 0 );
    h.name  = typeIs( ident, "identifier" ) ? nodeText( ident, src ) : std::string_view();
    h.broad = ts_node_is_null( exceptions )
           || ( namedCount( exceptions ) == 1 && isRootErrorType( nodeText( namedChild( exceptions, 0 ), src ) ) );
    h.body  = field( n, "body" );
    h.sole  = siblingsOfSameType( n ) == 1;
}

inline void readCppHandler( TSNode n, std::string_view src, Handler& h )
{
    const TSNode params = field( n, "parameters" );
    const TSNode decl   = namedChild( params, 0 );
    if( !ts_node_is_null( decl ) )
    {
        TSNode d = field( decl, "declarator" );
        while( !typeIs( d, "identifier" ) && namedCount( d ) > 0 )
        {
            d = namedChild( d, namedCount( d ) - 1 );   // & / && / * wrappers carry the name last
        }
        h.name = typeIs( d, "identifier" ) ? nodeText( d, src ) : std::string_view();
    }
    h.broad = ts_node_is_null( decl );   // catch( ... ): C++ has no root error type every throw derives from
    h.body  = field( n, "body" );
    h.sole  = siblingsOfSameType( n ) == 1;
}

// One row per grammar: which node is a handler there, and who reads it. A grammar absent from the table has
// no handler shape (Go's `if err != nil` is its own reader below; Rust, Swift and the rest are not judged).
struct HandlerReader
{
    Lang        lang;
    const char* nodeType;
    void ( *read )( TSNode, std::string_view, Handler& );
};

inline constexpr HandlerReader kHandlerReaders[] = {
    { Lang::Python,     "except_clause", readPythonHandler     },
    { Lang::JavaScript, "catch_clause",  readJavaScriptHandler },
    { Lang::TypeScript, "catch_clause",  readJavaScriptHandler },
    { Lang::Java,       "catch_clause",  readJavaHandler       },
    { Lang::CSharp,     "catch_clause",  readCSharpHandler     },
    { Lang::Kotlin,     "catch_block",   readKotlinHandler     },
    { Lang::Ruby,       "rescue",        readRubyHandler       },
    { Lang::Cpp,        "catch_clause",  readCppHandler        },
};

// ── what a statement IS ───────────────────────────────────────────────────────────────────────────────

// Unwrap a statement to the expression it evaluates (expression_statement → its one child).
inline TSNode statementExpression( TSNode s ) noexcept
{
    if( typeIs( s, "expression_statement" ) && namedCount( s ) == 1 )
    {
        return namedChild( s, 0 );
    }
    return s;
}

inline bool isCallNode( TSNode n ) noexcept
{
    return typeIs( n, "call" ) || typeIs( n, "call_expression" ) || typeIs( n, "method_invocation" ) || typeIs( n, "invocation_expression" );
}

// The callee of a call, as source text: `print`, `logger.warning`, `console.error`, `System.out.println`,
// `log.Printf`. Java's and Ruby's calls keep the receiver in its own field, so it is joined back on.
inline std::string_view calleeText( TSNode call, std::string_view src, std::string_view& receiverOut ) noexcept
{
    receiverOut = {};
    if( typeIs( call, "method_invocation" ) )
    {
        receiverOut = nodeText( field( call, "object" ), src );
        return nodeText( field( call, "name" ), src );
    }
    if( typeIs( call, "call" ) && !ts_node_is_null( field( call, "method" ) ) )   // Ruby
    {
        receiverOut = nodeText( field( call, "receiver" ), src );
        return nodeText( field( call, "method" ), src );
    }
    TSNode fn = field( call, "function" );
    if( ts_node_is_null( fn ) )
    {
        fn = namedChild( call, 0 );   // Kotlin: the callee is the first child, no field
    }
    const std::string_view text = nodeText( fn, src );
    const std::size_t      dot  = text.find_last_of( '.' );
    if( dot == std::string_view::npos )
    {
        return text;
    }
    receiverOut = text.substr( 0, dot );
    return text.substr( dot + 1 );
}

inline bool iequalsAscii( std::string_view a, std::string_view b ) noexcept
{
    if( a.size() != b.size() )
    {
        return false;
    }
    for( std::size_t i = 0; i < a.size(); ++i )
    {
        const char x = ( a[i] >= 'A' && a[i] <= 'Z' ) ? char( a[i] - 'A' + 'a' ) : a[i];
        const char y = ( b[i] >= 'A' && b[i] <= 'Z' ) ? char( b[i] - 'A' + 'a' ) : b[i];
        if( x != y )
        {
            return false;
        }
    }
    return true;
}

inline bool containsLogWord( std::string_view s ) noexcept
{
    for( std::size_t i = 0; i + 3 <= s.size(); ++i )
    {
        if( iequalsAscii( s.substr( i, 3 ), "log" ) )
        {
            return true;
        }
    }
    return false;
}

// A logging receiver: anything whose LAST segment says log (logger, log, LOG, logging, _log, self.logger,
// Rails.logger), or one of the console/stream spellings every grammar here uses for print-to-a-reader.
inline bool isLogReceiver( std::string_view recv ) noexcept
{
    const std::size_t      dot  = recv.find_last_of( '.' );
    const std::string_view last = ( dot == std::string_view::npos ) ? recv : recv.substr( dot + 1 );
    return containsLogWord( last ) || last == "console" || last == "Console" || last == "out" || last == "err" || last == "stderr"
        || last == "stdout" || last == "warnings" || last == "fmt" || last == "Debug" || last == "Trace";
}

// The verbs a logging call ends in. `exception` is deliberately ABSENT (Python's logger.exception writes
// the traceback — it logs the error), and so are fatal/Fatal*/panic/Panic* (they end the program, which is
// not continuing past the error).
inline constexpr std::string_view kLogVerbs[] = {
    "debug", "info", "warn", "warning", "error", "critical", "log", "trace", "verbose", "notice", "severe", "fine",
    "print", "println", "printf", "write", "writeln", "writeline", "debugf", "infof", "warnf", "warningf", "errorf",
};

inline constexpr std::string_view kBarePrintCalls[] = { "print", "println", "printf", "puts", "warn", "eprint", "eprintln", "p" };

// Is this statement ONE logging/print call? An unrecognised callee answers no — the shape then does not
// fire, which is a miss and never a finding.
inline bool isLogCall( TSNode stmt, std::string_view src ) noexcept
{
    const TSNode call = statementExpression( stmt );
    if( !isCallNode( call ) )
    {
        return false;
    }
    std::string_view       recv;
    const std::string_view verb = calleeText( call, src, recv );
    if( recv.empty() )
    {
        for( std::string_view bare : kBarePrintCalls )
        {
            if( verb == bare )
            {
                return true;
            }
        }
        return false;
    }
    if( recv == "fmt" && ( verb == "Errorf" || verb.starts_with( "S" ) ) )
    {
        return false;   // fmt.Errorf / Sprintf BUILD a value; they print nothing
    }
    for( std::string_view v : kLogVerbs )
    {
        if( iequalsAscii( verb, v ) )
        {
            return isLogReceiver( recv );
        }
    }
    return false;
}

// A statement that re-raises the caught error unchanged: bare `raise` / `throw;`, or raise/throw of the
// caught name itself. `raise e from x` changes the chain and is not unchanged.
inline bool isRethrowOf( TSNode stmt, std::string_view src, std::string_view name ) noexcept
{
    const TSNode s = statementExpression( stmt );
    if( typeIs( s, "identifier" ) && nodeText( s, src ) == "raise" )
    {
        return true;   // Ruby: a bare `raise` parses as an identifier
    }
    const bool isThrow = typeIs( s, "raise_statement" ) || typeIs( s, "throw_statement" )
                      || ( typeIs( s, "jump_expression" ) && nodeText( s, src ).starts_with( "throw" ) );
    const bool isRubyRaise = typeIs( s, "call" ) && nodeText( field( s, "method" ), src ) == "raise" && ts_node_is_null( field( s, "receiver" ) );
    if( !isThrow && !isRubyRaise )
    {
        return false;
    }
    if( !ts_node_is_null( field( s, "cause" ) ) )
    {
        return false;
    }
    const TSNode arg = isRubyRaise ? field( s, "arguments" ) : s;
    const std::uint32_t argCount = namedCount( arg );
    if( argCount == 0 )
    {
        return !isRubyRaise || ts_node_is_null( arg );
    }
    return argCount == 1 && !name.empty() && nodeText( namedChild( arg, 0 ), src ) == name;
}

// ── the two error-masking shapes over one handler ─────────────────────────────────────────────────────

inline std::string_view handlerShape( const Handler& h, std::string_view src, std::vector<TSNode>& stmts )
{
    if( h.filtered )
    {
        return {};
    }
    statementsOf( h.body, stmts );
    if( stmts.empty() )
    {
        return {};   // an EMPTY handler is kErrorMaskRules' row, not this shape
    }
    if( h.sole && stmts.size() == 1 && isRethrowOf( stmts[0], src, h.name ) )
    {
        return kRethrowOnly;
    }
    if( !h.broad )
    {
        return {};
    }
    for( const TSNode s : stmts )
    {
        if( !isLogCall( s, src ) )
        {
            return {};
        }
    }
    return mentionsError( h.body, src, h.name ) ? std::string_view() : kLogOnly;
}

// Go: `if err != nil { log.Printf( "…" ) }` — no else, the error-shaped name compared against nil, and a
// body of log calls that never reads it. A Fatal/Panic log is not a log verb above, so it never qualifies.
inline bool isGoErrName( std::string_view n ) noexcept
{
    return n == "err" || n.ends_with( "Err" ) || n.ends_with( "err" ) || ( n.starts_with( "err" ) && n.size() > 3 && n[3] >= 'A' && n[3] <= 'Z' );
}

inline std::string_view goLogOnlyShape( TSNode n, std::string_view src, std::vector<TSNode>& stmts )
{
    const TSNode cond = field( n, "condition" );
    if( !typeIs( cond, "binary_expression" ) || !ts_node_is_null( field( n, "alternative" ) ) )
    {
        return {};
    }
    const TSNode left = field( cond, "left" ), right = field( cond, "right" ), op = field( cond, "operator" );
    if( !typeIs( left, "identifier" ) || !typeIs( right, "nil" ) || nodeText( op, src ) != "!=" || !isGoErrName( nodeText( left, src ) ) )
    {
        return {};
    }
    const TSNode body = field( n, "consequence" );
    statementsOf( body, stmts );
    if( stmts.empty() )
    {
        return {};
    }
    for( const TSNode s : stmts )
    {
        if( !isLogCall( s, src ) )
        {
            return {};
        }
    }
    return mentionsError( body, src, nodeText( left, src ) ) ? std::string_view() : kLogOnly;
}

// ── the walk ──────────────────────────────────────────────────────────────────────────────────────────

inline const HandlerReader* handlerReaderFor( Lang lang, const char* type ) noexcept
{
    for( const HandlerReader& r : kHandlerReaders )
    {
        if( r.lang == lang && std::strcmp( r.nodeType, type ) == 0 )
        {
            return &r;
        }
    }
    return nullptr;
}

// The tag this ONE node carries, if any — empty for almost every node.
inline std::string_view shapeOfNode( TSNode n, std::string_view src, Lang lang, std::vector<TSNode>& stmts )
{
    const char* type = ts_node_type( n );
    if( const HandlerReader* reader = handlerReaderFor( lang, type ) )
    {
        Handler h;
        reader->read( n, src, h );
        return handlerShape( h, src, stmts );
    }
    if( lang == Lang::Go && std::strcmp( type, "if_statement" ) == 0 )
    {
        return goLogOnlyShape( n, src, stmts );
    }
    return {};
}

// Every hit in one file's tree, in document (DFS pre-) order. Explicit stack with the same pathological-depth
// guard the unreachable-code walk uses; a node that is a hit is still descended into (a stub inside a
// log-only handler is still read on its own).
inline void walkHandlerShapes( TSNode root, std::string_view src, Lang lang, std::vector<ShapeSpan>& out )
{
    struct Frame { TSNode node; std::uint16_t depth; };
    std::vector<Frame>  stack;
    std::vector<TSNode> kids;
    std::vector<TSNode> stmts;
    ChildCursor         cursor( root );
    stack.push_back( { root, 0 } );
    while( !stack.empty() )
    {
        const Frame frame = stack.back();
        stack.pop_back();
        if( frame.depth > 512 )
        {
            continue;   // pathological-AST guard, the same bound ur_walkTree uses
        }
        if( ts_node_is_named( frame.node ) )
        {
            const std::string_view tag = shapeOfNode( frame.node, src, lang, stmts );
            if( !tag.empty() )
            {
                ASSUME( tag == kLogOnly || tag == kRethrowOnly, "shapeOfNode answers one of the two tags or none" );
                out.push_back( { ts_node_start_byte( frame.node ), ts_node_end_byte( frame.node ), tag } );
            }
        }
        collectChildren( frame.node, cursor.cur, kids );
        for( std::size_t c = kids.size(); c > 0; --c )
        {
            stack.push_back( { kids[c - 1], static_cast<std::uint16_t>( frame.depth + 1 ) } );
        }
    }
}

}   // namespace rw::hshape
