#!/usr/bin/env python3
"""_common.py — the helpers every bench/slice harness needs, defined once.

`run_slicerecall.py` (the 2026-08-30 / 08-31 cpp rounds) and the 2026-09-20 py round's three
scripts all shell out to git and all index source by 1-based line number. Each had grown its own
copy; --quality-delta named the clone pairs, so they live here instead.
"""

import io, subprocess, tokenize


def sh( args, cwd=None, ok_fail=False ):
    """run a command, capture text, raise on failure unless ok_fail.

    errors="replace": external corpora carry non-UTF-8 bytes (ugrep's own test fixtures are
    deliberately latin-1/binary), and a diff that touches one must not abort a mine. Only content
    bytes are ever mangled — hunk headers and funcnames are ASCII by git's own format — so
    qualification is unaffected.
    """
    r = subprocess.run( args, cwd=cwd, capture_output=True, text=True, errors="replace" )
    if r.returncode != 0 and not ok_fail:
        raise RuntimeError( f"{args}: rc={r.returncode}\n{r.stderr[:500]}" )
    return r


def git( repo, *args, ok_fail=False ):
    """sh() with `git -C repo` prepended."""
    return sh( [ "git", "-C", str( repo ) ] + list( args ), ok_fail=ok_fail )


def line_text( lines, n ):
    """the 1-based n-th source line, or "" when n is outside the file."""
    return lines[ n - 1 ] if 0 < n <= len( lines ) else ""


def name_lines( source ):
    """{identifier: {line numbers where it occurs as a NAME token}} — the strict relevance oracle.

    AMENDMENT 2026-09-20 (b) of docs/research/slice-line-recall.md, taken AFTER inspecting the
    registered oracle's misses and reported BESIDE it, never instead of it: the registered oracle is
    a word regex over the line text, so it counts a variable's name inside a docstring, a comment or
    a string literal as an occurrence the slice ought to have rowed. Python's own tokenizer settles
    which occurrences are identifiers. A source the tokenizer refuses (py2 syntax, decode trouble)
    yields None, and its instance is then reported only under the registered oracle.
    """
    out = {}
    try:
        for tok in tokenize.generate_tokens( io.StringIO( source ).readline ):
            if tok.type == tokenize.NAME:
                out.setdefault( tok.string, set() ).add( tok.start[ 0 ] )
    except Exception:
        return None
    return out
