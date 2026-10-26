import { test, before, after } from 'node:test';
import { readFileSync } from 'fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, deleteDoc, getDocs, collection } from 'firebase/firestore';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'voinoo',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => { await testEnv.cleanup(); });

const board = (db, uid, id = 'b1') => doc(db, 'users', uid, 'boards', id);
const valid = () => ({
  title: 'Ideas',
  data: JSON.stringify({ title: 'Ideas', notes: [] }),
  updatedAt: new Date(),
});

test('unauthenticated: read, write, delete on a board all denied', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(board(db, 'u1')));
  await assertFails(setDoc(board(db, 'u1'), valid()));
  await assertFails(deleteDoc(board(db, 'u1')));
});

test('userA cannot read, write or delete userB boards', async () => {
  const alice = testEnv.authenticatedContext('alice').firestore();
  await assertFails(getDoc(board(alice, 'bob')));
  await assertFails(setDoc(board(alice, 'bob'), valid()));
  await assertFails(deleteDoc(board(alice, 'bob')));
});

test('malformed documents denied: extra key, missing updatedAt, string updatedAt, oversized data, long title', async () => {
  const db = testEnv.authenticatedContext('u1').firestore();
  await assertFails(setDoc(board(db, 'u1'), { ...valid(), evil: 1 }));
  const noTs = valid(); delete noTs.updatedAt;
  await assertFails(setDoc(board(db, 'u1'), noTs));
  await assertFails(setDoc(board(db, 'u1'), { ...valid(), updatedAt: 'now' }));
  await assertFails(setDoc(board(db, 'u1'), { ...valid(), data: 'x'.repeat(1000001) }));
  await assertFails(setDoc(board(db, 'u1'), { ...valid(), title: 't'.repeat(201) }));
});

test('owner: valid save, list and delete succeed', async () => {
  const db = testEnv.authenticatedContext('u1').firestore();
  await assertSucceeds(setDoc(board(db, 'u1'), valid()));
  await assertSucceeds(getDoc(board(db, 'u1')));
  await assertSucceeds(getDocs(collection(db, 'users', 'u1', 'boards')));
  await assertSucceeds(deleteDoc(board(db, 'u1')));
});

test('counter rules unchanged: anonymous small create still allowed, reads still denied', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  const c = doc(db, 'counters', 'global');
  await assertSucceeds(setDoc(c, { sessions: 1, boards: 0, devices: 1, returning: 0 }));
  await assertFails(getDoc(c));
});
