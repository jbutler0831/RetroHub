// The test library for the window checks: placeholder files, no real games. Each holds its own
// name, so no two look like copies of each other to the scanner. The Mac app's
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
    fs.writeFileSync(full, `RetroHub placeholder: ${file}\n`);
  }
}

module.exports = { makeLibrary };
