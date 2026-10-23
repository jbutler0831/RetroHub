// Setup › Appearance: Follow System, Light, Dark; readable status colors; couch mode stays dark;
// the choice is kept after quitting.
const dark = (evaluate) => evaluate(`matchMedia('(prefers-color-scheme: dark)').matches`);
const color = (evaluate, selector) => evaluate(`getComputedStyle(document.querySelector(${JSON.stringify(selector)})).color`);

module.exports = {
  async run({ evaluate, check, log, shot, click, wait }) {
    const choose = async (value) => { await click(`[data-appearance="${value}"]`); await wait(600); };
    log('- Setup');
    await click('[data-key="setup"]');
    await wait(400);
    check(await evaluate(`document.querySelector('[data-appearance].active')?.dataset.appearance`) === 'system', 'Follow System is the default');
    await choose('light');
    check(await dark(evaluate) === false, 'Light: the window draws light');
    check(await evaluate(`document.querySelector('[data-appearance].active').dataset.appearance`) === 'light', 'and Light shows as chosen');
    await shot('setup light');
    log('- status colors in Light');
    await click('[data-key="sys:genesis"]');
    await wait(500);
    // Genesis plays only with RetroArch cores that the checks' machines don't have.
    const pill = await evaluate(`document.querySelector('.pill')?.className`);
    if (pill?.includes('needs-setup')) {
      check(await color(evaluate, '.pill.needs-setup') === 'rgb(127, 65, 0)', 'the Setup needed pill uses the readable orange (5:1 or more)');
    } else {
      log('  (Genesis is ready here: no Setup needed pill to measure)');
    }
    const badge = await evaluate(`!!document.querySelector('.nav-item:not(.active) .badge.setup-needed')`);
    if (badge) check(await color(evaluate, '.nav-item:not(.active) .badge.setup-needed') === 'rgb(127, 65, 0)', 'and so does an unselected sidebar badge');
    await shot('genesis light');
    log('- couch mode in Light');
    await click('#couch-button');
    await wait(1500);
    check(await evaluate(`getComputedStyle(document.getElementById('couch')).backgroundColor`) === 'rgb(0, 0, 0)', 'couch mode keeps its dark look');
    await click('[data-exit]');
    await wait(1500);
    log('- Dark');
    await click('[data-key="setup"]');
    await wait(400);
    await choose('dark');
    check(await dark(evaluate) === true, 'Dark: the window draws dark');
    await shot('setup dark');
  },
  async afterRelaunch({ evaluate, check, log }) {
    log('- after quitting and reopening');
    check(await dark(evaluate) === true, 'Dark is still applied');
  },
};
