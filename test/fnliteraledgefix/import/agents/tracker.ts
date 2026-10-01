// A factory whose closures are FUNCTION-LOCAL: `start` and `stop` are names of createTracker's scope, handed out
// only as the returned object's members.
export const createTracker = () => {
    const start = (): void => { console.log( "tick" ); };
    const stop = (): void => { start(); };
    return { start, stop };
};
