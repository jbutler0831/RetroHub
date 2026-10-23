// Window checks: each file in steps/ starts RetroHub on a fresh, temporary data folder (settings,
// a small test library, no real games or settings), drives the real window the way a person would
// (key presses, clicks, a simulated controller) over Chromium's DevTools protocol on localhost, and
// checks the result. A picture of each step goes to dist/window-checks. They mirror the Mac app's
// UIChecks.swift.
//
//   npm run test:window                    every group
//   npm run test:window keyboard sidebar   some groups
//
// RETROHUB_APP=<program> checks an installed or packaged RetroHub instead of this source, such as a
// downloaded release (.github/workflows/release-check.yml does that on fresh machines).
//
// Exits non-zero if a check fails. Checks that need hardware or a person (a real controller, an
// emulator showing a game, a screen reader speaking) aren't here; see the pull request notes.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const electron = require('electron');
const { makeLibrary } = require('./library');

const desktop = path.join(__dirname, '../..');
const pictures = path.join(desktop, 'dist/window-checks');
const only = process.argv.slice(2);
const groups = fs.readdirSync(path.join(__dirname, 'steps')).filter((f) => f.endsWith('.js'))
  .map((f) => ({ name: f.slice(0, -3), ...require(`./steps/${f}`) }))
  .filter((g) => !only.length || only.includes(g.name));
/** The program and its first arguments: this source in Electron, or an installed RetroHub. */
const appCommand = process.env.RETROHUB_APP ? [process.env.RETROHUB_APP] : [electron, desktop];
// GitHub's Linux machines don't allow Chromium's sandbox; the app itself is unchanged.
const sandbox = process.platform === 'linux' && process.env.CI ? ['--no-sandbox'] : [];

/** Starts RetroHub with a debugging port on localhost, and these arguments; what it prints goes to logFile. */
function startApp(port, logFile, ...args) {
  const log = fs.openSync(logFile, 'w');
  return spawn(appCommand[0], [...appCommand.slice(1), ...args, `--remote-debugging-port=${port}`, ...sandbox], { stdio: ['ignore', log, log] });
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

/** Connects to the RetroHub page and returns the helpers the steps use. */
async function connect(port) {
  let target;
  for (let i = 0; i < 120 && !target; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      target = list.find((t) => t.type === 'page' && t.url.endsWith('index.html'));
    } catch { /* not up yet */ }
    if (!target) await wait(250);
  }
  if (!target) throw new Error('RetroHub\'s window never opened');
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  let nextId = 1;
  const pending = new Map();
  ws.onmessage = (event) => {
    const message = JSON.parse(event.data);
    const call = pending.get(message.id);
    if (!call) return;
    pending.delete(message.id);
    message.error ? call.reject(new Error(message.error.message)) : call.resolve(message.result);
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });
  return { ws, send };
}

