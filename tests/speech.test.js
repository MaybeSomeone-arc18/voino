import test from 'node:test';import assert from 'node:assert/strict';import {stitchSpeech,speechSnapshot} from '../src/speech.js';
const r=(text,final=false)=>Object.assign([{transcript:text}],{isFinal:final});
test('Android incremental hypotheses show only latest utterance',()=>{
 assert.equal(speechSnapshot([r('the'),r('the meeting'),r('the meeting is Wednesday'),r('the meeting is Wednesday remember to send notes tonight')]),'the meeting is Wednesday remember to send notes tonight');
});
test('normal final segment and interim are joined once',()=>{
 assert.equal(speechSnapshot([r('The meeting is Wednesday.',true),r('Remember to send the slides',false)]),'The meeting is Wednesday. Remember to send the slides');
});
test('cumulative final segments do not duplicate shared prefix',()=>{
 assert.equal(speechSnapshot([r('the meeting',true),r('the meeting is Wednesday',true),r('is Wednesday remember to send notes',true)]),'the meeting is Wednesday remember to send notes');
});
test('separate final utterances are preserved',()=>{
 assert.equal(speechSnapshot([r('First point.',true),r('Second point.',true)]),'First point. Second point.');
});
test('overlap and repeated result are idempotent',()=>{
 assert.equal(stitchSpeech('meeting is Wednesday','is Wednesday send notes'),'meeting is Wednesday send notes');
 assert.equal(stitchSpeech('meeting is Wednesday','meeting is Wednesday'),'meeting is Wednesday');
});

test('network-start retry remains bounded',()=>{
 const retry=(reason,n,active)=>active&&reason==='network'&&n<2?750*(n+1):0;
 assert.equal(retry('network',0,true),750);assert.equal(retry('network',1,true),1500);
 assert.equal(retry('network',2,true),0);assert.equal(retry('not-allowed',0,true),0);assert.equal(retry('network',0,false),0);
});
test('raw Pages entry does not require static npm imports',async()=>{
 const {readFile}=await import('node:fs/promises');const source=await readFile(new URL('../src/app.js',import.meta.url),'utf8');
 assert.equal(/^import .*from ['"]@/m.test(source),false);
 assert.match(source,/if\(!isNative&&!WebSpeechRecognition\)showManualMode\(\)/);
 assert.equal(source.includes('recognition.stop()'),false);
});
