// The controller, SIMULATED: a stand-in gamepad replaces navigator.getGamepads(), so this checks
// RetroHub's mapping and its one-action-per-press rule, not a real controller or its drivers.
const BUTTON = { A: 0, B: 1, Y: 3, LB: 4, RB: 5, START: 9, RIGHT: 15 };

module.exports = {
  async run({ evaluate, check, log, shot, click, title, focus, favorites, wait }) {
    await evaluate(`window.__pad = { index: 0, id: 'Simulated Controller (STANDARD GAMEPAD)', connected: true, mapping: 'standard',
      buttons: Array.from({ length: 17 }, () => ({ pressed: false, value: 0 })), axes: [0, 0, 0, 0] };
      navigator.getGamepads = () => [window.__pad];`);
    // Held for several frames, as a real press is, then released.
    const press = async (button, hold = 150) => {
      await evaluate(`window.__pad.buttons[${button}].pressed = true`);
      await wait(hold);
      await evaluate(`window.__pad.buttons[${button}].pressed = false`);
      await wait(250);
    };
    const picked = () => evaluate(`selectedGame[selection]?.split(/[\\\\/]/).pop()`);
    await wait(300);
    log('- connected (simulated)');
    check(await evaluate(`document.getElementById('controller-status').textContent.trim()`) === 'Simulated Controller', 'the sidebar shows its name');
    await click('[data-key="sys:nes"]');
    await wait(300);
    check(await focus() === 'sidebar', 'a click leaves focus in the sidebar');
    log('- D-pad and stick');
    const first = await picked();
    await press(BUTTON.RIGHT, 400);
    check(await focus() === 'games', 'controller input moves focus to the games');
    check(await picked() !== first && await evaluate(`visibleGames().findIndex((g) => g.id === selectedGame[selection])`) === 1,
      'a held → moves one game, once');
    await evaluate(`window.__pad.axes[0] = -1`);
    await wait(400);
    await evaluate(`window.__pad.axes[0] = 0`);
    await wait(250);
    check(await picked() === first, 'the stick held left moves back one game, once');
    log('- buttons');
    const before = (await favorites()).length;
    await press(BUTTON.Y);
    check((await favorites()).length === before + 1, 'Y toggles one favorite, once');
    await press(BUTTON.RB);
    check(await title() === 'Super Nintendo', `RB goes to the next system: ${await title()}`);
    await press(BUTTON.LB);
    check(await title() === 'NES', `LB comes back: ${await title()}`);
    await press(BUTTON.START);
    await wait(1200);
    check(!(await evaluate(`document.getElementById('couch').hidden`)), 'Start opens couch mode');
    await shot('couch mode');
    await press(BUTTON.B);
    await wait(1200);
    check(await evaluate(`document.getElementById('couch').hidden`), 'B leaves it');
    log('- A on a system that needs setup');
    await click('[data-key="sys:ps1"]');
    await wait(300);
    const ready = await evaluate(`S.systems.find((s) => s.id === 'ps1').readiness.ready`);
    if (ready) {
      log('  (PlayStation can play here: not pressing A, which would start a real emulator)');
    } else {
      await press(BUTTON.A);
      await wait(400);
      check(!(await evaluate(`document.getElementById('modal').hidden`)), 'A explains what setup is needed');
      await press(BUTTON.B);
      check(await evaluate(`document.getElementById('modal').hidden`), 'and B closes the message');
    }
  },
};
