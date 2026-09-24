import { add } from "./lib";
import { expect } from "chai";

describe( "add", () => { it( "adds", () => { expect( add( 1, 2 ) ).to.equal( 3 ); } ); } );
