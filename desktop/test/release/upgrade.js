// Upgrade check, in two halves with an install in between, on a machine with no RetroHub settings:
//
//   node test/release/upgrade.js before <older RetroHub program>   # sets a favorite and a screen filter
//   (install or unpack the new version)
//   node test/release/upgrade.js after <newer RetroHub program>    # they must still be there
//
// Both use RetroHub's normal settings folder and ~/Games, as a real upgrade does, so only run it on
// a machine where that's fine, such as a fresh GitHub runner. Exits non-zero if a check fails.
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { connect, wait } = require('../window/run');
const { makeLibrary } = require('../window/library');

const [phase, program] = process.argv.slice(2);
const games = path.join(os.homedir(), 'Games');
const favorite = 'Legend of Placeholder, The (USA) [!].nes';
let failures = 0;
const check = (passed, label) => {
  if (!passed) failures++;
  console.log(`  ${passed ? 'ok' : 'FAIL'} ${label}`);
};

(async () => {
  if (phase === 'before') makeLibrary(games);
  const sandbox = process.platform === 'linux' && process.env.CI ? ['--no-sandbox'] : [];
  const app = spawn(program, ['--remote-debugging-port=9400', ...sandbox], { stdio: 'ignore' });
  let ws;
  try {
    const connection = await connect(9400);
    ws = connection.ws;
    const evaluate = async (expression) => {
      const result = await connection.send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
      if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || expression);
      return result.result.value;
    };
    await wait(2500);
    const state = () => evaluate(`window.retrohub.state()`);
    const names = (s) => s.favorites.map((f) => f.split(/[\\/]/).pop());
    if (phase === 'before') {
      console.log(`${path.basename(program)}: the older version`);
      let s = await state();
      check(s.libraryRoot === games, `uses ${games}`);
      const id = s.games.nes.find((g) => g.bootPath.endsWith(favorite))?.id;
      await evaluate(`window.retrohub.toggleFavorite(${JSON.stringify(id)})`);
      await evaluate(`window.retrohub.setGraphics({ filter: 'crt' })`);
      s = await state();
      check(JSON.stringify(names(s)) === JSON.stringify([favorite]), `a favorite: ${names(s)}`);
      check(s.graphics.filter === 'crt', 'and the CRT screen filter');
    } else {
      console.log(`${path.basename(program)}: the newer version, on the same settings`);
      const s = await state();
      check(s.libraryRoot === games, `still uses ${s.libraryRoot}`);
      check(JSON.stringify(names(s)) === JSON.stringify([favorite]), `the favorite is kept: ${names(s)}`);
      check(s.graphics.filter === 'crt', `the screen filter is kept: ${s.graphics.filter}`);
      check(s.graphics.fullscreen === true, 'new settings take their defaults (Full screen on)');
      check((s.games.nes || []).length === 2, `the library is found: ${(s.games.nes || []).length} NES games`);
      const news = s.libraryCheck?.news;
      check(news && !news.added && !news.renamed && !news.missing, `an upgrade isn't news: the first scan is a quiet baseline (${JSON.stringify(news)})`);
    }
  } catch (error) {
    check(false, error.message);
  } finally {
    ws?.close();
    app.kill();
    await new Promise((resolve) => (app.exitCode !== null ? resolve() : app.once('exit', resolve)));
  }
  console.log(failures ? `FAIL: ${failures} checks failed` : 'PASS');
  process.exit(failures ? 1 : 0);
})();
