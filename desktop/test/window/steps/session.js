// One game at a time, with a stand-in emulator set as Dolphin: a script that runs 3 seconds, or on
// Windows, where an emulator has to be a program, RETROHUB_STAND_IN (test/release/StandIn), which
// does the same next to itself.
const standIn = process.platform === 'win32' && process.env.RETROHUB_STAND_IN;
const fs = require('fs');
const path = require('path');

const startsIn = (dataDir) => {
  const log = path.join(dataDir, 'emulator.log');
  return fs.existsSync(log) ? fs.readFileSync(log, 'utf8').split('\n').filter(Boolean).length : 0;
};

module.exports = {
  ...(standIn ? {} : { platforms: ['darwin', 'linux'] }),
  skipReason: 'the stand-in emulator is a shell script; the unit tests cover starting and ending a process here',
  settings(dataDir) {
    if (standIn) {
      const emulator = path.join(dataDir, 'emulator.exe');
      fs.copyFileSync(standIn, emulator);
      return { emulatorPaths: { dolphin: emulator } };
    }
    const emulator = path.join(dataDir, 'emulator.sh');
    fs.writeFileSync(emulator, `#!/bin/sh\necho "start $*" >> "${path.join(dataDir, 'emulator.log')}"\nsleep 3\n`, { mode: 0o755 });
    return { emulatorPaths: { dolphin: emulator } };
  },
  async run({ evaluate, key, check, log, shot, click, wait }, dataDir) {
    log('- play');
    await click('[data-key="sys:gamecube"]');
    await wait(400);
    await evaluate(`document.getElementById('content').focus()`);
    await key('Enter');
    // A stand-in program can take a few seconds to start on a fresh machine (.NET on Windows).
    for (let i = 0; i < 50 && startsIn(dataDir) === 0; i++) await wait(100);
    check(startsIn(dataDir) === 1, `Return starts the game once: ${startsIn(dataDir)} start(s)`);
    log('- play again while it runs');
    await key('Enter');
    await wait(600);
    const message = await evaluate(`!document.getElementById('modal').hidden && document.getElementById('modal-message').textContent`);
    check(message === 'Dolphin is still running Test Disc. Close it to start another game.', `RetroHub explains instead: ${message}`);
    check(startsIn(dataDir) === 1, `and starts no second copy: ${startsIn(dataDir)} start(s)`);
    await shot('still running');
    await key('Enter');
    log('- after the game closes');
    await wait(3500);
    await key('Enter');
    await wait(600);
    check(startsIn(dataDir) === 2, `the next Play starts it again: ${startsIn(dataDir)} start(s)`);
    check(await evaluate(`document.querySelector('[data-key="recent"] .badge')?.textContent.trim()`) === '1', 'and it is in Recently Played');
  },
};
