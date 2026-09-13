#!/usr/bin/env python3
"""testrowpaths.py — THE tests_to_run row reader every gate shares.

WHY THIS FILE EXISTS. Six gates read the PATHS out of the tests_to_run row family — affectedcheck,
impactpartitioncheck, receiptpostcheck, rootrelemitcheck, selectorchaincheck, testrowruncheck — and each one
had grown its own reader: `grep -oE '<t p="[^"]*"'`, `sed -n 's/.*<test p="\\([^"]*\\)".*/\\1/p'`,
`grep -oE '"tests_to_run":\\[[^]]*\\]'`, `awk '{print $1}'`. Every one of them was written when a row was
one path, and E1 (2026-09-12) made a row possibly be SEVERAL — `<g n="3" p="a,b,c"/>` in XML, a `"p"`
ARRAY in JSON, `[hops=2] (3): a, b, c` in the text dialect. The private readers did not fail; they went
QUIET or, worse, wrong:

  * `grep -oE '"tests_to_run":\\[[^]]*\\]'` stops at the first `]`, which is now the end of the FIRST
    group's path array — three gate arms asserted over two and a half rows and passed vacuously;
  * `sed -n 's/^test p=//'` and friends saw the singles and silently skipped every group row;
  * the text reader took `$1` of the line, which on a group line is `[hops=1]`, not a path.

The invariant all six actually want is THE FILES NAMED, in emitted order. That is one question, so it is
answered in one place, for every dialect, and a gate that adds a new assertion gets the group shapes for
free instead of re-deriving them. Two further gates read these rows and are NOT converted, because neither
asks for the paths: test/listingpagingcheck.sh sums `n=` over the <g> rows to prove the family never pages,
and test/w3fixlegendcheck.sh counts path occurrences on a --situ line. Both were made group-aware in place
(E1) and stay that way — routing a COUNT through a path reader would only add a dialect hop.

    python3 test/testrowpaths.py paths xml|json|text  [FILE]   # one path per line, emitted order
    python3 test/testrowpaths.py jsonlist             [FILE]   # the balanced "tests_to_run":[...] slice

FILE defaults to stdin. Exit 0 even when nothing matches: "no rows" is an answer a gate may be asserting,
and an empty stdout says it. Exit 2 only on a malformed document the reader cannot parse at all.

DIALECTS, and what counts as a row in each — the shapes testmap.h's seam emits, and nothing else:
  xml   <t p="…"/> and <test p="…"/> singles, <g … p="a,b,c" …/> groups. Comments are stripped FIRST, so
        the legend's own `<g n= p=a,b,c>` definition is never read as a row.
  json  every object inside the balanced "tests_to_run":[…] list whose "p" (or "test") key is a string or
        an array of strings. The list is sliced by bracket depth, not by the first `]`.
  text  --situ's `        path [hops=N]   (run: …)` singles and its
        `        [hops=N] (n): a, b, c   (run: not derivable)` group lines.

A path is emitted VERBATIM, exactly as the document spelled it, except that XML entity references are
decoded (`&amp;` `&lt;` `&gt;` `&quot;` `&#NN;`) — a gate compares paths against the file names it created,
which are unescaped. Note that a path containing ',' is never grouped (testmap.h refuses to), so splitting
a group's p= on ',' cannot split a path in half.
"""

import json
import re
import sys

_ENT = { "amp": "&", "lt": "<", "gt": ">", "quot": '"', "apos": "'" }


def xml_unescape( s ):
    def one( m ):
        body = m.group( 1 )
        if body.startswith( "#" ):
            try:
                return chr( int( body[2:], 16 ) if body[1:2].lower() == "x" else int( body[1:], 10 ) )
            except ValueError:
                return m.group( 0 )
        return _ENT.get( body, m.group( 0 ) )
    return re.sub( r"&([#0-9A-Za-z]+);", one, s )


def strip_comments( doc ):
    """Drop every <!-- … --> run. The legends define the row shapes they describe, so a reader that keeps
    comments reads the DEFINITION of <g n= p=a,b,c> as a row with the paths 'a', 'b' and 'c'."""
    return re.sub( r"<!--.*?-->", "", doc, flags = re.S )


def xml_paths( doc ):
    """The test FILES an XML document names, in emitted order.

    `<g` is NOT a tests_to_run element on its own: --flags spells a gate row `<g n="NAME" … p="src/x.h"/>`
    with the same opener. A tests_to_run group is qualified by run_unknown="1", which every group row carries
    by construction (a group exists only where no runner is derivable), so that is what this reader matches —
    the same qualification the compact legend uses to keep the two readings of `<g>` apart."""
    out = []
    for m in re.finditer( r'<(?:t|test|g)\b[^>]*?\bp="([^"]*)"[^>]*/>', strip_comments( doc ) ):
        row = m.group( 0 )
        raw = m.group( 1 )
        if row.startswith( "<g " ):
            if 'run_unknown="1"' not in row:
                continue                                        # --flags' own <g> gate row, not a test group
            # a group's p= is a comma-separated list; a path containing ',' is never grouped (testmap.h
            # refuses to), so splitting on ',' cannot split a path in half.
            out.extend( xml_unescape( p ) for p in raw.split( "," ) if p != "" )
        else:
            out.append( xml_unescape( raw ) )
    return out


