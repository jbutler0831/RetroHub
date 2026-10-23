// What a screen reader is given (Chromium's accessibility tree): names for the sidebar rows, the
// buttons, the search field and the games, and an announcement when the picked game changes. It
// doesn't check that a screen reader actually speaks them: that needs a person.
module.exports = {
  async run({ evaluate, key, check, log, click, wait, send }) {
    await send('Accessibility.enable');
    const tree = async () => (await send('Accessibility.getFullAXTree')).nodes
      .filter((n) => !n.ignored).map((n) => ({ role: n.role?.value, name: n.name?.value || '' }));
    await click('[data-key="sys:nes"]');
    await wait(400);
    let nodes = await tree();
    const named = (role, name) => nodes.some((n) => n.role === role && n.name === name);
    log('- sidebar and toolbar');
    check(named('button', 'NES, 2 games') || named('button', 'NES, 2 games, setup needed'), 'the NES row reads as its name and game count');
    check(named('button', 'Setup'), 'the Setup row reads as Setup');
    for (const name of ['Couch mode (full screen, for controllers)', 'Look for new games']) check(named('button', name), `the toolbar button "${name}" has a name`);
    check(nodes.some((n) => n.role === 'searchbox' && n.name === 'Search games'), 'the search field has a name');
    log('- games');
    check(named('button', 'Play The Legend of Placeholder') && named('button', 'Play RetroHub Test Pattern'),
      'each Play button names its game');
    await evaluate(`document.getElementById('content').focus()`);
    await key('ArrowRight');
    await wait(300);
    const said = await evaluate(`document.getElementById('announcer')?.textContent`);
    check(said === 'RetroHub Test Pattern, 2 of 2', `moving to a game announces it: ${said}`);
    await key('f');
    await wait(300);
    check(await evaluate(`document.getElementById('announcer')?.textContent`) === 'RetroHub Test Pattern, 2 of 2, favorite',
      'and favoriting it says so');
    log('- couch mode');
    await click('#couch-button');
    await wait(1200);
    await key('ArrowLeft');
    await wait(300);
    check(await evaluate(`document.getElementById('announcer')?.textContent`) === 'The Legend of Placeholder, 1 of 2',
      'moving through the carousel announces each game');
    nodes = await tree();
    check(nodes.some((n) => n.role === 'button' && n.name === 'Exit couch mode (Esc)'), 'the exit button has a name');
  },
};