function helpers(send, group, results) {
  const evaluate = async (expression) => {
    const result = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || expression);
    return result.result.value;
  };
  const codes = { ArrowUp: 38, ArrowDown: 40, ArrowLeft: 37, ArrowRight: 39, Enter: 13, Escape: 27, Tab: 9, ',': 188, '[': 219, ']': 221 };
  /** A key press as the window receives it; modifiers: 2 Ctrl, 4 Meta, 8 Shift. */
  const key = async (name, modifiers = 0) => {
    const text = name.length === 1 && !(modifiers & 6) ? name : undefined;
    const code = codes[name] || name.toUpperCase().charCodeAt(0);
    await send('Input.dispatchKeyEvent', { type: 'keyDown', key: name, windowsVirtualKeyCode: code, modifiers, text });
    await send('Input.dispatchKeyEvent', { type: 'keyUp', key: name, windowsVirtualKeyCode: code, modifiers });
    await wait(250);
  };
  const check = (passed, label) => {
    results.checks++;
    if (!passed) results.failures++;
    console.log(`  ${passed ? 'ok' : 'FAIL'} ${label}`);
  };
  const log = (text) => console.log(text);
  let pictureNumber = 0;
  const shot = async (name) => {
    const { data } = await send('Page.captureScreenshot', { format: 'png' });
    const dir = path.join(pictures, group);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, `${String(++pictureNumber).padStart(2, '0')} ${name}.png`), Buffer.from(data, 'base64'));
  };
  const click = (selector) => evaluate(`document.querySelector(${JSON.stringify(selector)}).click()`);
  const title = () => evaluate(`document.getElementById('toolbar-title').textContent`);
  /** Where keyboard focus is: 'sidebar', 'games', or the focused element's id. */
  const focus = () => evaluate(`document.getElementById('nav').contains(document.activeElement) ? 'sidebar'
    : document.getElementById('content').contains(document.activeElement) ? 'games' : document.activeElement.id || document.activeElement.tagName`);
  /** File names of the favorites, sorted. */
  const favorites = () => evaluate(`S.favorites.map((p) => p.split(/[\\\\/]/).pop()).sort()`);
  /** Whether an emulator is installed here, which decides where RetroHub opens. */
  const anyEmulator = () => evaluate(`S.emulators.some((e) => e.installed)`);
  return { evaluate, key, check, log, shot, click, title, focus, favorites, anyEmulator, wait, send };
}

/** Opens RetroHub on dataDir, runs one phase of a group's steps, and quits it. */
async function runPhase(phase, group, port, dataDir, results) {
  const logFile = path.join(dataDir, `app-${port}.log`);
  const app = startApp(port, logFile, `--data-dir=${dataDir}`);
  let ws;
  try {
    const connection = await connect(port);
    ws = connection.ws;
    await connection.send('Runtime.enable');
    // document.hasFocus() is true even when another window is in front, so controller input counts.
    await connection.send('Emulation.setFocusEmulationEnabled', { enabled: true });
    await wait(1500);
    await phase(helpers(connection.send, group.name, results), dataDir);
  } catch (error) {
    results.checks++;
    results.failures++;
    console.log(`  FAIL ${error.message}`);
    console.log(`  what RetroHub printed (exit code ${app.exitCode}):\n${fs.readFileSync(logFile, 'utf8').slice(-3000)}`);
  } finally {
    ws?.close();
    app.kill();
    await new Promise((resolve) => (app.exitCode !== null ? resolve() : app.once('exit', resolve)));
  }
}

async function runGroup(group, port, results) {
  if (group.platforms && !group.platforms.includes(process.platform)) {
    console.log(`${group.name}: skipped on ${process.platform} (${group.skipReason})`);
    return;
  }
  console.log(`${group.name}:`);
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'retrohub-check-'));
  makeLibrary(path.join(dataDir, 'Games'));
  const settings = group.settings ? group.settings(dataDir) : null;
  if (settings) {
    fs.mkdirSync(path.join(dataDir, 'desktop'), { recursive: true });
    fs.writeFileSync(path.join(dataDir, 'desktop/settings.json'), JSON.stringify(settings));
  }
  // A group can check something again after quitting and reopening RetroHub on the same data.
  const phases = [group.run, ...(group.afterRelaunch ? [group.afterRelaunch] : [])];
  try {
    for (const phase of phases) await runPhase(phase, group, port, dataDir, results);
  } finally {
    fs.rmSync(dataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  }
}

module.exports = { connect, helpers, startApp, wait };
if (require.main !== module) return;

(async () => {
  fs.rmSync(pictures, { recursive: true, force: true });
  const results = { checks: 0, failures: 0 };
  let port = 9333;
  for (const group of groups) await runGroup(group, port++, results);
  console.log(results.failures ? `FAIL: ${results.failures} of ${results.checks} checks failed` : `PASS: ${results.checks} checks`);
  console.log(`Pictures of each step: ${path.relative(process.cwd(), pictures) || pictures}`);
  process.exit(results.failures ? 1 : 0);
})();
