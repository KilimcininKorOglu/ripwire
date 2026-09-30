// The same helper, copied into a sibling test file: its `run` PARAMETER names nothing in a.test.ts either.
const captureStdout = async ( run: () => Promise<unknown> ): Promise<string> => {
    await run();
    return "out";
};

describe( "b", () => {
    it( "captures", async () => {
        await captureStdout( async () => 2 );
    } );
} );
