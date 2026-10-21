// Finds games in the library folder. Mirrors Sources/RetroHub/Library.swift.
const fs = require('fs');
const path = require('path');
const { SYSTEMS } = require('./systems');

/** Removes tags like "(USA)" or "[!]": "Contra (USA) [!]" → "Contra". */
function stripTags(title) {
  return title.replace(/\s*[([][^)\]]*[)\]]/g, '').trim();
}

/** Clean title for display; also turns "Legend of Zelda, The" back into "The Legend of Zelda". */
function displayTitle(title) {
  let name = stripTags(title);
  const article = name.match(/, (The|A|An)$/);
  if (article) name = `${article[1]} ${name.slice(0, -article[0].length)}`;
  return name || title;
}

function exists(file) {
  try { return fs.statSync(file) && true; } catch { return false; }
}

function listDir(dir) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true }).filter((e) => !e.name.startsWith('.'));
  } catch {
    return [];
  }
}

function makeGame(system, title, bootPath, localCovers) {
  return { id: bootPath, system: system.id, title, displayTitle: displayTitle(title), bootPath, localCovers };
}

function scanFiles(system, dir) {
  const games = [];
  for (const entry of listDir(dir)) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      games.push(...scanFiles(system, full));
    } else if (system.exts.includes(path.extname(entry.name).slice(1).toLowerCase())) {
      const base = full.slice(0, -path.extname(full).length);
      games.push(makeGame(system, path.basename(base), full, ['png', 'jpg', 'jpeg'].map((ext) => `${base}.${ext}`)));
    }
  }
  return games;
}

/** Disc dumps keep EBOOT.BIN under PS3_GAME/USRDIR; PSN games keep it under USRDIR. */
function scanPS3(system, dir) {
  const games = [];
  for (const entry of listDir(dir)) {
    if (!entry.isDirectory()) continue;
    const gameDir = path.join(dir, entry.name);
    const eboot = ['PS3_GAME/USRDIR/EBOOT.BIN', 'USRDIR/EBOOT.BIN'].map((p) => path.join(gameDir, p)).find(exists);
    if (!eboot) continue;
    const title = ['PS3_GAME/PARAM.SFO', 'PARAM.SFO'].map((p) => sfoTitle(path.join(gameDir, p))).find(Boolean) || entry.name;
    const covers = ['cover.png', 'cover.jpg', 'PS3_GAME/ICON0.PNG', 'ICON0.PNG'].map((p) => path.join(gameDir, p));
    games.push(makeGame(system, title, eboot, covers));
  }
  return games;
}

/** Reads the TITLE entry from a PS3 PARAM.SFO file (little-endian key/value table). */
function sfoTitle(file) {
  let data;
  try { data = fs.readFileSync(file); } catch { return null; }
  if (data.length < 20 || data.readUInt32BE(0) !== 0x00505346) return null;
  const keyTable = data.readUInt32LE(8), dataTable = data.readUInt32LE(12), count = data.readUInt32LE(16);
  for (let i = 0; i < count; i++) {
    const entry = 20 + i * 16;
    if (entry + 16 > data.length) return null;
    const keyStart = keyTable + data.readUInt16LE(entry);
    const keyEnd = keyStart < data.length ? data.indexOf(0, keyStart) : -1;
    if (keyEnd < 0) return null;
    if (data.toString('utf8', keyStart, keyEnd) !== 'TITLE') continue;
    const length = data.readUInt32LE(entry + 4), start = dataTable + data.readUInt32LE(entry + 12);
    if (start + length > data.length) return null;
    const title = data.toString('utf8', start, start + length).replace(/\n/g, ' ').replace(/[\x00-\x1f]/g, '').trim();
    return title || null;
  }
  return null;
}

/** Creates a folder per system under root and returns { systemId: [game] }. */
function scanLibrary(root) {
  const result = {};
  for (const system of SYSTEMS) {
    const dir = path.join(root, system.folder);
    try { fs.mkdirSync(dir, { recursive: true }); } catch { /* read-only drive: just scan */ }
    const games = system.id === 'ps3' ? scanPS3(system, dir) : scanFiles(system, dir);
    result[system.id] = games.sort((a, b) => a.title.localeCompare(b.title, undefined, { numeric: true, sensitivity: 'base' }));
  }
  return result;
}

module.exports = { scanLibrary, stripTags, sfoTitle, exists };
