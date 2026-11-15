// Sync: the account's copy of the library, kept in step with this browser's.
//
// The local library (IndexedDB) stays the working copy, so Sieve works offline exactly as it
// always has. When someone is signed in, every local change is queued and pushed to the
// `records` table (one row per record, data kept as-is), and changes from other devices are
// pulled down. The server's clock orders changes; the last write wins per record. PDFs go to
// the private `pdfs` bucket named by their SHA-256, so the same paper is stored once.
//
// Schema: supabase/migrations/20261115120000_sieve_cloud_init.sql

import * as db from './db.js';
import * as auth from './auth.js';

const NOT_SYNCED = new Set(['meta']);          // per-device preferences
const PAGE = 500;
const PUSH_CHUNK = 200;
const MAX_PDF = 50 * 1024 * 1024;              // bucket limit
const POLL_MS = 30000;

let uid = null;
let client = null;
let outbox = new Map();                         // "store\u0000key" → [store, key, version]
let version = 0;
let pushTimer = null;
let pollTimer = null;
let busy = null;
let status = { state: 'off', at: null, detail: '' };

const lsKey = (k) => `sieve-sync:${uid}:${k}`;
const lsGet = (k) => { try { return localStorage.getItem(lsKey(k)); } catch { return null; } };
const lsSet = (k, v) => { try { localStorage.setItem(lsKey(k), v); } catch { /* storage blocked */ } };

export function state() { return status; }

function setStatus(state, detail = '') {
  status = { state, detail, at: new Date() };
  window.dispatchEvent(new CustomEvent('sieve:sync-status', { detail: status }));
}

// ---------------------------------------------------------------- outbox

function loadOutbox() {
  outbox = new Map();
  try {
    for (const [store, key] of JSON.parse(lsGet('outbox') || '[]')) outbox.set(id(store, key), [store, key, 0]);
  } catch { /* corrupt: a full push on next init covers it */ }
}
function saveOutbox() { lsSet('outbox', JSON.stringify([...outbox.values()].map(([s, k]) => [s, k]))); }
const id = (store, key) => `${store}\u0000${key}`;

function shouldSync(store, value) {
  if (NOT_SYNCED.has(store)) return false;
  // Method recipes are seeded on every device; syncing them would duplicate them.
  if (store === 'methods' && value?.isTemplate) return false;
  return true;
}

function mark(store, key) {
  outbox.set(id(store, key), [store, key, ++version]);
}

db.onWrite((store, key, value) => {
  if (!uid || !shouldSync(store, value)) return;
  mark(store, key);
  saveOutbox();
  schedulePush();
});

function schedulePush(delay = 1500) {
  clearTimeout(pushTimer);
  pushTimer = setTimeout(() => run(push), delay);
}

// ---------------------------------------------------------------- push

async function sha256(blob) {
  const buf = await crypto.subtle.digest('SHA-256', await blob.arrayBuffer());
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
}

async function uploadPdf(file) {
  const sha = file.sha256 || await sha256(file.blob);
  if (!file.sha256) { file.sha256 = sha; await db.rawPut('files', file); }
  if (file.blob.size > MAX_PDF) return { sha, skipped: 'too large for cloud backup (50 MB limit)' };
  const path = `${uid}/${sha}.pdf`;
  const { error } = await client.storage.from('pdfs').upload(path, file.blob, {
    contentType: 'application/pdf', upsert: false,
  });
  // Same hash already uploaded (from this or another device): nothing to do.
  if (error && !/exists|duplicate|409/i.test(`${error.message} ${error.statusCode || ''}`)) throw error;
  return { sha };
}

async function rowFor(store, key) {
  const now = new Date().toISOString();
  const gone = { user_id: uid, store, key: String(key), data: {}, deleted_at: now };
  if (store === 'files') {
    const f = await db.get('files', key);
    if (!f?.blob) return gone;
    const up = await uploadPdf(f);
    return { user_id: uid, store, key: String(key), deleted_at: null,
      data: { sourceId: f.sourceId, name: f.name, sha256: up.sha, size: f.blob.size, ...(up.skipped ? { skipped: up.skipped } : {}) } };
  }
  const v = await db.get(store, key);
  if (v == null) return gone;
  return { user_id: uid, store, key: String(key), data: JSON.parse(JSON.stringify(v)), deleted_at: null };
}

async function push() {
  if (!outbox.size) return;
  const entries = [...outbox.values()];
  for (let i = 0; i < entries.length; i += PUSH_CHUNK) {
    const chunk = entries.slice(i, i + PUSH_CHUNK);
    const rows = [];
    for (const [store, key] of chunk) rows.push(await rowFor(store, key));
    const { error } = await client.from('records').upsert(rows, { onConflict: 'user_id,store,key' });
    if (error) throw error;
    // Drop only what has not changed again while we were pushing it.
    for (const [store, key, v] of chunk) {
      const cur = outbox.get(id(store, key));
      if (cur && cur[2] === v) outbox.delete(id(store, key));
    }
    saveOutbox();
  }
}

// ---------------------------------------------------------------- pull

const NUMERIC_KEYS = new Set(['projects', 'sources', 'evidence', 'tags', 'columns', 'frames', 'axes',
                              'searchRuns', 'methods', 'aiEvents', 'files']);
const keyOf = (store, row) => (store === 'cells' || store === 'frameCells' ? row.key : row.id);
const localKey = (store, key) => (NUMERIC_KEYS.has(store) && /^\d+$/.test(key) ? Number(key) : key);

function stable(v) {
  if (Array.isArray(v)) return `[${v.map(stable).join(',')}]`;
  if (v && typeof v === 'object') return `{${Object.keys(v).sort().map(k => `${JSON.stringify(k)}:${stable(v[k])}`).join(',')}}`;
  return JSON.stringify(v);
}

