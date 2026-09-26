# builtinbindfix — the builtin-method name gate (test/builtinbindcheck.sh)

Each language defines ONE in-repo method whose name is also a method of the language's builtin map, list or
string type (`get`, `push`, `fetch`), and calls that name from two kinds of file:

- a file that names the class (imports, constructs, annotates or subclasses it): the call may be on an
  instance, so the edge stays;
- a file that never names it (`plain.*`): the receiver is a dict, a Map, an Array, a Hash or a parameter of
  unknown type, so the call is declined and counted, never bound by name.

`java/` is the stated-scope control: Java has no table (no declared parameter type is extracted there), so its
calls keep the name ladder.
