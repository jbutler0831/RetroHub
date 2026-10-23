// Play time: sessions RetroHub sees end are added (under 10 seconds they aren't); it shows under
// the game, in couch mode, as a total on Recently Played, and moves with a renamed game. The
// emulator is a stand-in script set as Dolphin, running as long as a file says.
// Not on Windows, where an emulator has to be a .exe program.
const fs = require('fs');
const path = require('path');

const legend = (dir, name = 'Legend of Placeholder, The (USA) [!].nes') => path.join(dir, 'Games/NES', name);
const disc = (dir) => path.join(dir, 'Games/GameCube/Test Disc.iso');

module.exports = {
  platforms: ['darwin', 'linux'],
  skipReason: 'the stand-in emulator is a shell script; the unit tests cover the rules here',
  settings(dataDir) {
    const emulator = path.join(dataDir, 'emulator.sh');
    fs.writeFileSync(emulator, `#!/bin/sh\nsleep "$(cat "${path.join(dataDir, 'seconds')}")"\n`, { mode: 0o755 });
    // Earlier play time for one NES game, to show.
    return { emulatorPaths: { dolphin: emulator }, playtime: { [legend(dataDir)]: { seconds: 3 * 3600 + 12 * 60, sessions: 4 } } };
  },
  async run({ evaluate, key, check, log, shot, click, wait }, dataDir) {
    const sub = (name) => evaluate(`[...document.querySelectorAll('.card')].find((c) => c.dataset.id.endsWith(${JSON.stringify(name)}))?.querySelector('.card-sub')?.textContent`);
    const played = (file) => evaluate(`S.playtime[${JSON.stringify(file)}] || null`);
    const play = async (seconds) => {
      fs.writeFileSync(path.join(dataDir, 'seconds'), String(seconds));
      await click('[data-key="sys:gamecube"]');
      await wait(300);
      await evaluate(`document.getElementById('content').focus()`);
      await key('Enter');
      await wait(seconds * 1000 + 1500);
    };

    log('- showing play time');
    await click('[data-key="sys:nes"]');
    await wait(300);
    check(await sub('[!].nes') === '3 h 12 min', `under the game: ${await sub('[!].nes')}`);
    check(await sub('Test Pattern.nes') === undefined, 'nothing under a game never played');
    await click('[data-key="recent"]');
    await wait(300);
    check((await evaluate(`document.querySelector('.page-meta').textContent`)).includes('3 h 12 min played in all'), 'Recently Played shows the total');

    log('- sessions');
    await play(3);
    check(await played(disc(dataDir)) === null, 'a 3-second session (an emulator that failed to start) does not count');
    await play(11);
    const after = await played(disc(dataDir));
    check(after?.sessions === 1 && after.seconds >= 11 && after.seconds <= 13, `an 11-second session counts once: ${JSON.stringify(after)}`);

    log('- couch mode');
    await click('[data-key="sys:nes"]');
    await wait(300);
    await evaluate(`selectedGame['sys:nes'] = visibleGames().find((g) => g.id.endsWith('[!].nes')).id`);
    await click('#couch-button');
    await wait(1500);
    check((await evaluate(`document.getElementById('couch-details').textContent`)).includes('Played 3 h 12 min'), 'couch mode shows it beside the game');
    await shot('couch mode');
    await click('[data-exit]');
    await wait(1200);

    log('- a renamed game takes its play time along');
    fs.renameSync(legend(dataDir), legend(dataDir, 'Legend of Placeholder, The (USA) (Rev 1).nes'));
    await key('r', 2);
    await wait(1500);
    await click('.library-banner [data-show="check"]');
    await wait(400);
    check((await evaluate(`document.querySelector('.check').textContent`)).includes('3 h 12 min of play'), 'Library Check says what the rename carries');
    await click('[data-check="applyRename"]');
    await wait(400);
    check((await played(legend(dataDir, 'Legend of Placeholder, The (USA) (Rev 1).nes')))?.seconds === 3 * 3600 + 12 * 60
      && await played(legend(dataDir)) === null, 'Same game moves it to the new name');
  },
};
