// C++ TEMPLATE-ARGUMENT CALL fixture — read by test/cppqualcheck.sh §12.
//
// A MEMBER call whose callee carries explicit template arguments — `r.f<T>( x )`, `p->f<T>( x )`,
// `x.template f<T>()` — parses as
//     call_expression function: (field_expression field: (template_method name: (field_identifier)))
// or, with the `template` disambiguator, `field: (dependent_name (template_method …))`. No C++ reference
// pattern matched either shape, so every such call minted NO reference at all: --callers/--uses/--impact
// read zero and --quality-delta called a method reached only this way dead-code. The QUALIFIED dependent
// form (`X::template f<T>()`) did extract, but under the NAME `template f`, and a scope spelled
// `X::template Rebind<T>::g()` keyed its qualifier as `template Rebind` — a name no definition carries.
//
// §12a: EVERY callee has a UNIQUE name, so `--uses=<name>` is the number of call sites written below for
// that name, read off this file by hand — never derived by running the query the extractor runs (plan §7
// trap 1). Spellings 6-9 are CONTROLS the pre-round patterns already bound.
// §12b: the names are SHARED on purpose — each decoy is a same-final-name definition the call must NOT bind.

namespace tq
{

template <typename T> T tqQualTmpl( int n ) { return T( n ); }

template <int I> int tqIndexTmpl( int n ) { return n + I; }

enum class TqKind : unsigned char { A, B };

struct TqHolder
{
    template <typename T> static T tqStaticTmpl( int n ) { return T( n ); }
};

}   // namespace tq

template <typename T> T tqFreeTmpl( int n ) { return T( n ); }

template <typename A, typename B> struct TqPair { A first; B second; };

struct TqReader
{
    template <typename E> E tqDotTmpl( int n ) { return E( n ); }
    template <typename E> E tqArrowTmpl( int n ) { return E( n ); }
    template <typename E> E tqDepDotTmpl( int n ) { return E( n ); }
    template <typename E> E tqDepArrowTmpl( int n ) { return E( n ); }
    template <typename E> int tqNestedArgTmpl( int n ) { return n; }
};

struct TqOuter
{
    TqReader reader;
};

template <typename Self> struct TqCrtp
{
    template <typename E> E tqThisTmpl( int n ) { return E( n ); }
    int viaThis() { return this->template tqThisTmpl<int>( 5 ); }                 // 5. this->template f<T>()
};

struct TqMaker
{
    template <typename T> static T tqDepQualTmpl( int n ) { return T( n ); }
    template <typename T> static T tqCommentDepTmpl( int n ) { return T( n ); }
    struct Inner
    {
        template <typename T> static T tqDeepDepTmpl( int n ) { return T( n ); }
    };
};

// ── §12a the spellings ─────────────────────────────────────────────────────────────────────────────
int tqCallMember( TqReader& r, TqReader* p )
{
    int a = int( r.tqDotTmpl<tq::TqKind>( 1 ) );                                  // 1. member dot — the defect's repro shape
    a += p->tqArrowTmpl<int>( 2 );                                                // 2. member arrow
    return a;
}

template <typename X> int tqCallDependent( X& x, X* px )
{
    return x.template tqDepDotTmpl<int>( 3 )                                      // 3. x.template f<T>()
         + px->template tqDepArrowTmpl<int>( 4 );                                 // 4. p->template f<T>()
}

int tqCallControls()
{
    return tqFreeTmpl<int>( 6 )                                                   // 6. CONTROL: free f<T>( x )
         + tq::tqQualTmpl<int>( 7 )                                               // 7. CONTROL: ns::f<T>( x )
         + tq::tqIndexTmpl<0>( 8 )                                                // 8. CONTROL: std::get<0>( t )-style non-type argument
         + tq::TqHolder::tqStaticTmpl<int>( 9 );                                  // 9. CONTROL: 3-segment static member template
}

template <typename X> int tqCallDependentQualified()
{
    return X::template tqDepQualTmpl<int>( 10 )                                   // 10. X::template f<T>() — was named `template tqDepQualTmpl`
         + X::Inner::template tqDeepDepTmpl<int>( 11 )                            // 11. X::Y::template f<T>() — same, through the re-split
         + X::template /* disambiguated */ tqCommentDepTmpl<int>( 15 );           // 15. a comment between the keyword and the name
}

int tqCallShapes( TqReader& r, TqOuter& o )
{
    return r.tqNestedArgTmpl<TqPair<int, TqPair<tq::TqKind, int>>>( 12 )          // 12. nested template arguments closing on `>>`
         + o.reader.tqDotTmpl<int>( 13 );                                         // 13. member template through a chained receiver
}

// ── §12b precision: the RIGHT definition, not merely a definition ──────────────────────────────────
struct TqTarget
{
    template <typename E> E tqPick( int n ) { return E( n ); }
};

struct TqDecoy
{
    template <typename E> E tqPick( int n ) { return E( n ); }                   // RECEIVER decoy: same name, same arity

    // `other` is a TqTarget LOCAL, so this binds TqTarget::tqPick; read as a BARE call the enclosing-class
    // rule pins TqDecoy::tqPick. A local, not a parameter: Rule 2 reads no parameter type (model.h ParamType).
    int tqDecoyCaller() { TqTarget other; return other.tqPick<int>( 1 ); }

    // `this->template`: the enclosing class is the receiver, so this binds TqDecoy::tqPick.
    int tqSelfCaller() { return this->template tqPick<int>( 2 ); }
};

struct TqArity
{
    template <typename E> E tqArityPick( int n ) { return E( n ); }
    template <typename E> E tqArityPick( int n, int m ) { return E( n + m ); }   // ARITY decoy: two parameters
};

// Two arguments bind the two-parameter overload only — through template_method (3 hops from the name to the
// call) and behind `template` (4 hops, callArity's whole bound). Free functions, so no enclosing class narrows
// first and the arity prune is what decides.
int tqArityCaller( TqArity& a ) { return a.tqArityPick<int>( 3, 4 ); }
int tqDepArityCaller( TqArity& a ) { return a.template tqArityPick<int>( 5, 6 ); }

template <typename T> struct TqRebind { static int tqScopedFn( int n ) { return n; } };
struct TqOtherScope { static int tqScopedFn( int n ) { return n; } };                    // QUALIFIER decoy

// `X::template TqRebind<int>::tqScopedFn` keys on the immediate scope `TqRebind`, so it binds that
// definition; keyed as `template TqRebind` the canonical tier misses and both definitions tie.
template <typename X> int tqCallRebind() { return X::template TqRebind<int>::tqScopedFn( 14 ); }
