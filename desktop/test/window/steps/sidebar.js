// Sidebar status: counts, setup warnings, tooltips, labels; "x of y games" while searching.
module.exports = {
  async run({ evaluate, check, log, shot }) {
    log('- badges');
    const rows = await evaluate(`[...document.querySelectorAll('.nav-item')].map((b) => {
      const system = b.dataset.key.startsWith('sys:') ? S.systems.find((s) => 'sys:' + s.id === b.dataset.key) : null;
      return { key: b.dataset.key, badge: b.querySelector('.badge')?.textContent.trim() || null,
               warn: !!b.querySelector('.badge.setup-needed svg'), title: b.title, aria: b.getAttribute('aria-label'),
               ready: system ? system.readiness.ready : null };
    })`);
    const row = (key) => rows.find((r) => r.key === key);
    check(row('sys:nes').badge === '2', `NES counts its 2 games (hidden files and other types left out): ${row('sys:nes').badge}`);
    const withGames = rows.filter((r) => r.ready !== null && r.badge);
    check(withGames.every((r) => r.warn === !r.ready),
      `a system with games shows the warning exactly when nothing installed plays them: ${withGames.map((r) => `${r.key}${r.warn ? '⚠' : ''}`).join(' ')}`);
    const gamecube = row('sys:gamecube');
    check(gamecube.ready ? gamecube.title.startsWith('GameCube: 1 game. Plays with') : gamecube.title.startsWith('GameCube: 1 game. Setup needed. Install Dolphin'),
      `the tooltip says what plays them or what's needed: ${gamecube.title}`);
    check(gamecube.aria === (gamecube.ready ? 'GameCube, 1 game' : 'GameCube, 1 game, setup needed'), `and the label reads: ${gamecube.aria}`);
    check(row('setup').badge === null && row('setup').aria === 'Setup', 'Setup has no count');
    check(row('sys:n64').badge === null && row('sys:n64').title === 'Nintendo 64: no games yet', 'empty systems show no count');
    await shot('sidebar');
    log('- search');
    await evaluate(`document.querySelector('[data-key="sys:nes"]').click()`);
    await evaluate(`(() => { const s = document.getElementById('search'); s.value = 'pattern'; s.dispatchEvent(new Event('input')); })()`);
    const meta = await evaluate(`document.querySelector('.page-meta span').textContent`);
    check(meta === '1 of 2 games', `while searching the header says: ${meta}`);
  },
};
