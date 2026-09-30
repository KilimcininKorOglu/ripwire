// The FUNCTION-DECLARATION form of the same shape: `done` is a name of createTimer's scope, returned as a member.
export const createTimer = () => {
    function done(): void { console.log( "timer" ); }
    return { done };
};
