// CodeRabbit follow-up (src/ingest_names.h:126, thread 4053600599): only an ASCII-lowercase first
// letter is an intrinsic tag. `_Widget` starts with `_`, a legal (non-lowercase) leading character for
// a component identifier, so it must be treated as a COMPONENT — a real call edge, not a filtered
// intrinsic tag — exactly like `<UniqueWidget />` in isolate/jsx.tsx.
function _Widget() {
  return <h1>Settings</h1>;
}

function UnderscoreWrapper() {
  return <_Widget />;
}
