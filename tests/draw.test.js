import test from 'node:test';import assert from 'node:assert/strict';import {safeShapes} from '../src/draw.js';
test('accepts only bounded circles and boxes',()=>{const shapes=safeShapes([{type:'circle',x:4,y:5,w:100,h:80},{type:'html',x:1,y:2}]);assert.equal(shapes.length,1);assert.deepEqual(shapes[0],{type:'circle',x:4,y:5,w:100,h:80})});
test('malformed shapes are ignored',()=>assert.deepEqual(safeShapes([{type:'box',x:NaN,y:1}]),[]));
