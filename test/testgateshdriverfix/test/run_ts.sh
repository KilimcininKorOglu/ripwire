#!/bin/bash
# drives test/lib.test.ts through the vendored runner
exec ./node_modules/.bin/vitest run test/lib.test.ts
