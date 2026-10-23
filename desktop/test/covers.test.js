// Mirrors the "cover art" checks in mac/Sources/RetroHub/SelfTests.swift.
const test = require('node:test');
const assert = require('node:assert');
const { fetchResult } = require('../src/covers');

test('200 is art and 404 is remembered as no art', () => {
  assert.strictEqual(fetchResult(200), 'found');
  assert.strictEqual(fetchResult(404), 'missing');
});

test('server trouble is retried later, not cached as no art', () => {
  for (const status of [429, 500, 502, 503]) assert.strictEqual(fetchResult(status), 'retry', `${status}`);
});
