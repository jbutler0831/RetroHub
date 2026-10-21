// RetroHub window: sidebar, game grid, Setup page, couch mode and controller input.
const api = window.retrohub;
const I = window.ICONS;

let S = null;                 // State from the main process.
let lastStateJSON = '';
let selection = 'sys:nes';    // 'favorites' | 'recent' | 'setup' | 'sys:<id>'
let search = '';
const selectedGame = {};      // selection → game id
let couch = false;
let couchIndex = 0;
let padName = null;
const coverCache = new Map(); // game id → Promise<file URL | null>

const $ = (id) => document.getElementById(id);
const nav = $('nav');
const content = $('content');
const couchEl = $('couch');
const modal = $('modal');

const esc = (value) => String(value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const orList = new Intl.ListFormat('en', { type: 'disjunction' });
const relative = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });

// ---- Data helpers -------------------------------------------------------------

const systemById = (id) => S.systems.find((s) => s.id === id);
const systemFor = (key) => (key.startsWith('sys:') ? systemById(key.slice(4)) : null);
/** The game lists, in the order the controller cycles through them. */
const listKeys = () => ['favorites', 'recent', ...S.systems.map((s) => `sys:${s.id}`)];
/** Couch mode only shows lists with games, so the controller never lands on a blank screen. */
const couchKeys = () => listKeys().filter((key) => gamesFor(key).length);
const allGames = () => S.systems.flatMap((s) => S.games[s.id] || []);

function gamesFor(key) {
  const system = systemFor(key);
  if (system) return S.games[system.id] || [];
  if (key === 'favorites') {
    const favorites = new Set(S.favorites);
    return allGames().filter((g) => favorites.has(g.id));
  }
  if (key === 'recent') {
    return allGames()
      .filter((g) => S.lastPlayed[g.id])
      .sort((a, b) => S.lastPlayed[b.id] - S.lastPlayed[a.id])
      .slice(0, S.recentLimit);
  }
  return [];
}

function visibleGames() {
  const query = search.trim().toLowerCase();
  const games = gamesFor(selection);
  return query ? games.filter((g) => g.displayTitle.toLowerCase().includes(query)) : games;
}

function itemInfo(key) {
  const system = systemFor(key);
  if (system) return { title: system.name, color: system.color, label: system.label };
  return {
    favorites: { title: 'Favorites', color: '#ffb800', icon: I.star },
    recent: { title: 'Recently Played', color: '#ff9500', icon: I.clock },
    setup: { title: 'Setup', color: '#8e8e93', icon: I.wrench },
  }[key];
}

function fileHint(system) {
  if (system.id === 'ps1') return '.cue (with its .bin files), .chd or .pbp files';
  if (system.id === 'xbox') return 'XISO-format .iso files';
  if (system.id === 'ps3') return 'game folders (each containing PS3_GAME or USRDIR)';
  return `${orList.format([...system.exts].sort().map((e) => `.${e}`))} files`;
}

function timeAgo(ms) {
  const seconds = (ms - Date.now()) / 1000;
  for (const [unit, size] of [['year', 31536000], ['month', 2592000], ['week', 604800], ['day', 86400], ['hour', 3600], ['minute', 60]]) {
    if (Math.abs(seconds) >= size) return relative.format(Math.round(seconds / size), unit);
  }
  return 'just now';
}

function cover(id) {
  if (!coverCache.has(id)) coverCache.set(id, api.cover(id).catch(() => null));
  return coverCache.get(id);
}

const emulatorName = (id) => S.emulators.find((e) => e.id === id)?.name || id;

// ---- Building blocks -------------------------------------------------------------

function tile(key, size = '') {
  const info = itemInfo(key);
  const iconSize = { huge: 36, big: 28 }[size] || 14;
  const inner = info.label ? esc(info.label) : info.icon({ size: iconSize });
  return `<span class="tile ${size}" style="--c:${info.color}">${inner}</span>`;
}

function placeholder(game, system) {
  return `<div class="placeholder"><span class="label">${esc(system.label)}</span><span class="ph-title">${esc(game.displayTitle)}</span></div>`;
}

function statusHtml(system) {
  const r = system.readiness;
  const pill = `<span class="pill ${r.ready ? 'ready' : 'needs-setup'}" title="${esc(r.detail || '')}">` +
    `${r.ready ? I.check({ size: 13 }) : I.alert({ size: 13 })} ${esc(r.summary)}</span>`;
  const get = r.missing ? ` <button class="button primary small" data-download="${r.missing}">Get ${esc(emulatorName(r.missing))}</button>` : '';
  return pill + get;
}

