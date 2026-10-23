// Keyboard: the sidebar, into the games and back, the picked game per list, Ctrl shortcuts,
// search, and couch mode sharing the picked game. Mirrors the Mac app's window checks.
const CTRL = 2;
const NES = ['Legend of Placeholder, The (USA) [!].nes', 'RetroHub Test Pattern.nes'];

module.exports = {
  async run({ evaluate, key, check, log, shot, click, title, focus, favorites, anyEmulator, wait, send }) {
    const highlight = () => evaluate(`getComputedStyle(document.querySelector('.nav-item.active')).backgroundColor`);
    const accent = 'rgb(10, 132, 255)';

    log('- launch');
    const opens = (await anyEmulator()) ? 'NES' : 'Setup';
    check(await title() === opens, `opens on ${opens} (${opens === 'NES' ? 'an emulator is installed' : 'no emulators'}): ${await title()}`);
    check(await focus() === 'games', 'the content has keyboard focus');
    check(await highlight() !== accent, 'so the sidebar highlight is grey');

    log('- sidebar');
    await click('[data-key="setup"]');
    await wait(300);
    check(await focus() === 'sidebar' && await title() === 'Setup', 'a click on Setup keeps focus in the sidebar');
    check(await highlight() === accent, 'and the highlight is blue');
    await key('ArrowDown');
    check(await title() === 'NES' && await focus() === 'sidebar', `↓ selects NES and focus stays there: ${await title()}, ${await focus()}`);
    await key('ArrowDown');
    check(await title() === 'Super Nintendo', `a second ↓ selects Super Nintendo: ${await title()}`);
    await key('ArrowUp');
    check(await title() === 'NES', `↑ goes back to NES: ${await title()}`);
    await shot('sidebar focused');

    log('- into the games and back');
    await key('Enter');
    check(await focus() === 'games' && await title() === 'NES', 'Return moves focus to the games, with NES still selected');
    await key('f');
    check(JSON.stringify(await favorites()) === JSON.stringify([NES[0]]), `F adds the selected game: ${await favorites()}`);
    await key('ArrowRight');
    await key('f');
    check(JSON.stringify(await favorites()) === JSON.stringify(NES), `→ then F adds the second game: ${await favorites()}`);
    await shot('games focused');
    await key('Escape');
    check(await focus() === 'sidebar', 'Esc moves focus back to the sidebar');
    await key('ArrowDown');
    await key('ArrowUp');
    await key('Enter');
    await key('f');
    check(JSON.stringify(await favorites()) === JSON.stringify([NES[0]]), `F acts on the game picked before leaving NES: ${await favorites()}`);

    log('- shortcuts');
    await key(',', CTRL);
    check(await title() === 'Setup', `Ctrl+, shows Setup: ${await title()}`);
    await key('[', CTRL);
    check(await title() === 'Arcade', `Ctrl+[ from Setup wraps to the last list, Arcade: ${await title()}`);
    // Within a pixel: rows can be a fraction of a pixel tall (Linux and Windows fonts), and scrolling is whole pixels.
    const row = await evaluate(`(() => { const r = document.querySelector('.nav-item.active').getBoundingClientRect(), n = document.getElementById('nav').getBoundingClientRect();
      return { top: r.top - n.top, bottom: n.bottom - r.bottom }; })()`);
    check(row.top >= -1 && row.bottom >= -1, `and the sidebar scrolls Arcade into view (${row.top.toFixed(1)}px below the top, ${row.bottom.toFixed(1)}px above the bottom)`);
    await key(']', CTRL);
    check(await title() === 'Favorites', `Ctrl+] from Arcade wraps to Favorites: ${await title()}`);
    await key('r', CTRL);
    await wait(400);
    check(await title() === 'Favorites', 'Ctrl+R rescans and stays on the list');

    log('- search');
    await key(']', CTRL);
    await key(']', CTRL);
    check(await title() === 'NES', `Ctrl+] steps on to NES: ${await title()}`);
    await key('f', CTRL);
    check(await focus() === 'search', 'Ctrl+F puts the cursor in the search field');
    await send('Input.insertText', { text: 'pattern' });
    await wait(300);
    await key('Enter');
    check(await focus() === 'games', 'Return in the search field moves to the results');
    await key('f');
    check((await favorites()).includes(NES[1]), `F adds the one result: ${await favorites()}`);
    await evaluate(`(() => { const s = document.getElementById('search'); s.value = ''; s.dispatchEvent(new Event('input')); })()`);

    log('- couch mode shares the picked game');
    await evaluate(`document.getElementById('content').focus()`);
    await key('ArrowLeft');
    await key('ArrowRight');
    const picked = await evaluate(`selectedGame['sys:nes'].split(/[\\\\/]/).pop()`);
    await click('#couch-button');
    await wait(1500);
    const current = () => evaluate(`document.querySelector('.carousel .cover.current')?.dataset.cover.split(/[\\\\/]/).pop()`);
    check(await current() === picked, `couch mode opens on the game picked in the browser: ${await current()}`);
    await key('ArrowLeft');
    const couchPick = await current();
    await key('Escape');
    await wait(1500);
    check(await evaluate(`document.getElementById('couch').hidden`), 'Esc leaves couch mode');
    check(await evaluate(`document.querySelector('.card.selected')?.dataset.id.split(/[\\\\/]/).pop()`) === couchPick,
      `the browser keeps the game picked in couch mode: ${couchPick}`);
    check(await focus() === 'games', 'with focus on the games');
  },
};
