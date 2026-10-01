// A class the caller imports and types its parameter with: `tui.start()` means THIS start.
export class Tui
{
    start( label: string ): void { console.log( label ); }
    done(): void { console.log( "done" ); }
}
