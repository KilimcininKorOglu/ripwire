// fnliteralcheck fixture (TypeScript). Every name below that is bound to a function literal owns a body;
// the gate asserts --callees reports it as a definition WITH a body (bodyless_defs absent/0) and that
// --metrics reads params/cx from the literal itself.

function sink( v: number ): number
{
    return v + 1;
}

// block-bodied arrow const: params=2, cx=2 (one if)
const blockArrow = ( a: number, b: number ) => {
    if( a > b )
    {
        return sink( a );
    }
    return sink( b );
};

// concise arrow const — the body is an expression, not a statement_block
const conciseArrow = ( p: string ) => sink( p.length );

// a lone parameter without parens — no formal_parameters list: params=1 all the same
const bareParam = x => sink( x );

// function_expression bound to a const
const fnExprConst = function( x: number ) { return sink( x ); };

// exported const — the export_statement wraps the lexical_declaration
export const exportedArrow = ( x: number ) => {
    return sink( x );
};

// the typed-const cast forms: the arrow sits under as_expression / satisfies_expression + parens.
// The inline TYPE annotation carries its own formal_parameters (three of them) ahead of the arrow — params
// must come from the arrow (one), not the type.
type Fn3 = ( a: number, b: number, c: number ) => number;
export const castArrow: ( a: number, b: number, c: number ) => number = ( ( x: number ) => sink( x ) ) as Fn3;
export const satisfiesArrow = ( ( x: number ) => sink( x ) ) satisfies ( x: number ) => number;

// two declarators in one declaration: each name gets ITS OWN literal's body
const firstOfTwo = ( x: number ) => sink( x ),
      secondOfTwo = ( y: number, z: number ) => sink( y + z );

class Widget
{
    // class-field arrow — the bound-method idiom
    handle = ( e: number ) => {
        return sink( e );
    };
}

// a nested callback passed as an argument is NOT a definition
export function withCallback( xs: number[] ): number[]
{
    return xs.map( ( x ) => sink( x ) );
}

// a real bodyless declaration stays bodyless
declare function declaredOnly( x: number ): void;
declare const declaredConst: ( x: number ) => void;
export function overloaded( x: number ): number;
export function overloaded( x: string ): number;
export function overloaded( x: number | string ): number
{
    return sink( Number( x ) );
}

export function useAll(): number
{
    const w = new Widget();
    w.handle( 1 );
    declaredOnly( 1 );
    declaredConst( 1 );
    return blockArrow( 1, 2 ) + conciseArrow( "a" ) + bareParam( 1 ) + fnExprConst( 1 ) + exportedArrow( 1 ) + castArrow( 1, 2, 3 )
           + satisfiesArrow( 1 ) + firstOfTwo( 1 ) + secondOfTwo( 1, 2 ) + overloaded( 1 ) + withCallback( [] ).length;
}