class TestRowParseError( Exception ):
    """A document that NAMES a tests_to_run list this reader cannot read to its end.

    CodeRabbit on #214: this was not distinguished from the field being absent. Both returned None, json_paths
    turned None into [], and the caller got an empty answer and exit 0 — so a TRUNCATED document (a gate that
    captured a killed run, a byte cap that cut mid-array) asserted over zero rows and passed vacuously. That is
    the very failure this file was written to end. The two cases are not the same claim: no `tests_to_run` field
    is an ANSWER ("this document serves no such list", None -> []), while a field whose array never closes is a
    document this reader cannot read at all, and the only honest thing to return is an error. Exit 2, as the
    module header promises for exactly this."""


def json_list_slice( doc ):
    """The "tests_to_run":[…] value, sliced by BRACKET DEPTH (a group row's "p" is itself an array, so the
    first ']' is not the end of the list) and string-aware (a ']' inside a path is not a bracket).

    Returns None when the document has no "tests_to_run" field at all. Raises TestRowParseError when it has
    one that this reader cannot slice — see that class for why the two are not the same answer."""
    i = doc.find( '"tests_to_run"' )
    if i < 0:
        return None
    i = doc.find( "[", i )
    if i < 0:
        raise TestRowParseError( '"tests_to_run" is present but is followed by no "[" — not a list at all' )
    depth = 0
    instr = False
    esc = False
    for k in range( i, len( doc ) ):
        c = doc[k]
        if instr:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                instr = False
            continue
        if c == '"':
            instr = True
        elif c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                return doc[i:k + 1]
    raise TestRowParseError( '"tests_to_run" list is never closed: %d bracket(s) still open at end of document '
                             '(%d bytes read from the field)' % ( depth, len( doc ) - i ) )


def json_paths( doc ):
    sl = json_list_slice( doc )
    if sl is None:
        return []
    rows = json.loads( sl )
    out = []
    for r in rows:
        if not isinstance( r, dict ):
            continue
        p = r.get( "p", r.get( "test" ) )
        if isinstance( p, list ):
            out.extend( str( x ) for x in p )
        elif isinstance( p, str ):
            out.append( p )
    return out


# The text dialect's row grammar, spelled from the RENDERER rather than guessed at (testmap.h: the Text arm
# of testRowEvidence, and runSuffixTextDisclosed). A row is
#
#     <indent><path>[ [changed]][ [partner]][ [hops=N]]   (run: <cmd>|not derivable)
#
# and a GROUP row replaces <path> with "<attrs> (n): a, b, c", its attrs leading. The three evidence
# attributes are optional, but they are emitted in THAT ORDER and no other, and the run suffix always opens
# with exactly three spaces. So the whole tail of a row is a closed, known shape.
#
# CodeRabbit on #214: the single-row reader took `(\S+)`, which stops at the first space — a test path
# holding a space was reported TRUNCATED, silently, as a path that does not exist. A generic bracket matcher
# would have the mirror-image bug (a path holding "[...]" would lose it), which is why this is pinned to the
# renderer's own sequence instead: everything before the known attribute tail is the path, spaces included.
# The one ambiguity left is the dialect's, not the reader's — text carries NO escaping, so a path containing
# the literal three-space "(run: " opener cannot be told from the suffix. XML and JSON are exact; a gate that
# needs a path that adversarial should assert in one of those.
_TEXT_RUN_OPEN = "   (run: "
_TEXT_ATTR_TAIL = re.compile( r"(?: \[changed\])?(?: \[partner\])?(?: \[hops=\d+\])?$" )
_TEXT_GROUP = re.compile( r"^\s*(?:\[[^\]]*\]\s*)*\((\d+)\):\s*(.*?)\s{2,}\(run: " )


def text_paths( doc ):
    out = []
    for line in doc.split( "\n" ):
        if _TEXT_RUN_OPEN not in line or not line.rstrip( "\r" ).endswith( ")" ):
            continue
        g = _TEXT_GROUP.match( line )
        if g:
            out.extend( p.strip() for p in g.group( 2 ).split( "," ) if p.strip() )
            continue
        # a SINGLE row: cut the run suffix, then the known attribute tail; what is left of the indent is the
        # path, verbatim — spaces and all.
        head = line[ :line.index( _TEXT_RUN_OPEN ) ]
        head = _TEXT_ATTR_TAIL.sub( "", head )
        path = head.strip()
        if path:
            out.append( path )
    return out


def main( argv ):
    if len( argv ) < 2:
        sys.stderr.write( __doc__ )
        return 2
    mode = argv[1]
    if mode == "jsonlist":
        src = argv[2] if len( argv ) > 2 else None
        doc = open( src ).read() if src else sys.stdin.read()
        try:                                                    # an unbalanced list is exit 2 here too, not ""
            sl = json_list_slice( doc )
        except TestRowParseError as e:
            sys.stderr.write( "testrowpaths: json dialect unreadable: %s\n" % e )
            return 2
        sys.stdout.write( sl if sl else "" )
        return 0
    if mode != "paths" or len( argv ) < 3:
        sys.stderr.write( __doc__ )
        return 2
    dialect = argv[2]
    src = argv[3] if len( argv ) > 3 else None
    doc = open( src ).read() if src else sys.stdin.read()
    try:
        if dialect == "xml":
            paths = xml_paths( doc )
        elif dialect == "json":
            paths = json_paths( doc )
        elif dialect == "text":
            paths = text_paths( doc )
        else:
            sys.stderr.write( "testrowpaths: unknown dialect %r (xml|json|text)\n" % dialect )
            return 2
    except Exception as e:                                      # a document this reader cannot parse at all
        sys.stderr.write( "testrowpaths: %s dialect unreadable: %s\n" % ( dialect, e ) )
        return 2
    for p in paths:
        sys.stdout.write( p + "\n" )
    return 0


if __name__ == "__main__":
    sys.exit( main( sys.argv ) )