function cardHtml(game, showSystem) {
  const system = systemById(game.system);
  const favorite = S.favorites.includes(game.id);
  return `<div class="card${game.id === selectedGame[selection] ? ' selected' : ''}" data-id="${esc(game.id)}">
    <div class="cover" style="--c:${system.color}" data-cover="${esc(game.id)}">
      ${placeholder(game, system)}<img alt="" hidden>
      ${favorite ? `<span class="fav-badge">${I.star({ size: 12 })}</span>` : ''}
      <button class="play-button" data-play title="Play">${I.play({ size: 22 })}</button>
    </div>
    <div class="card-title">${esc(game.displayTitle)}</div>
    ${showSystem ? `<div class="card-sub">${esc(system.name)}</div>` : ''}
  </div>`;
}

/** Swaps each placeholder for its cover art once it loads. */
function loadCovers(root) {
  for (const el of root.querySelectorAll('[data-cover]')) {
    cover(el.dataset.cover).then((url) => {
      const img = el.querySelector('img');
      if (!url || !img) return;
      img.onload = () => {
        img.hidden = false;
        el.querySelector('.placeholder')?.remove();
      };
      img.src = url;
    });
  }
}

// ---- Rendering -------------------------------------------------------------------

function render() {
  renderSidebar();
  renderController();
  if (couch) {
    couchEl.hidden = false;
    renderCouch();
  } else {
    couchEl.hidden = true;
    renderContent();
  }
}

function renderSidebar() {
  const row = (key, count) => `<button class="nav-item${key === selection ? ' active' : ''}" data-key="${key}">
      ${tile(key)}<span class="name">${esc(itemInfo(key).title)}</span>${count ? `<span class="badge">${count}</span>` : ''}
    </button>`;
  nav.innerHTML =
    `<div class="nav-section">${row('favorites', gamesFor('favorites').length)}${row('recent', gamesFor('recent').length)}${row('setup')}</div>` +
    S.makers.map((maker) => `<div class="nav-section"><div class="nav-heading">${maker}</div>
      ${S.systems.filter((s) => s.maker === maker).map((s) => row(`sys:${s.id}`, (S.games[s.id] || []).length)).join('')}
    </div>`).join('');
}

function renderController() {
  const el = $('controller-status');
  el.classList.toggle('connected', !!padName);
  el.innerHTML = `${I.gamepad({ size: 18 })}<span>${esc(padName || 'No controller')}</span>`;
  el.title = padName ? 'A: play · Y: favorite · LB/RB: switch · Start: couch mode' : 'Connect a controller and press any button';
}

function renderContent() {
  const info = itemInfo(selection);
  $('toolbar-title').textContent = info.title;
  const scroll = content.scrollTop;
  if (selection === 'setup') {
    renderSetup();
  } else {
    const games = visibleGames();
    if (games.length && !games.some((g) => g.id === selectedGame[selection])) selectedGame[selection] = games[0].id;
    const system = systemFor(selection);
    const total = gamesFor(selection).length;
    content.innerHTML = `<div class="page-backdrop" style="--c:${info.color}"></div>
      <div class="page-header">${tile(selection, 'big')}
        <div><h2>${esc(info.title)}</h2>
          <div class="page-meta"><span>${total === 1 ? '1 game' : `${total} games`}</span>${system ? statusHtml(system) : ''}</div>
        </div>
      </div>
      ${games.length ? `<div class="grid" id="grid">${games.map((g) => cardHtml(g, !system)).join('')}</div>` : emptyHtml(system)}`;
    loadCovers(content);
  }
  content.scrollTop = scroll;
}

