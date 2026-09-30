import test from 'node:test';
import assert from 'node:assert/strict';
import {makeNotes,exportText} from '../src/notes.js';
test('empty input never manufactures notes', () => assert.deepEqual(makeNotes(''), {title:'New note',points:[],actions:[],transcript:''}));
test('preserves source text and sorts explicit action phrases', () => {
 const n=makeNotes('Photosynthesis means plants turn sunlight into energy. Remember to submit the lab report Friday.',' Biology ');
 assert.equal(n.title,'Biology');
 assert.deepEqual(n.points,['Photosynthesis means plants turn sunlight into energy.']);
 assert.deepEqual(n.actions,['Remember to submit the lab report Friday.']);
 assert.match(exportText(n),/Original transcript/);
});
test('repeated sentence is not duplicated',()=>assert.equal(makeNotes('Cells are the basic units of life. Cells are the basic units of life.').points.length,1));
test('short transcript is not dropped',()=>assert.deepEqual(makeNotes('Hello.').points,['Hello.']));
test('short statements survive beside longer lecture sentences',()=>{
 const n=makeNotes('Cells divide. Photosynthesis means plants turn sunlight into energy. Submit the report Friday.');
 assert.deepEqual(n.points,['Cells divide.','Photosynthesis means plants turn sunlight into energy.']);
 assert.deepEqual(n.actions,['Submit the report Friday.']);
});
test('unpunctuated dictated words still become a card source',()=>assert.deepEqual(makeNotes('mitosis produces two cells').points,['mitosis produces two cells']));
