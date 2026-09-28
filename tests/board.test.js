import test from 'node:test';import assert from 'node:assert/strict';import {toCards,safeCards} from '../src/board.js';
test('makes only cards from real notes',()=>{const cards=toCards({points:['First'],actions:['Submit']});assert.deepEqual(cards.map(c=>c.text),['First','Submit']);assert.deepEqual(cards.map(c=>c.type),['point','action'])});
test('empty notes make no claims',()=>assert.deepEqual(toCards({points:[],actions:[]}),[]));
test('rejects malformed saved board cards',()=>assert.deepEqual(safeCards([{type:'fake',text:'X'}]),[]));
