// Storage for Sieve on the web.
//
// Everything lives in this browser: records, highlights, tags and the PDF bytes themselves.
// There is no server and no account, which is deliberate — the desktop app's whole argument
// is that a review is yours and stays on your machine, and moving to a browser is no reason
// to hand it to somebody else's.
//
// IndexedDB holds it all, including the PDFs as blobs, so the app works with the network off
// and a backup is a single file you export and keep.

const DB_NAME = 'sieve';
const DB_VERSION = 1;

let dbp = null;

export function open() {
  if (dbp) return dbp;
  dbp = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;

      if (!db.objectStoreNames.contains('sources')) {
        const s = db.createObjectStore('sources', { keyPath: 'id', autoIncrement: true });
        s.createIndex('byKey', 'dedupeKey', { unique: false });
        s.createIndex('byStage', 'stage', { unique: false });
      }
      // PDF bytes are kept apart from the record so listing the library never loads them.
      if (!db.objectStoreNames.contains('files')) {
        db.createObjectStore('files', { keyPath: 'sourceId' });
      }
      if (!db.objectStoreNames.contains('evidence')) {
        const e = db.createObjectStore('evidence', { keyPath: 'id', autoIncrement: true });
        e.createIndex('bySource', 'sourceId', { unique: false });
      }
      if (!db.objectStoreNames.contains('tags')) {
        db.createObjectStore('tags', { keyPath: 'id', autoIncrement: true });
      }
      if (!db.objectStoreNames.contains('meta')) {
        db.createObjectStore('meta', { keyPath: 'key' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbp;
}

async function tx(store, mode, fn) {
  const db = await open();
  return new Promise((resolve, reject) => {
    const t = db.transaction(store, mode);
    const s = t.objectStore(store);
    let out;
    try { out = fn(s); } catch (err) { reject(err); return; }
    t.oncomplete = () => resolve(out && out.result !== undefined ? out.result : out);
    t.onerror = () => reject(t.error);
  });
}

export const put = (store, value) => tx(store, 'readwrite', s => s.put(value));
export const del = (store, key) => tx(store, 'readwrite', s => s.delete(key));
export const get = (store, key) => tx(store, 'readonly', s => s.get(key));
export const all = (store) => tx(store, 'readonly', s => s.getAll());

export async function byIndex(store, index, value) {
  const db = await open();
  return new Promise((resolve, reject) => {
    const t = db.transaction(store, 'readonly');
    const req = t.objectStore(store).index(index).getAll(value);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

// The categories a highlight can carry. Same defaults as the desktop app, and the colour is
// the category — that is the whole interaction.
export const DEFAULT_TAGS = [
  { name: 'Definition',    color: '#4C8DF2', shortcut: '1', detail: 'How the source defines a key idea.' },
  { name: 'Method',        color: '#9B6BE8', shortcut: '2', detail: 'Design, sample, instrument, procedure.' },
  { name: 'Finding',       color: '#4CAF7D', shortcut: '3', detail: 'A result the authors actually report.' },
  { name: 'Limitation',    color: '#EF8A45', shortcut: '4', detail: 'What the work cannot claim.' },
  { name: 'Gap',           color: '#E86A9A', shortcut: '5', detail: 'Something unstudied — your opening.' },
  { name: 'Contradiction', color: '#E2564D', shortcut: '6', detail: 'Conflicts with another source.' },
  { name: 'Quote',         color: '#F2C14E', shortcut: '7', detail: 'Worth quoting verbatim.' },
  { name: 'Theory',        color: '#3FB8AF', shortcut: '8', detail: 'A frame or model invoked.' },
];

export async function seed() {
  const tags = await all('tags');
  if (tags.length) return tags;
  for (const t of DEFAULT_TAGS) await put('tags', t);
  return all('tags');
}

/// A whole library as one JSON file. Owning your data means being able to walk away with it.
export async function exportAll() {
  const [sources, evidence, tags, files] = await Promise.all([
    all('sources'), all('evidence'), all('tags'), all('files')
  ]);
  const encoded = [];
  for (const f of files) {
    const buf = await f.blob.arrayBuffer();
    let bin = '';
    const bytes = new Uint8Array(buf);
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) {
      bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    encoded.push({ sourceId: f.sourceId, name: f.name, base64: btoa(bin) });
  }
  return { format: 'sieve-web/1', exported: new Date().toISOString(), sources, evidence, tags, files: encoded };
}

export async function importAll(data) {
  if (!data || data.format !== 'sieve-web/1') throw new Error('Not a Sieve export.');
  for (const t of data.tags || []) await put('tags', t);
  for (const s of data.sources || []) await put('sources', s);
  for (const e of data.evidence || []) await put('evidence', e);
  for (const f of data.files || []) {
    const bin = atob(f.base64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    await put('files', { sourceId: f.sourceId, name: f.name, blob: new Blob([bytes], { type: 'application/pdf' }) });
  }
}

/// How much room the browser has given us, and how much is used. Worth showing, because a
/// library of PDFs in IndexedDB is not weightless.
export async function usage() {
  if (!navigator.storage || !navigator.storage.estimate) return null;
  const { usage, quota } = await navigator.storage.estimate();
  return { usage, quota };
}
