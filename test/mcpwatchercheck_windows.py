"""Native Windows freshness-watcher gate for the MCP server."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import sys
import tempfile
import time


TEST_DIR = Path( __file__ ).resolve().parent
if str( TEST_DIR ) not in sys.path:
    sys.path.insert( 0, str( TEST_DIR ) )

from qsnapprefetchcheck_windows import Gate, Server  # noqa: E402
from sidecarsymlinkcheck_windows import Suite  # noqa: E402


def main() -> int:
    if len( sys.argv ) != 2:
        print( "usage: mcpwatchercheck_windows.py RIPWIRE_BIN", file=sys.stderr )
        return 2
    binary = Path( sys.argv[1] ).resolve()
    if not binary.is_file():
        print( f"no ripwire binary at {binary}", file=sys.stderr )
        return 2
    if os.name != "nt":
        print( "mcpwatchercheck_windows.py requires native Windows Python", file=sys.stderr )
        return 2

    with tempfile.TemporaryDirectory( prefix="ripwire-mcpwatcher-windows-" ) as temporary:
        base = Path( temporary )
        work = base / "work"
        source = work / "alpha" / "base.py"
        source.parent.mkdir( parents=True )
        source.write_text( "def base_probe():\n    return 1\n", encoding="utf-8" )
        suite = Suite( base, binary )
        print( f"mcpwatchercheck[windows]: BIN={binary} WORK={work}" )
        server = Server( binary, os.environ.copy() )
        try:
            initialized = server.call( 1, "initialize" )
            suite.check( "initialize", "result" in initialized, "MCP session initialized" )
            before = Gate.response_text( Gate.find( server, 2, work, "watcher_add_probe" ) )
            suite.check( "add/before", before.startswith( "__ERROR__:" ), "new symbol absent before the file is created" )

            def wait_for( request_id: int, symbol: str, present: bool ) -> None:
                deadline = time.monotonic() + 5.0
                last = ""
                while time.monotonic() < deadline:
                    last = Gate.response_text( Gate.find( server, request_id, work, symbol ) )
                    found = not last.startswith( "__ERROR__:" )
                    if found == present:
                        suite.check( f"{symbol}/watch", True, f"event delivered; present={found}" )
                        return
                    time.sleep( 0.05 )
                suite.check( f"{symbol}/watch", False, f"expected present={present}, last response={last[:240]!r}" )

            added = source.parent / "added.py"
            added.write_text( "def watcher_add_probe():\n    return 2\n", encoding="utf-8" )
            wait_for( 3, "watcher_add_probe", True )

            edited = source.parent / "edited.py"
            edited.write_text( "def watcher_edit_probe():\n    return 3\n", encoding="utf-8" )
            wait_for( 4, "watcher_edit_probe", True )
            edited.unlink()
            wait_for( 5, "watcher_edit_probe", False )

            nested_dir = source.parent / "nested"
            nested_dir.mkdir()
            nested = nested_dir / "nested.py"
            nested.write_text( "def watcher_nested_probe():\n    return 4\n", encoding="utf-8" )
            wait_for( 6, "watcher_nested_probe", True )
            nested.unlink()
            wait_for( 7, "watcher_nested_probe", False )

            Gate.find( server, 8, work, "base_probe" )
            shutil.rmtree( work )
            work.mkdir()
            deadline = time.monotonic() + 5.0
            last = ""
            while time.monotonic() < deadline:
                last = Gate.response_text( Gate.find( server, 9, work, "base_probe" ) )
                if last.startswith( "__ERROR__:" ):
                    suite.check( "root-replacement/watch", True, "replaced root does not serve the removed index" )
                    break
                time.sleep( 0.05 )
            else:
                suite.check( "root-replacement/watch", False, f"removed root symbol remained available: {last[:240]!r}" )
        except ( OSError, RuntimeError ) as exc:
            suite.check( "protocol", False, str( exc ) )
        finally:
            server.close()

    print( f"mcpwatchercheck[windows]: checks={suite.checks} failures={suite.failures}" )
    if suite.failures:
        return 1
    print( "ALL PASS" )
    return 0


if __name__ == "__main__":
    raise SystemExit( main() )