async function applyRow(r) {
  const key = localKey(r.store, r.key);
  if (outbox.has(id(r.store, key))) return false;     // a newer local edit is waiting to go up
  const local = await db.get(r.store, key);
  if (r.deleted_at) {
    if (local == null) return false;
    await db.rawDel(r.store, key);
    return true;
  }
  if (r.store === 'files') {
    if (local?.blob && local.sha256 === r.data.sha256) return false;
    if (r.data.skipped) return false;
    const { data: blob, error } = await client.storage.from('pdfs').download(`${uid}/${r.data.sha256}.pdf`);
    if (error) { console.warn('PDF download failed', r.data.name, error); return false; }
    await db.rawPut('files', { sourceId: r.data.sourceId, name: r.data.name, sha256: r.data.sha256,
      blob: new Blob([blob], { type: 'application/pdf' }) });
    return true;
  }
  if (local != null && stable(local) === stable(r.data)) return false;
  await db.rawPut(r.store, r.data);
  return true;
}

async function pull() {
  let since = lsGet('since') || '1970-01-01T00:00:00Z';
  let seenAtSince = new Set(JSON.parse(lsGet('seen') || '[]'));
  let changed = 0, projectsArrived = 0;
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await client.from('records')
      .select('store,key,data,updated_at,deleted_at')
      .gte('updated_at', since)
      .order('updated_at', { ascending: true }).order('store').order('key')
      .range(from, from + PAGE - 1);
    if (error) throw error;
    for (const r of data) {
      const tag = id(r.store, r.key);
      if (r.updated_at === since && seenAtSince.has(tag)) continue;
      if (await applyRow(r)) { changed++; if (r.store === 'projects' && !r.deleted_at) projectsArrived++; }
      if (r.updated_at !== since) { since = r.updated_at; seenAtSince = new Set(); }
      seenAtSince.add(tag);
    }
    if (data.length < PAGE) break;
  }
  lsSet('since', since);
  lsSet('seen', JSON.stringify([...seenAtSince]));
  if (changed) window.dispatchEvent(new CustomEvent('sieve:remote-change', { detail: { changed, projectsArrived } }));
  return { changed, projectsArrived };
}

// ---------------------------------------------------------------- first sync on a device

/// A brand-new browser seeds an empty "My first review". If the account already has
/// reviews, that placeholder should quietly go away instead of joining them.
async function seedOnly() {
  const [projects, sources, evidence] = await Promise.all(['projects', 'sources', 'evidence'].map(db.all));
  return projects.length === 1 && !sources.length && !evidence.length && !projects[0].question
    ? projects[0] : null;
}

async function removeLocalProject(pid) {
  for (const store of ['columns', 'tags', 'frames', 'axes', 'cells', 'frameCells', 'methods', 'searchRuns', 'aiEvents']) {
    for (const row of await db.all(store)) {
      if (row.projectId === pid && !row.isTemplate) await db.rawDel(store, keyOf(store, row));
    }
  }
  await db.rawDel('projects', pid);
}

async function markEverything() {
  for (const store of db.STORES) {
    if (!shouldSync(store)) continue;
    for (const row of await db.all(store)) {
      if (!shouldSync(store, row)) continue;
      mark(store, keyOf(store, row));
    }
  }
  for (const f of await db.all('files')) mark('files', f.sourceId);
  saveOutbox();
}

async function firstSync() {
  const placeholder = await seedOnly();
  if (placeholder) {
    const { projectsArrived } = await pull();
    if (projectsArrived) {
      await removeLocalProject(placeholder.id);
      lsSet('init', '1');
      // The open review no longer exists; start again on one of the account's reviews.
      try { await db.rawDel('meta', 'currentProject'); } catch { /* fine */ }
      location.reload();
      return;
    }
  }
  await markEverything();
  await push();
  await pull();
  lsSet('init', '1');
}

// ---------------------------------------------------------------- running

function run(task) {
  if (!uid || !client) return Promise.resolve();
  if (!navigator.onLine) { setStatus('offline', 'Changes are saved here and will sync when you are back online.'); return Promise.resolve(); }
  // One sync at a time; a request made meanwhile runs once the current one finishes.
  busy = (busy || Promise.resolve()).then(async () => {
    setStatus('syncing');
    try {
      await task();
      setStatus(outbox.size ? 'pending' : 'synced');
    } catch (err) {
      console.warn('Sync failed', err);
      setStatus('error', err?.message || String(err));
    }
  });
  return busy;
}

export function syncNow() { return run(async () => { await push(); await pull(); }); }

// Sync waits for the app to finish opening (and seeding) its library, so a first sync never
// races the "My first review" placeholder being created.
let markReady;
const appReady = new Promise(r => { markReady = r; });
export function ready() { markReady(); }

async function startFor(user) {
  await appReady;
  if (user?.id === uid) return;
  stop();
  if (!user) return;
  uid = user.id;
  client = auth.supabase();
  loadOutbox();
  run(lsGet('init') ? async () => { await push(); await pull(); } : firstSync);
  pollTimer = setInterval(() => { if (document.visibilityState === 'visible') syncNow(); }, POLL_MS);
}

function stop() {
  clearInterval(pollTimer); clearTimeout(pushTimer);
  uid = null; client = null; outbox = new Map();
  setStatus('off');
}

auth.onChange(startFor);
window.addEventListener('online', () => syncNow());
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') syncNow(); });
// Push what is queued before the tab goes away, as far as the browser allows.
window.addEventListener('pagehide', () => { if (outbox.size) run(push); });
