// fnliteralcheck fixture (JavaScript): the JS spellings of the same bindings.
function sinkJs( v )
{
    return v + 1;
}

const jsArrow = ( a, b ) => {
    if( a > b )
    {
        return sinkJs( a );
    }
    return sinkJs( b );
};

const jsConcise = ( p ) => sinkJs( p.length );

var jsLegacyVar = function( x ) { return sinkJs( x ); };

const handlers = {
    onPair: ( x ) => sinkJs( x ),
};

class JsWidget
{
    jsField = ( e ) => {
        return sinkJs( e );
    };
}

module.exports.jsExported = function( x ) { return sinkJs( x ); };

function jsWithCallback( xs )
{
    return xs.map( ( x ) => sinkJs( x ) );
}

module.exports.useJs = function() { return jsArrow( 1, 2 ) + jsConcise( "a" ) + jsLegacyVar( 1 ) + handlers.onPair( 1 ) + new JsWidget().jsField( 1 ) + jsWithCallback( [] ).length; };