function emptyHtml(system) {
  if (search.trim()) {
    return `<div class="empty"><h3>No results for “${esc(search.trim())}”</h3><p>Check the spelling or try a different search.</p></div>`;
  }
  if (selection === 'favorites') {
    return `<div class="empty">${tile('favorites', 'huge')}<h3>No favorites yet</h3>
      <p>Right-click a game and choose Add to Favorites, press F, or press Y on your controller.</p></div>`;
  }
  if (selection === 'recent') {
    return `<div class="empty">${tile('recent', 'huge')}<h3>Nothing played yet</h3>
      <p>The games you play will show up here so you can jump right back in.</p></div>`;
  }
  const r = system.readiness;
  return `<div class="empty">${tile(selection, 'huge')}<h3>Let's add some ${esc(system.name)} games</h3>
    <div class="panel steps">
      <div class="step">
        <span class="step-number${r.ready ? ' done' : ''}">${r.ready ? I.check({ size: 14 }) : '1'}</span>
        <div class="step-text"><strong>${esc(r.ready ? r.summary : 'Get an emulator')}</strong>${r.detail ? `<span>${esc(r.detail)}</span>` : ''}</div>
        ${r.missing ? `<button class="button primary" data-download="${r.missing}">Get ${esc(emulatorName(r.missing))}</button>` : ''}
      </div>
      <div class="step">
        <span class="step-number">2</span>
        <div class="step-text"><strong>Add your games</strong><span>Put ${esc(fileHint(system))} in the ${esc(system.folder)} folder.</span></div>
        <button class="button" data-open-folder="${system.id}">Open Folder</button>
      </div>
    </div></div>`;
}

