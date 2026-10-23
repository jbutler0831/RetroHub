// The Smart Game Scanner and Library Check: the first scan is quiet; after files are renamed,
// removed, added and copied on disk, the banner and Library Check say so, and nothing changes until
// a button is pressed. The choices are kept after quitting.
const fs = require('fs');
const path = require('path');

const CTRL = 2;
const NES = (dir) => path.join(dir, 'Games/NES');

module.exports = {
  async run({ evaluate, key, check, log, shot, click, title, favorites, wait }, dataDir) {
    const banner = () => evaluate(`document.querySelector('.library-banner')?.textContent.replace(/\\s+/g, ' ').trim() || null`);
    log('- first scan');
    await click('[data-key="sys:nes"]');
    await wait(300);
    check(await banner() === null, 'the first scan is the baseline: no banner');
    await evaluate(`document.getElementById('content').focus()`);
    await key('f');
    check(JSON.stringify(await favorites()) === JSON.stringify(['Legend of Placeholder, The (USA) [!].nes']), 'a favorite to follow through a rename');
    await wait(1000); // fingerprints of the baseline, in the background

    log('- files change on disk');
    fs.renameSync(path.join(NES(dataDir), 'Legend of Placeholder, The (USA) [!].nes'), path.join(NES(dataDir), 'Legend of Placeholder, The (USA) (Rev 1).nes'));
    fs.rmSync(path.join(dataDir, 'Games/SNES/UPPERCASE EXTENSION.SFC'));
    fs.writeFileSync(path.join(NES(dataDir), 'Brand New Game.nes'), 'RetroHub placeholder: a new game\n');
    fs.copyFileSync(path.join(dataDir, 'Games/GameCube/Test Disc.iso'), path.join(dataDir, 'Games/GameCube/Test Disc (copy).iso'));
    await key('r', CTRL);
    await wait(1500);
    check(await banner() === 'Library changed: 2 new · 1 moved or renamed · 1 missing Review', `the banner says what changed: ${await banner()}`);
    check(JSON.stringify(await favorites()) === JSON.stringify(['Legend of Placeholder, The (USA) [!].nes']), 'nothing has changed yet: the favorite is still on the old name');
    await shot('banner');

    log('- Library Check');
    await click('.library-banner [data-show="check"]');
    await wait(400);
    check(await title() === 'Library Check', 'Review opens Library Check');
    const rows = (heading) => evaluate(`[...document.querySelectorAll('.check section')].find((s) => s.querySelector('h3').textContent.startsWith(${JSON.stringify(heading)}))
      .querySelectorAll('.check-row').length`);
    const text = () => evaluate(`document.querySelector('.check').textContent.replace(/\\s+/g, ' ')`);
    check(await rows('Moved or renamed') === 1 && (await text()).includes('Legend of Placeholder, The (USA) [!].nes → Legend of Placeholder, The (USA) (Rev 1).nes · favorite'),
      'the rename is listed, with the favorite it carries');
    check(await rows('Missing') === 1 && (await text()).includes('UPPERCASE EXTENSION.SFC'), 'the missing SNES game is listed');
    check(await rows('New') === 2, 'the two new files are listed');
    const copies = await evaluate(`[...document.querySelectorAll('[data-check="showFile"]')].map((b) => b.dataset.path.split(/[\\\\/]/).pop()).sort()`);
    check(await rows('Duplicates') === 1 && JSON.stringify(copies) === JSON.stringify(['Test Disc (copy).iso', 'Test Disc.iso']),
      `and the copy as a duplicate: ${copies.join(', ')}`);
    await shot('library check');

    log('- confirming');
    await click('[data-check="applyRename"]');
    await wait(400);
    check(JSON.stringify(await favorites()) === JSON.stringify(['Legend of Placeholder, The (USA) (Rev 1).nes']), `Same game moves the favorite to the new name: ${await favorites()}`);
    check(await rows('Moved or renamed') === 0, 'and the rename is done');
    await click('[data-check="removeMissing"]');
    await wait(400);
    check(await rows('Missing') === 0, 'Remove forgets the missing game');
    await click('[data-check="markReviewed"]');
    await wait(400);
    check(await title() === 'NES' && await banner() === null, 'Done goes back to NES, and the banner is gone');
  },
  async afterRelaunch({ evaluate, check, log, click, favorites, wait }) {
    log('- after quitting and reopening');
    await click('[data-key="sys:nes"]');
    await wait(300);
    check(await evaluate(`!document.querySelector('.library-banner')`), 'no banner: the changes were reviewed');
    check(JSON.stringify(await favorites()) === JSON.stringify(['Legend of Placeholder, The (USA) (Rev 1).nes']), 'the favorite is still on the new name');
    check(await evaluate(`S.libraryCheck.duplicates.length`) === 1, 'the duplicate is still listed in Library Check (it is still on disk)');
  },
};
