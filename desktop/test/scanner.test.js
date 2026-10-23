// The Smart Game Scanner's rules (src/scanner.js). The Mac app's self-tests check the same cases.
const test = require('node:test');
const assert = require('node:assert');
const { updateIndex, summarize, needsFingerprint } = require('../src/scanner');

const game = (system, bootPath, displayTitle = bootPath) => ({ system, bootPath, displayTitle });
const library = (...games) => games.reduce((all, g) => ({ ...all, [g.system]: [...(all[g.system] || []), g] }), {});
/** A pretend file system: path → { size, mtime }. */
const stats = (files) => (file) => files[file] ?? null;

test('the first scan is the baseline: nothing is reported as new', () => {
  const index = updateIndex(null, library(game('nes', '/g/NES/Contra.nes')), { now: 100, stat: stats({ '/g/NES/Contra.nes': { size: 10, mtime: 1 } }) });
  assert.deepStrictEqual(summarize(index, 100), { added: [], renamed: [], missing: [], duplicates: [] });
});

test('a game added later is new until the changes are reviewed', () => {
  const files = { '/g/NES/Contra.nes': { size: 10, mtime: 1 }, '/g/NES/Zelda.nes': { size: 20, mtime: 1 } };
  const first = updateIndex(null, library(game('nes', '/g/NES/Contra.nes')), { now: 100, stat: stats(files) });
  const second = updateIndex(first, library(game('nes', '/g/NES/Contra.nes'), game('nes', '/g/NES/Zelda.nes')), { now: 200, stat: stats(files) });
  assert.deepStrictEqual(summarize(second, 100).added.map((g) => g.path), ['/g/NES/Zelda.nes']);
  assert.deepStrictEqual(summarize(second, 200).added, [], 'reviewed at 200: nothing new');
});

test('a missing game is kept and flagged, not dropped', () => {
  const first = updateIndex(null, library(game('nes', '/g/NES/Contra.nes', 'Contra')), { now: 100, stat: stats({ '/g/NES/Contra.nes': { size: 10, mtime: 1 } }) });
  const second = updateIndex(first, {}, { now: 200, stat: stats({}) });
  assert.strictEqual(second['/g/NES/Contra.nes'].missingSince, 200);
  assert.deepStrictEqual(summarize(second, 100).missing, [{ path: '/g/NES/Contra.nes', system: 'nes', title: 'Contra', since: 200 }]);
  const third = updateIndex(second, {}, { now: 300, stat: stats({}) });
  assert.strictEqual(third['/g/NES/Contra.nes'].missingSince, 200, 'still missing since it first went missing');
});

test('a renamed game is matched by system, size and type', () => {
  const before = { '/g/NES/Contra.nes': { size: 10, mtime: 1 } };
  const after = { '/g/NES/Contra (USA).nes': { size: 10, mtime: 5 } };
  const first = updateIndex(null, library(game('nes', '/g/NES/Contra.nes', 'Contra')), { now: 100, stat: stats(before) });
  const second = updateIndex(first, library(game('nes', '/g/NES/Contra (USA).nes', 'Contra')), { now: 200, stat: stats(after) });
  const summary = summarize(second, 100);
  assert.deepStrictEqual(summary.renamed.map(({ from, to }) => ({ from, to })), [{ from: '/g/NES/Contra.nes', to: '/g/NES/Contra (USA).nes' }]);
  assert.deepStrictEqual(summary.missing, [], 'a renamed game isn\'t also reported missing');
  assert.deepStrictEqual(summary.added, [], 'nor its new path as new');
});

test('fingerprints decide when both are known', () => {
  const first = { '/g/NES/A.nes': { system: 'nes', title: 'A', size: 10, mtime: 1, firstSeen: 0, fp: 'aaa', missingSince: 200 } };
  const differs = { ...first, '/g/NES/B.nes': { system: 'nes', title: 'B', size: 10, mtime: 5, firstSeen: 200, fp: 'bbb' } };
  assert.deepStrictEqual(summarize(differs).renamed, [], 'a different fingerprint is a different game');
  const same = { ...first, '/g/NES/B.nes': { ...differs['/g/NES/B.nes'], fp: 'aaa' } };
  assert.strictEqual(summarize(same).renamed.length, 1);
});

test('no rename when it could be either of two files, or another system, or a file that was already there', () => {
  const gone = { system: 'nes', title: 'A', size: 10, mtime: 1, firstSeen: 0, missingSince: 200 };
  const two = { '/g/NES/A.nes': gone, '/g/NES/B.nes': { ...gone, missingSince: undefined, firstSeen: 200 }, '/g/NES/C.nes': { ...gone, missingSince: undefined, firstSeen: 200 } };
  assert.deepStrictEqual(summarize(two).renamed, []);
  const other = { '/g/NES/A.nes': gone, '/g/SNES/A.sfc': { ...gone, system: 'snes', missingSince: undefined, firstSeen: 200 } };
  assert.deepStrictEqual(summarize(other).renamed, []);
  const old = { '/g/NES/A.nes': gone, '/g/NES/B.nes': { ...gone, missingSince: undefined, firstSeen: 0 } };
  assert.deepStrictEqual(summarize(old).renamed, []);
});

test('"not the same game" leaves it missing', () => {
  const index = {
    '/g/NES/A.nes': { system: 'nes', title: 'A', size: 10, mtime: 1, firstSeen: 0, missingSince: 200, notRenamed: true },
    '/g/NES/B.nes': { system: 'nes', title: 'B', size: 10, mtime: 5, firstSeen: 200 },
  };
  const summary = summarize(index, 100);
  assert.deepStrictEqual(summary.renamed, []);
  assert.deepStrictEqual(summary.missing.map((g) => g.path), ['/g/NES/A.nes']);
});

test('duplicates: the same fingerprint at two paths of one system', () => {
  const index = {
    '/g/NES/A.nes': { system: 'nes', title: 'A', size: 10, firstSeen: 0, fp: 'x' },
    '/g/NES/Copy of A.nes': { system: 'nes', title: 'Copy of A', size: 10, firstSeen: 0, fp: 'x' },
    '/g/NES/B.nes': { system: 'nes', title: 'B', size: 10, firstSeen: 0, fp: 'y' },
  };
  assert.deepStrictEqual(summarize(index).duplicates, [{ system: 'nes', title: 'A', paths: ['/g/NES/A.nes', '/g/NES/Copy of A.nes'] }]);
});

test('an unchanged file keeps its fingerprint; a changed one is fingerprinted again', () => {
  const first = { '/g/NES/A.nes': { system: 'nes', title: 'A', size: 10, mtime: 1, firstSeen: 0, fp: 'x' } };
  const same = updateIndex(first, library(game('nes', '/g/NES/A.nes', 'A')), { now: 200, stat: stats({ '/g/NES/A.nes': { size: 10, mtime: 1 } }) });
  assert.strictEqual(same['/g/NES/A.nes'].fp, 'x');
  assert.deepStrictEqual(needsFingerprint(same), []);
  const changed = updateIndex(first, library(game('nes', '/g/NES/A.nes', 'A')), { now: 200, stat: stats({ '/g/NES/A.nes': { size: 11, mtime: 2 } }) });
  assert.strictEqual(changed['/g/NES/A.nes'].fp, undefined);
  assert.deepStrictEqual(needsFingerprint(changed), ['/g/NES/A.nes']);
});