function renderSetup() {
  const installed = S.emulators.filter((e) => e.installed).length;
  const emulatorCard = (e) => `<div class="panel emulator-card">
      <span class="letter" style="--c:${e.color}">${esc(e.name[0].toUpperCase())}</span>
      <div class="info">
        <strong>${esc(e.name)}</strong>
        <span class="covers">${esc(e.covers)}</span>
        ${e.location ? `<span class="location" title="${esc(e.location)}">${esc(e.location)}</span>` : ''}
        <div class="actions">
          ${e.installed ? `<span class="installed">${I.check({ size: 14 })} Installed</span>`
                        : `<button class="button primary small" data-download="${e.id}">Download</button>`}
          <button class="button small" data-locate="${e.id}">${e.installed ? 'Change…' : 'Locate…'}</button>
        </div>
      </div>
    </div>`;
  const notes = S.systems.filter((s) => s.note);
  const g = S.graphics;
  const segmented = (key, options) => `<div class="segmented">${options.map(([value, label]) =>
    `<button class="${g[key] === value ? 'active' : ''}" data-graphics="${key}" data-value="${esc(JSON.stringify(value))}">${esc(label)}</button>`).join('')}</div>`;
  const graphicsRow = (title, detail, control) => `<div class="graphics-row">
      <div class="grow"><strong>${esc(title)}</strong><span>${esc(detail)}</span></div>${control}</div>`;
  content.innerHTML = `<div class="page-backdrop" style="--c:#8e8e93"></div>
    <div class="page-header">${tile('setup', 'big')}
      <div><h2>Setup</h2><div class="page-meta">${installed
        ? `${installed} of ${S.emulators.length} emulators installed`
        : 'Welcome! Install an emulator below to get started.'}</div></div>
    </div>
    <div class="setup">
      <section>
        <h3>Emulators</h3>
        <p class="subtitle">RetroHub opens your games in these free emulators. Install the ones for the systems you want to play.
          If one isn't found automatically, click Locate… and pick its program file.</p>
        <div class="emulator-grid">${S.emulators.map(emulatorCard).join('')}</div>
      </section>
      <section>
        <h3>Games Folder</h3>
        <p class="subtitle">Each system has its own folder inside this one.</p>
        <div class="panel row-panel">
          <span class="tile" style="--c:#007aff;width:36px;height:36px;border-radius:9px">${I.folder({ size: 18 })}</span>
          <div class="grow mono" title="${esc(S.libraryRoot)}">${esc(S.libraryRoot)}</div>
          <button class="button" data-open-folder="">Open</button>
          <button class="button" data-choose-root>Change…</button>
        </div>
      </section>
      <section>
        <h3>Graphics</h3>
        <p class="subtitle">Applied when RetroHub starts a game in RetroArch. RetroArch's own settings stay as they are.</p>
        <div class="panel graphics-panel">
          ${graphicsRow('Screen filter', 'NES, SNES, Game Boy, GBA and Genesis. CRT adds scanlines and a curved screen; Smooth HD rounds off pixel edges.',
                        segmented('filter', [['off', 'Off'], ['crt', 'CRT'], ['smooth', 'Smooth HD']]))}
          ${S.shadersMissing ? `<div class="graphics-warning">Download RetroArch's shaders first: Main Menu › Online Updater › Update Slang Shaders.</div>` : ''}
          ${graphicsRow('3D resolution', 'N64 and PlayStation. Higher looks sharper but needs a faster computer.',
                        segmented('scale', [[1, 'Native'], [2, '2×'], [3, '3×'], [4, '4×']]))}
          ${graphicsRow('Widescreen hack', 'N64 and PlayStation. Shows more of the 3D world in 16:9; some games glitch at the edges.',
                        segmented('widescreen', [[false, 'Off'], [true, 'On']]))}
        </div>
      </section>
      <section>
        <h3>Controller</h3>
        <p class="subtitle">PS5 DualSense and Xbox controllers work over Bluetooth or USB.</p>
        <div class="panel row-panel">
          <span class="tile" style="--c:${padName ? '#28a745' : '#8e8e93'};width:36px;height:36px;border-radius:9px">${I.gamepad({ size: 20 })}</span>
          <div class="grow">
            <strong>${esc(padName || 'No controller connected')}</strong>
            <div class="card-sub" style="text-align:left">${padName
              ? 'A to play · Y to favorite · LB/RB to switch · Start for couch mode'
              : 'Connect one, then press any button so RetroHub can see it.'}</div>
          </div>
        </div>
      </section>
      <section>
        <h3>BIOS &amp; Firmware</h3>
        <p class="subtitle">Some systems need files from your own console. These can't be included.</p>
        <div class="panel bios-list">${notes.map((s) => `<div class="bios-row">${tile(`sys:${s.id}`)}<strong>${esc(s.name)}</strong><span>${esc(s.note)}</span></div>`).join('')}</div>
      </section>
    </div>`;
}

// ---- Couch mode --------------------------------------------------------------------

/** Cover width and gap in pixels, from the CSS (they shrink on small screens). */
function coverMetrics() {
  const style = getComputedStyle(document.documentElement);
  return { width: parseFloat(style.getPropertyValue('--cover-w')), gap: parseFloat(style.getPropertyValue('--cover-gap')) };
}

function renderCouch() {
  const keys = couchKeys();
  const games = gamesFor(selection);
  couchIndex = Math.min(couchIndex, Math.max(0, games.length - 1));
  const hint = (button, label) => `<span><span class="button-badge">${button}</span><span class="label">${label}</span></span>`;
  couchEl.innerHTML = `<div class="couch-backdrop" id="couch-backdrop"></div>
    <button class="couch-close icon-button" data-exit title="Exit couch mode (Esc)">${I.close({ size: 22 })}</button>
    <div class="couch-tabs">
      <span class="button-badge">LB</span>
      <div class="tabs">${keys.map((k) => `<span class="tab${k === selection ? ' active' : ''}" data-tab="${k}">${esc(itemInfo(k).title)}</span>`).join('')}</div>
      <span class="button-badge">RB</span>
    </div>
    <div class="couch-stage">${games.length
      ? `<div class="carousel" id="carousel">${games.map((g, i) => `<div class="cover" style="--c:${systemById(g.system).color}" data-cover="${esc(g.id)}" data-index="${i}">${placeholder(g, systemById(g.system))}<img alt="" hidden></div>`).join('')}</div>
         <div class="couch-details" id="couch-details"></div>`
      : `<div class="couch-empty">${I.gamepad({ size: 64 })}<h2>No games yet</h2><p>Add games to ${esc(S.libraryRoot)} to see them here.</p></div>`}
    </div>
    <div class="couch-hints">${hint('A', 'Play')}${hint('Y', 'Favorite')}${hint('LB RB', 'Switch')}${hint('B', 'Exit')}</div>`;
  loadCovers(couchEl);
  updateCouch();
}

/** Moves the carousel and refreshes the title and backdrop without rebuilding it. */
function updateCouch() {
  const games = gamesFor(selection);
  const game = games[couchIndex];
  const carousel = $('carousel');
  if (!game || !carousel) return;
  carousel.querySelectorAll('.cover').forEach((el, i) => el.classList.toggle('current', i === couchIndex));
  const { width, gap } = coverMetrics();
  carousel.style.transform = `translateX(${window.innerWidth / 2 - (couchIndex * (width + gap) + width / 2)}px)`;

  const system = systemById(game.system);
  const last = S.lastPlayed[game.id];
  $('couch-details').innerHTML = `<h2>${esc(game.displayTitle)}${S.favorites.includes(game.id) ? `<span class="star">${I.star({ size: 26 })}</span>` : ''}</h2>
    <p>${esc(system.name)}${last ? ` · Last played ${timeAgo(last)}` : ''}</p>`;
  cover(game.id).then((url) => {
    if (gamesFor(selection)[couchIndex]?.id !== game.id) return;
    $('couch-backdrop').style.backgroundImage = url ? `url(${JSON.stringify(url)})` : 'none';
  });
}

function setCouch(on) {
  couch = on;
  const keys = couchKeys();
  if (on && keys.length && !keys.includes(selection)) selection = keys[0];
  couchIndex = 0;
  api.setFullScreen(on || S.consoleMode);
  render();
}

// ---- Actions -----------------------------------------------------------------------

function showModal(message) {
  $('modal-message').textContent = message;
  $('modal').querySelector('.modal-icon').innerHTML = I.alert({ size: 34 });
  modal.hidden = false;
  $('modal-ok').focus();
}

function hideModal() {
  modal.hidden = true;
  content.focus();
}

async function play(id) {
  if (!couch) select(id);
  const result = await api.play(id);
  if (result.error) showModal(result.error);
  else if (couch && selection === 'recent') couchIndex = 0; // The game just moved to the front.
}

function select(id, scroll = false) {
  selectedGame[selection] = id;
  content.querySelectorAll('.card.selected').forEach((c) => c.classList.remove('selected'));
  const card = content.querySelector(`.card[data-id="${CSS.escape(id)}"]`);
  card?.classList.add('selected');
  if (scroll) card?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
}

function gridColumns() {
  const cards = [...content.querySelectorAll('.card')];
  return Math.max(1, cards.filter((c) => c.offsetTop === cards[0]?.offsetTop).length);
}

function move(dx, dy) {
  const games = visibleGames();
  if (!games.length) return;
  const current = games.findIndex((g) => g.id === selectedGame[selection]);
  if (current < 0) return select(games[0].id, true);
  const next = Math.min(Math.max(current + dx + dy * gridColumns(), 0), games.length - 1);
  select(games[next].id, true);
}

function cycle(step) {
  const keys = couch ? couchKeys() : listKeys();
  if (!keys.length) return;
  let index = keys.indexOf(selection);
  if (index < 0) index = step > 0 ? -1 : 0;
  selection = keys[(index + step + keys.length) % keys.length];
  couchIndex = 0;
  render();
}

/** Handles a controller or keyboard command. */
function command(cmd) {
  if (!modal.hidden) {
    if (cmd === 'play' || cmd === 'back') hideModal();
    return;
  }
  if (couch) {
    const games = gamesFor(selection);
    switch (cmd) {
      case 'left': case 'right':
        couchIndex = Math.min(Math.max(couchIndex + (cmd === 'left' ? -1 : 1), 0), Math.max(0, games.length - 1));
        return updateCouch();
      case 'up': case 'prev': return cycle(-1);
      case 'down': case 'next': return cycle(1);
      case 'play': return games[couchIndex] && play(games[couchIndex].id);
      case 'favorite': return games[couchIndex] && api.toggleFavorite(games[couchIndex].id);
      case 'back': case 'couch': return setCouch(false);
    }
    return;
  }
  const id = selectedGame[selection];
  switch (cmd) {
    case 'left': return move(-1, 0);
    case 'right': return move(1, 0);
    case 'up': return move(0, -1);
    case 'down': return move(0, 1);
    case 'play': return id && visibleGames().some((g) => g.id === id) && play(id);
    case 'favorite': return id && api.toggleFavorite(id);
    case 'prev': return cycle(-1);
    case 'next': return cycle(1);
    case 'couch': return setCouch(true);
  }
}

// ---- Events ------------------------------------------------------------------------

nav.addEventListener('click', (event) => {
  const item = event.target.closest('[data-key]');
  if (!item) return;
  selection = item.dataset.key;
  render();
  content.focus();
});

async function handleButtons(event) {
  const target = event.target.closest('[data-download], [data-open-folder], [data-choose-root], [data-locate], [data-play], [data-exit], [data-tab], [data-graphics]');
  if (!target) return false;
  const d = target.dataset;
  if ('download' in d) api.openDownload(d.download);
  else if ('openFolder' in d) api.openFolder(d.openFolder);
  else if ('chooseRoot' in d) applyState(await api.chooseRoot());
  else if ('locate' in d) applyState(await api.locateEmulator(d.locate));
  else if ('play' in d) play(target.closest('[data-id]').dataset.id);
  else if ('exit' in d) setCouch(false);
  else if ('tab' in d) { selection = d.tab; couchIndex = 0; render(); }
  else if ('graphics' in d) applyState(await api.setGraphics({ [d.graphics]: JSON.parse(d.value) }));
  return true;
}

content.addEventListener('click', async (event) => {
  if (await handleButtons(event)) return;
  const card = event.target.closest('.card');
  if (card) select(card.dataset.id);
});
content.addEventListener('dblclick', (event) => {
  const card = event.target.closest('.card');
  if (card && !event.target.closest('button')) play(card.dataset.id);
});
content.addEventListener('contextmenu', (event) => {
  const card = event.target.closest('.card');
  if (!card) return;
  event.preventDefault();
  select(card.dataset.id);
  api.gameMenu(card.dataset.id);
});

couchEl.addEventListener('click', async (event) => {
  if (await handleButtons(event)) return;
  const el = event.target.closest('[data-index]');
  if (el) {
    couchIndex = Number(el.dataset.index);
    updateCouch();
  }
});
couchEl.addEventListener('dblclick', (event) => {
  const el = event.target.closest('[data-index]');
  if (el) command('play');
});

$('couch-button').innerHTML = I.tv({ size: 18 });
$('rescan-button').innerHTML = I.refresh({ size: 17 });
document.querySelector('.search-icon').innerHTML = I.search({ size: 14 });
$('couch-button').addEventListener('click', () => setCouch(true));
$('rescan-button').addEventListener('click', async () => applyState(await api.rescan(), true));
$('modal-ok').addEventListener('click', hideModal);
$('search').addEventListener('input', (event) => {
  search = event.target.value;
  renderContent();
});

const KEYS = { ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down', Enter: 'play', f: 'favorite', F: 'favorite', Escape: 'back' };
window.addEventListener('keydown', (event) => {
  if (event.target.id === 'search') {
    if (event.key === 'Escape') event.target.blur();
    if (event.key === 'Enter' || event.key === 'ArrowDown') content.focus();
    return;
  }
  const cmd = KEYS[event.key];
  if (!cmd) return;
  event.preventDefault();
  command(cmd);
});
window.addEventListener('resize', () => couch && updateCouch());

// ---- Controller ----------------------------------------------------------------------

// Standard gamepad mapping: 0 A/✕, 1 B/○, 3 Y/△, 4 LB, 5 RB, 9 Start/Options, 12–15 D-pad.
const BUTTONS = { 0: 'play', 1: 'back', 3: 'favorite', 4: 'prev', 5: 'next', 9: 'couch', 12: 'up', 13: 'down', 14: 'left', 15: 'right' };
const held = new Map();

function cleanPadName(id) {
  return id.replace(/\s*\(.*\)\s*$/, '').replace(/^[0-9a-f]{4}-[0-9a-f]{4}-/i, '').trim() || 'Controller';
}

/** Fires a command when an input goes from released to pressed, but only while RetroHub is in front. */
function edge(key, down, cmd) {
  const wasDown = held.get(key);
  held.set(key, down);
  if (down && !wasDown && document.hasFocus()) command(cmd);
}

function pollGamepads() {
  const pads = [...navigator.getGamepads()].filter(Boolean);
  const name = pads[0] ? cleanPadName(pads[0].id) : null;
  if (name !== padName) {
    padName = name;
    renderController();
    if (selection === 'setup' && !couch) renderContent();
  }
  for (const pad of pads) {
    for (const [index, cmd] of Object.entries(BUTTONS)) edge(`${pad.index}:${index}`, !!pad.buttons[index]?.pressed, cmd);
    const [x = 0, y = 0] = pad.axes;
    edge(`${pad.index}:x-`, x < -0.6, 'left');
    edge(`${pad.index}:x+`, x > 0.6, 'right');
    edge(`${pad.index}:y-`, y < -0.6, 'up');
    edge(`${pad.index}:y+`, y > 0.6, 'down');
  }
  requestAnimationFrame(pollGamepads);
}

// ---- Startup -------------------------------------------------------------------------

function applyState(state, force = false) {
  const json = JSON.stringify(state);
  if (!force && json === lastStateJSON) return;
  lastStateJSON = json;
  S = state;
  render();
}

api.onState((state) => applyState(state));
api.onError(showModal);

api.state().then((state) => {
  // New users land on Setup until they have an emulator.
  selection = state.emulators.some((e) => e.installed) ? 'sys:nes' : 'setup';
  applyState(state);
  if (state.consoleMode) setCouch(true);
  content.focus();
  requestAnimationFrame(pollGamepads);
});
