// Box art: a local image next to the game first, then libretro-thumbnails, cached on disk.
// Mirrors mac/Sources/RetroHub/CoverArt.swift.
const fs = require('fs');
const path = require('path');
const { SYSTEMS } = require('./systems');
const { stripTags, exists } = require('./library');

const SERVER = 'https://thumbnails.libretro.com';
const REGIONS = ['USA', 'World', 'USA, Europe', 'Europe', 'Japan'];

/** The thumbnail server replaces these characters with underscores. */
const sanitize = (name) => name.replace(/[&*/:`<>?\\|"]/g, '_');

/**
 * libretro-thumbnails uses No-Intro names such as "Super Mario Bros. (World)" and
 * "Legend of Zelda, The (USA)", so also try the bare title with common regions added.
 */
function candidateNames(title) {
  const base = stripTags(title);
  const bases = [base];
  if (base.startsWith('The ')) bases.push(`${base.slice(4)}, The`);
  return [...new Set([title, ...bases.flatMap((b) => REGIONS.map((r) => `${b} (${r})`))])];
}

/** Returns a local file path for the game's cover, or null. */
async function coverPath(game, cacheRoot) {
  const local = game.localCovers.find(exists);
  if (local) return local;

  const system = SYSTEMS.find((s) => s.id === game.system);
  const cached = path.join(cacheRoot, system.id, `${sanitize(game.title)}.png`);
  const missMarker = `${cached}.none`;
  if (exists(cached)) return cached;
  if (exists(missMarker)) return null;
  fs.mkdirSync(path.dirname(cached), { recursive: true });

  for (const name of candidateNames(game.title)) {
    const url = `${SERVER}/${encodeURIComponent(system.libretro)}/Named_Boxarts/${encodeURIComponent(sanitize(name))}.png`;
    let response;
    try {
      response = await fetch(url);
    } catch {
      return null; // Offline: don't remember the miss; try again later.
    }
    if (response.ok) {
      fs.writeFileSync(cached, Buffer.from(await response.arrayBuffer()));
      return cached;
    }
  }
  fs.writeFileSync(missMarker, '');
  return null;
}

module.exports = { coverPath };
