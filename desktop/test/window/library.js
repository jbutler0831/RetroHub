// The test library for the window checks: empty placeholder files, no real games. The Mac app's
// mac/scripts/make-test-library.swift makes a similar one (with a playable test ROM).
const fs = require('fs');
const path = require('path');

const FILES = [
  'NES/Legend of Placeholder, The (USA) [!].nes',
  'NES/RetroHub Test Pattern.nes',
  'NES/.hidden.nes',
  'NES/notes.txt',
  'SNES/UPPERCASE EXTENSION.SFC',
  'Genesis/Subfolder/Nested Game.md',
  'GameCube/Test Disc.iso',
  'PS1/Disc Placeholder (USA).cue',
];

function makeLibrary(root) {
  for (const file of FILES) {
    const full = path.join(root, file);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, '');
  }
}

module.exports = { makeLibrary };
