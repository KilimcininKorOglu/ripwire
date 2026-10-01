import { Tui } from "../ui/tui.js";
import { createTracker } from "../agents/tracker.js";
import { createTimer } from "../agents/timer.js";

// `tui.start()` / `tui.done()`: the imported class's methods — the factory-local `start` (an arrow const) and `done` (a
// function declaration) in two other imported files are not in reach.
export function declCaller( tui: Tui ) { tui.start( "y" ); tui.done(); }
export const arrowCaller = ( tui: Tui ) => { tui.start( "x" ); tui.done(); };

// `t.stop()`: the member of the value createTracker returns — reached through the imported factory module, while the
// only other `stop` lives in a file this one never imports.
export function stopCaller() { const t = createTracker(); t.stop(); }

export function timerCaller() { return createTimer(); }
