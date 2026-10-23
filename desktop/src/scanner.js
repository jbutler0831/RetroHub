// Smart Game Scanner: compares each scan with the games RetroHub saw before, so it can say what's
// new, what was moved or renamed, what's missing and what's there twice. Nothing is changed until
// the user approves it in Library Check: a missing game keeps its favorite and play history, and a
// renamed one only takes them over once confirmed.
//
// The index is { [path]: entry }, entry = { system, title, size, mtime, firstSeen, fp?, missingSince?,
// notRenamed? }. fp is a fingerprint of the file's first 64 KB, worked out after the scan, in the
// background, only for files that don't have one yet.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const FINGERPRINT_BYTES = 64 * 1024;

/** Size and modification time, or null for a folder (PS Vita games), which isn't matched on moves. */
function statFile(file) {
  try {
    const info = fs.statSync(file);
    return info.isFile() ? { size: info.size, mtime: info.mtimeMs } : null;
  } catch {
    return null;
  }
}

/** SHA-256 of the file's size and first 64 KB, shortened. */
async function fingerprint(file) {
  const handle = await fs.promises.open(file, 'r');
  try {
    const buffer = Buffer.alloc(FINGERPRINT_BYTES);
    const { bytesRead } = await handle.read(buffer, 0, FINGERPRINT_BYTES, 0);
    const { size } = await handle.stat();
    return crypto.createHash('sha256').update(String(size)).update(buffer.subarray(0, bytesRead)).digest('hex').slice(0, 24);
  } finally {
    await handle.close();
  }
}

/**
 * The index after a scan. `previous` null means RetroHub has never scanned: everything found is the
 * baseline, not news. Games that disappeared stay in the index, marked missing since `now`.
 */
function updateIndex(previous, games, { now = Date.now(), stat = statFile } = {}) {
  const index = {};
  for (const list of Object.values(games)) {
    for (const game of list) {
      const old = previous?.[game.bootPath];
      const info = stat(game.bootPath);
      const unchanged = old && info && old.size === info.size && old.mtime === info.mtime;
      index[game.bootPath] = {
        system: game.system,
        title: game.displayTitle,
        size: info?.size ?? null,
        mtime: info?.mtime ?? null,
        firstSeen: old?.firstSeen ?? (previous ? now : 0),
        ...(unchanged && old.fp ? { fp: old.fp } : {}),
      };
    }
  }
  for (const [file, old] of Object.entries(previous || {})) {
    if (!index[file]) index[file] = { ...old, missingSince: old.missingSince ?? now };
  }
  return index;
}

/** Present files that still need a fingerprint. */
function needsFingerprint(index) {
  return Object.entries(index).filter(([, e]) => !e.missingSince && !e.fp && e.size !== null).map(([file]) => file);
}

const sameKind = (a, b, fileA, fileB) => a.system === b.system && a.size !== null && a.size === b.size
  && path.extname(fileA).toLowerCase() === path.extname(fileB).toLowerCase();

/**
 * What Library Check shows. `reviewedAt` is when the user last reviewed the changes: games first
 * seen since then are new.
 *   added: present games first seen since the last review (a renamed game's new path isn't counted)
 *   renamed: { from, to } for a missing game whose file turned up at another path
 *   missing: missing games that weren't renamed
 *   duplicates: { system, paths } for the same file at two or more paths
 */
function summarize(index, reviewedAt = 0) {
  const entries = Object.entries(index);
  const present = entries.filter(([, e]) => !e.missingSince);
  const renamed = [];
  const claimed = new Set();
  for (const [from, old] of entries.filter(([, e]) => e.missingSince && !e.notRenamed)) {
    // Same system, size and file type, and first seen when (or after) the old one went missing: a
    // file that was already there is a different game.
    const candidates = present.filter(([to, e]) => !claimed.has(to) && sameKind(old, e, from, to)
      && e.firstSeen >= old.missingSince);
    // Fingerprints, where both are known, must agree; one not worked out yet doesn't rule it out.
    const possible = candidates.filter(([, e]) => !old.fp || !e.fp || e.fp === old.fp);
    const match = possible.length === 1 ? possible[0] : null;
    if (match) {
      claimed.add(match[0]);
      renamed.push({ from, to: match[0], system: old.system, title: old.title, newTitle: match[1].title });
    }
  }
  const renamedFrom = new Set(renamed.map((r) => r.from));
  const added = present.filter(([file, e]) => e.firstSeen > reviewedAt && !claimed.has(file))
    .map(([file, e]) => ({ path: file, system: e.system, title: e.title }));
  const missing = entries.filter(([file, e]) => e.missingSince && !renamedFrom.has(file))
    .map(([file, e]) => ({ path: file, system: e.system, title: e.title, since: e.missingSince }));
  const groups = new Map();
  for (const [file, e] of present) {
    if (!e.fp) continue;
    const key = `${e.system}:${e.fp}`;
    groups.set(key, [...(groups.get(key) || []), file]);
  }
  const duplicates = [...groups.entries()].filter(([, paths]) => paths.length > 1)
    .map(([key, paths]) => ({ system: key.split(':')[0], title: index[paths[0]].title, paths: paths.sort() }));
  return { added, renamed, missing, duplicates };
}

module.exports = { statFile, fingerprint, updateIndex, needsFingerprint, summarize };
