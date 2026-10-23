// Play time (src/renderer/playtime.js). The Mac app's self-tests check the same cases.
const test = require('node:test');
const assert = require('node:assert');
const { addSession, moveGame, totalSeconds, format } = require('../src/renderer/playtime');

test('a session adds its time and counts once', () => {
  const once = addSession({}, '/g/a.nes', 125.4);
  assert.deepStrictEqual(once, { '/g/a.nes': { seconds: 125, sessions: 1 } });
  assert.deepStrictEqual(addSession(once, '/g/a.nes', 60), { '/g/a.nes': { seconds: 185, sessions: 2 } });
});

test('a session under 10 seconds (an emulator that failed to start) does not count', () => {
  assert.deepStrictEqual(addSession({}, '/g/a.nes', 9.9), {});
  assert.deepStrictEqual(addSession({}, '/g/a.nes', NaN), {});
});

test('a renamed game takes its play time along, added to any at the new path', () => {
  const before = { '/g/a.nes': { seconds: 100, sessions: 2 }, '/g/b.nes': { seconds: 50, sessions: 1 } };
  assert.deepStrictEqual(moveGame(before, '/g/a.nes', '/g/b.nes'), { '/g/b.nes': { seconds: 150, sessions: 3 } });
  assert.deepStrictEqual(moveGame(before, '/g/none.nes', '/g/b.nes'), before, 'nothing to move');
});

test('the total and the wording', () => {
  assert.strictEqual(totalSeconds({ a: { seconds: 100, sessions: 1 }, b: { seconds: 20, sessions: 1 } }), 120);
  assert.strictEqual(format(59), 'under a minute');
  assert.strictEqual(format(60), '1 min');
  assert.strictEqual(format(59 * 60), '59 min');
  assert.strictEqual(format(3600), '1 h');
  assert.strictEqual(format(3 * 3600 + 12 * 60 + 30), '3 h 12 min');
  assert.strictEqual(format(40 * 3600 + 25 * 60), '40 h', 'minutes dropped from 10 hours up');
});
