// Making the library survive.
//
// Two things go wrong with a browser app that stores your work:
//
// 1. IndexedDB is *evictable*. Under disk pressure a browser may delete it without asking.
//    `navigator.storage.persist()` asks for an exemption, and browsers grant it to sites the
//    person actually uses. Without it a review can disappear and nobody is told why.
//
// 2. Even when it survives, it is invisible. It lives inside browser profile data where you
//    cannot see it, back it up with everything else, or take it to another machine.
//
// So: persistence is requested as soon as there is anything to lose, and a folder on the real
// file system can be attached, into which the PDFs are written as ordinary files and the
// index as one JSON file. IndexedDB stays the working store because it is fast; the folder is
// a mirror you own, readable without this app ever running again.

const HANDLE_KEY = 'libraryFolder';

// ---------------------------------------------------------------- persistence

export async function persistenceState() {
  if (!navigator.storage?.persisted) return 'unsupported';
  return (await navigator.storage.persisted()) ? 'persistent' : 'evictable';
}

/// Asks the browser not to evict the library. Safe to call repeatedly; browsers decide on
/// their own signals, so a refusal is not an error, it just means keep the folder mirror.
export async function requestPersistence() {
  if (!navigator.storage?.persist) return 'unsupported';
  if (await navigator.storage.persisted()) return 'persistent';
  return (await navigator.storage.persist()) ? 'persistent' : 'refused';
}

// ---------------------------------------------------------------- folder mirror

export function folderSupported() {
  return typeof window.showDirectoryPicker === 'function';
}

export async function chooseFolder(db) {
  if (!folderSupported()) throw new Error('This browser cannot write to a folder. Use Back up instead.');
  const handle = await window.showDirectoryPicker({ mode: 'readwrite', id: 'sieve-library' });
  await db.put('meta', { key: HANDLE_KEY, handle });
  return handle;
}

export async function savedFolder(db) {
  const row = await db.get('meta', HANDLE_KEY);
  return row?.handle || null;
}

export async function forgetFolder(db) {
  await db.del('meta', HANDLE_KEY);
}

/// Permission does not survive a browser restart, and re-asking needs a click. Callers use
/// this to decide between "syncing" and "needs reconnecting".
export async function folderPermission(handle) {
  if (!handle) return 'none';
  const opts = { mode: 'readwrite' };
  if ((await handle.queryPermission(opts)) === 'granted') return 'granted';
  return 'prompt';
}

export async function reconnectFolder(handle) {
  return (await handle.requestPermission({ mode: 'readwrite' })) === 'granted';
}

// ---------------------------------------------------------------- writing the mirror

async function subdir(handle, name) {
  return handle.getDirectoryHandle(name, { create: true });
}

async function writeFile(dir, name, blob) {
  const file = await dir.getFileHandle(name, { create: true });
  const w = await file.createWritable();
  await w.write(blob);
  await w.close();
}

function safeName(title, id) {
  const slug = (title || 'source')
    .normalize('NFKD').replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '_').slice(0, 70);
  return `${slug || 'source'}-${id}.pdf`;
}

/// Writes the whole library into the folder: one PDF per source, plus an index describing
/// every highlight with the page and source it came from. A person who never opens this app
/// again can still read both.
///
/// `rest` carries everything else the review holds — the matrix, the frameworks, the method,
/// the trail. It is passed whole rather than named field by field so that adding a store to
/// the app can never quietly leave it out of the copy people restore from.
export async function syncFolder(handle, { sources, evidence, tags, fileFor, rest = {} }) {
  const pdfs = await subdir(handle, 'PDFs');
  const written = [];
  for (const s of sources) {
    const name = safeName(s.title, s.id);
    written.push({ id: s.id, file: `PDFs/${name}` });
    try {
      // Skip a file already on disk at the right size — resyncing should be cheap.
      const existing = await pdfs.getFileHandle(name).then(h => h.getFile()).catch(() => null);
      const rec = await fileFor(s.id);
      if (!rec?.blob) continue;
      if (existing && existing.size === rec.blob.size) continue;
      await writeFile(pdfs, name, rec.blob);
    } catch (err) {
      console.warn('could not write', name, err);
    }
  }

  const index = {
    format: 'sieve-web/1',
    written: new Date().toISOString(),
    note: 'Written by Sieve. The PDFs are in PDFs/. Every highlight below names the source and page it came from.',
    sources: sources.map(s => ({
      ...s,
      file: written.find(w => w.id === s.id)?.file || null,
    })),
    tags,
    evidence,
    ...rest,
  };
  await writeFile(handle, 'sieve-library.json', new Blob([JSON.stringify(index, null, 2)], { type: 'application/json' }));

  await writeFile(handle, 'README.txt', new Blob([[
    'Sieve library',
    '',
    'This folder is yours. Sieve wrote it and needs nothing from it to keep working, but if',
    'you ever clear your browser data, reinstall, or move to another machine, everything you',
    'need is here.',
    '',
    '  PDFs/               every source, as an ordinary PDF you can open in anything',
    '  sieve-library.json  the index: your highlights, their pages, tags, sources, and the',
    '                      rest of the review — matrix, frameworks, method, AI trail',
    '',
    'To restore: open Sieve, choose Restore, and pick sieve-library.json.',
    '',
    `Last written ${new Date().toLocaleString()} · ${sources.length} sources · ${evidence.length} highlights`,
  ].join('\n')], { type: 'text/plain' }));

  return written.length;
}

/// Reads a library back out of a folder — after clearing browser data, or on a new machine.
export async function readFolder(handle) {
  const file = await handle.getFileHandle('sieve-library.json').then(h => h.getFile());
  const index = JSON.parse(await file.text());
  const pdfs = await handle.getDirectoryHandle('PDFs').catch(() => null);
  const files = [];
  if (pdfs) {
    for (const s of index.sources || []) {
      if (!s.file) continue;
      const name = s.file.replace(/^PDFs\//, '');
      const f = await pdfs.getFileHandle(name).then(h => h.getFile()).catch(() => null);
      if (f) files.push({ sourceId: s.id, name, blob: f });
    }
  }
  return { index, files };
}
