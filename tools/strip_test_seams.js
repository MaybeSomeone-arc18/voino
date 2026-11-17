#!/usr/bin/env node
// Strips VOINO TEST SEAM blocks from a built JS artifact, in place.
// Blocks are delimited in the source by:
//   // >>> VOINO TEST SEAM ...
//   ...code...
//   // <<< VOINO TEST SEAM
// Production builds must not ship the test seams at all: this removes the
// code from the artifact, so no injected global can activate them. Fails
// loudly on unbalanced or nested markers and when markers survive.
// Usage: node tools/strip_test_seams.js <file>
'use strict';
const fs = require('fs');

const file = process.argv[2];
if (!file) { console.error('usage: node tools/strip_test_seams.js <file>'); process.exit(2); }

const OPEN = />>> VOINO TEST SEAM/;
const CLOSE = /<<< VOINO TEST SEAM/;
const lines = fs.readFileSync(file, 'utf8').split('\n');

let inside = false;
let blocks = 0;
const out = [];
for (const line of lines) {
  const opens = OPEN.test(line);
  const closes = CLOSE.test(line);
  if (opens && closes) { console.error('marker open and close on the same line: ' + line); process.exit(1); }
  if (opens) {
    if (inside) { console.error('nested TEST SEAM block'); process.exit(1); }
    inside = true;
    blocks++;
    continue;
  }
  if (closes) {
    if (!inside) { console.error('TEST SEAM close without open'); process.exit(1); }
    inside = false;
    continue;
  }
  if (!inside) out.push(line);
}
if (inside) { console.error('unterminated TEST SEAM block'); process.exit(1); }
if (blocks === 0) { console.error('no TEST SEAM blocks found in ' + file + ' - markers lost?'); process.exit(1); }

const stripped = out.join('\n');
if (/VOINO TEST SEAM|voinoSegTest|__voinoTestAsr|voinoInitStallMs/.test(stripped)) {
  console.error('test seam identifiers survive stripping - refusing to write');
  process.exit(1);
}
fs.writeFileSync(file, stripped);
console.log('stripped ' + blocks + ' TEST SEAM block(s) from ' + file);
