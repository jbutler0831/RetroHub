// Mirrors the "game process" checks in mac/Sources/RetroHub/SelfTests.swift: RetroHub learns when
// the emulator's process ends, with its exit status, also when it fails straight away.
const test = require('node:test');
const assert = require('node:assert');
const { startProcess } = require('../src/emulators');

const exitOf = (child) => new Promise((resolve) => child.once('exit', (code) => resolve(code)));

test('a running emulator is reported, then its end with its exit status', async () => {
  const child = await startProcess(process.execPath, ['-e', 'setTimeout(() => process.exit(0), 300)']);
  assert.strictEqual(child.exitCode, null, 'running after it starts');
  assert.strictEqual(await exitOf(child), 0);
});

test('an emulator that fails straight away still reports its end', async () => {
  const child = await startProcess(process.execPath, ['-e', 'process.exit(3)']);
  assert.strictEqual(child.exitCode === null ? await exitOf(child) : child.exitCode, 3);
});

test('a missing emulator is an error, not a silent failure', async () => {
  await assert.rejects(startProcess('/nonexistent/emulator', []));
});
