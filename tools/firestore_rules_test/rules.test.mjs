import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';

const projectId = 'starfilm-rules-test';
let testEnv;

before(async () => {
  const rulesPath = path.resolve(process.cwd(), '../../firestore.rules');
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(rulesPath, 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

test('owner can write and read own profile, library entry, and collection', async () => {
  const aliceDb = testEnv.authenticatedContext('alice').firestore();
  await assertSucceeds(setDoc(doc(aliceDb, 'users/alice'), { schemaVersion: 1 }));
  await assertSucceeds(setDoc(doc(aliceDb, 'users/alice/profiles/main'), { name: 'Головний' }));
  await assertSucceeds(
    setDoc(doc(aliceDb, 'users/alice/profiles/main/library/movie_550'), {
      mediaType: 'movie',
      tmdbId: 550,
      title: 'Fight Club',
      originalTitle: 'Fight Club',
      year: 1999,
      posterPath: '/pB8BM7pdSp6B6Ih7QZ4DrQ3PmJK.jpg',
      genreIds: [18],
      status: 'watched',
      userRating: 9,
      sentiment: 'liked',
    }),
  );
  await assertSucceeds(
    setDoc(doc(aliceDb, 'users/alice/profiles/main/collections/favs'), {
      title: 'Улюблені',
      mediaKeys: ['movie:550'],
    }),
  );
  const snap = await assertSucceeds(getDoc(doc(aliceDb, 'users/alice/profiles/main/library/movie_550')));
  assert.equal(snap.exists(), true);
});

test('different uid and unauthenticated user cannot read or write another uid data', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice/profiles/main/library/movie_550'), {
      mediaType: 'movie',
      tmdbId: 550,
      title: 'Fight Club',
      status: 'watched',
      sentiment: 'liked',
    });
  });

  const bobDb = testEnv.authenticatedContext('bob').firestore();
  const anonDb = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(bobDb, 'users/alice/profiles/main/library/movie_550')));
  await assertFails(setDoc(doc(bobDb, 'users/alice/profiles/main/library/movie_550'), { title: 'Hacked' }));
  await assertFails(getDoc(doc(anonDb, 'users/alice/profiles/main/library/movie_550')));
});

test('rules reject invalid profileId, invalid itemKey, oversized title, and invalid status', async () => {
  const aliceDb = testEnv.authenticatedContext('alice').firestore();

  await assertFails(setDoc(doc(aliceDb, 'users/alice/profiles/bad_id'), { name: 'Bad' }));
  await assertFails(setDoc(doc(aliceDb, 'users/alice/profiles/main'), { name: 'x'.repeat(25) }));
  await assertFails(
    setDoc(doc(aliceDb, 'users/alice/profiles/main/library/anime_123'), {
      mediaType: 'movie',
      title: 'Test',
    }),
  );
  await assertFails(
    setDoc(doc(aliceDb, 'users/alice/profiles/main/library/movie_123'), {
      mediaType: 'movie',
      title: 'A'.repeat(201),
      status: 'watched',
    }),
  );
  await assertFails(
    setDoc(doc(aliceDb, 'users/alice/profiles/main/library/movie_124'), {
      mediaType: 'movie',
      title: 'Valid',
      status: 'episode_progress',
    }),
  );
});
