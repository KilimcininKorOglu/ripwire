const test = require( "node:test" );
const assert = require( "node:assert" );
const { add } = require( "./lib" );

test( "adds", () => { assert.strictEqual( add( 1, 2 ), 3 ); } );
