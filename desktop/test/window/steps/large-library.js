// A large library: 3,000 NES games. Opening the list, searching, rescanning and couch mode must stay
// quick, and only covers near what's on screen are fetched (not 3,000 at once from the cover server).
// The time limits are generous, for slow machines; the times are printed.
const fs = require('fs');
const path = require('path');

const COUNT = 3000;
const timed = (evaluate, action) => evaluate(`(async () => {
  const start = performance.now();
  await ${action};
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  return Math.round(performance.now() - start);
})()`);

module.exports = {
  settings(dataDir) {
    const nes = path.join(dataDir, 'Games/NES');
    for (let i = 0; i < COUNT; i++) fs.writeFileSync(path.join(nes, `Large Game ${String(i).padStart(4, '0')} (USA).nes`), `game ${i}\n`);
    return null;
  },
  async run({ evaluate, key, check, log, shot, click, wait, send }) {
    const covers = () => evaluate(`coverCache.size`);
    log('- opening the list');
    const open = await timed(evaluate, `document.querySelector('[data-key="sys:nes"]').click()`);
    check(await evaluate(`document.querySelectorAll('.card').length`) === COUNT + 2, `all ${COUNT + 2} games listed`);
    check(open < 1500, `NES opens in ${open} ms`);
    await wait(1000);
    const asked = await covers();
    check(asked < 200, `covers fetched for the games in view, not all of them: ${asked} of ${COUNT + 2}`);
    await shot('large list');

    log('- scrolling');
    await evaluate(`document.getElementById('content').scrollTop = document.getElementById('content').scrollHeight / 2`);
    await wait(1000);
    const more = await covers();
    check(more > asked && more < asked + 300, `scrolling fetches the covers that come into view: ${more}`);

    log('- moving, searching, rescanning');
    await evaluate(`document.getElementById('content').focus()`);
    const move = await timed(evaluate, `command('right')`);
    check(move < 300, `moving to the next game takes ${move} ms`);
    const search = await timed(evaluate, `(() => { const s = document.getElementById('search'); s.value = 'Large Game 2999'; s.dispatchEvent(new Event('input')); })()`);
    check(await evaluate(`document.querySelectorAll('.card').length`) === 1 && search < 1000, `search narrows ${COUNT + 2} games to 1 in ${search} ms`);
    await evaluate(`(() => { const s = document.getElementById('search'); s.value = ''; s.dispatchEvent(new Event('input')); })()`);
    const rescan = await timed(evaluate, `(async () => applyState(await api.rescan(), true))()`);
    check(rescan < 3000, `a rescan of the library takes ${rescan} ms`);

    log('- couch mode');
    const before = await covers();
    const couch = await timed(evaluate, `document.getElementById('couch-button').click()`);
    await wait(1500);
    check(couch < 1500, `couch mode opens in ${couch} ms`);
    const couchCovers = (await covers()) - before;
    check(couchCovers < 50, `and fetches covers near the current game only: ${couchCovers} more`);
    const step = await timed(evaluate, `command('right')`);
    check(step < 300, `moving along the carousel takes ${step} ms`);
    await shot('large couch mode');
  },
};
