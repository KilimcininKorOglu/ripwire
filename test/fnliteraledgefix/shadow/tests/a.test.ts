// `run` below is captureStdout's own PARAMETER: it can never name the `const run` bound inside the it() callback.
const captureStdout = async ( run: () => Promise<unknown> ): Promise<string> => {
    await run();
    return "out";
};

describe( "a", () => {
    it( "runs twice", async () => {
        const run = () => captureStdout( async () => 1 );
        await run();
    } );
} );
