const test = require('node:test');
const assert = require('node:assert');
const { collapseRepeats, applyVocabulary } = require('../web/asrtext.js');

test('collapses looping phrases', () => {
  assert.strictEqual(collapseRepeats('yah hai raha hai raha hai raha hai raha hai'), 'yah hai raha hai');
  assert.strictEqual(collapseRepeats('aapko aapko aapko aapko aapko'), 'aapko');
});
test('keeps normal speech and short repeats', () => {
  assert.strictEqual(collapseRepeats('no no that is fine'), 'no no that is fine');
  assert.strictEqual(collapseRepeats('kal kal milte hain'), 'kal kal milte hain');
});
test('snaps near misses to the vocabulary', () => {
  assert.strictEqual(applyVocabulary('send it to Sanskar tomorrow', ['Sanskar']), 'send it to Sanskar tomorrow');
  assert.strictEqual(applyVocabulary('send it to Sanskaar tomorrow', ['Sanskar']), 'send it to Sanskar tomorrow');
  assert.strictEqual(applyVocabulary('meeting with Vyomm about voyno', ['Vyom', 'Voino']), 'meeting with Vyom about Voino');
});
test('does not touch unrelated or short words', () => {
  assert.strictEqual(applyVocabulary('the rain in Spain', ['Sanskar', 'Voino']), 'the rain in Spain');
  assert.strictEqual(applyVocabulary('send it', ['Sanskar']), 'send it');
});
