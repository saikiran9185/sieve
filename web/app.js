// Sieve on the web — the shell.
//
// Holds the state every screen reads, routes between them, and owns the things that touch
// storage. The screens themselves are in views.js and reader.js; this is what they hang off.
//
// The argument is unchanged from the desktop app: evidence stays tied to where it came from,
// and the library belongs to whoever is reading it. There is no account because there is no
// server — a sign-in would mean somewhere holding your research.

import * as db from './db.js';
import * as store from './storage.js';
import { Reader } from './reader.js';
import * as views from './views.js';
import * as inspector from './inspector.js';
import * as method from './method.js';
import * as mapView from './map.js';
import * as trail from './trail.js';
import * as guide from './guide.js';
import * as exports from './exports.js';
import * as citations from './citations.js';
import * as retrieve from './retrieve.js';
import { readZip } from './zip.js';
import { dedupeKey } from './search.js';

const $ = (s) => document.querySelector(s);
const el = views.el;
const chip = views.chip;

const state = {
  project: null, projects: [],
  sources: [], evidence: [], tags: [], columns: [], cells: {},
  frames: [], axes: [], frameCells: {},
  methods: [], aiEvents: [], searchRuns: [], allSources: [], allEvidence: [],
  openId: null, selection: null, stance: 'evidence', view: 'overview',
  railFilter: 'included', railQuery: '', railHidden: false,
};
let reader = null;

const STANCES = {
  evidence:       { label: 'Evidence',       color: '#4C8DF2', hint: 'What the source actually says.' },
  interpretation: { label: 'Interpretation', color: '#9B6BE8', hint: 'What you think it means.' },
  question:       { label: 'Question',       color: '#F2C14E', hint: "What you don't know yet." },
};

// ---------------------------------------------------------------- boot

async function boot() {
  // The buttons are wired before anything is loaded. If the library is slow, or refuses to
  // open at all, a sidebar whose every control is dead is a worse answer than an empty one.
  wire();
  try {
    state.projects = await db.seed();
    const savedId = (await db.get('meta', 'currentProject'))?.value;
    state.project = state.projects.find(p => p.id === savedId) || state.projects[0];
    await refresh();
    go('overview');
  } catch (err) {
    cannotOpen(err);
    return;
  }
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
  await showSafety();
}

/// Says what went wrong and what to do about it. A blank app that answers no clicks is the
/// one failure a person cannot diagnose, report or work around.
function cannotOpen(err) {
  console.error('Sieve could not open its library', err);
  $('#projectName').textContent = 'Sieve';
  $('#projectMeta').textContent = 'library not open';
  $('#safetyDot').className = 'dot bad';
  $('#safetyText').textContent = 'Library not open';
  $('#folderBtn').hidden = true;

  const box = el('div', 'empty');
  box.appendChild(el('h2', null, 'Sieve could not open your library'));
  if (err?.blocked) {
    box.appendChild(el('p', null,
      'Another tab or window still has an older version of Sieve open, and a browser will not upgrade a library while that is true.'));
    box.appendChild(el('p', null,
      'Close the other Sieve tabs — and the installed app, if you added it to your dock — then reload this page. Nothing has been lost: your sources and highlights are exactly where they were.'));
  } else {
    box.appendChild(el('p', null,
      'The browser refused to open the local database. This usually means private browsing, or storage switched off for this site.'));
    box.appendChild(el('p', 'hint', String(err?.message || err)));
  }
  const again = el('button', 'primary', 'Reload');
  again.onclick = () => location.reload();
  box.appendChild(again);

  for (const v of document.querySelectorAll('.view')) v.classList.add('hidden');
  const overview = $('#overview');
  overview.classList.remove('hidden');
  overview.innerHTML = '';
  overview.appendChild(box);
  // Every screen would show the same failure, so none of them should pretend otherwise.
  for (const b of document.querySelectorAll('.nav')) b.disabled = true;
}

/// Reloads everything for the current review. Scoping happens here so no screen has to
/// remember to filter, and two reviews can never contaminate each other's counts.
async function refresh() {
  const pid = state.project?.id;
  const [sources, evidence, tags, columns, cells, frames, axes, frameCells, files, methods, aiEvents, searchRuns] =
    await Promise.all(['sources','evidence','tags','columns','cells','frames','axes','frameCells','files',
                       'methods','aiEvents','searchRuns'].map(db.all));

  const mine = r => r.projectId === pid;
  const withFiles = new Set(files.map(f => f.sourceId));
  // Kept unscoped so the review picker can say how big each review is without reloading.
  state.allSources = sources;
  state.allEvidence = evidence;
  state.sources = sources.filter(mine).map(s => ({ ...s, hasFile: withFiles.has(s.id) }));
  state.evidence = evidence.filter(mine);
  state.tags = tags.filter(mine);
  state.columns = columns.filter(mine);
  state.frames = frames.filter(mine);
  state.axes = axes.filter(mine);
  state.cells = Object.fromEntries(cells.filter(mine).map(c => [c.key, c]));
  state.frameCells = Object.fromEntries(frameCells.filter(mine).map(c => [c.key, c]));
  // Recipes belong to no review; the method being run belongs to this one.
  state.methods = methods.filter(m => m.isTemplate || m.projectId === pid);
  state.aiEvents = aiEvents.filter(mine);
  state.searchRuns = searchRuns.filter(mine).sort((a, b) => String(a.at).localeCompare(String(b.at)));

  $('#projectName').textContent = state.project?.name || 'Review';
  $('#projectMeta').textContent =
    `${state.sources.length} source${state.sources.length === 1 ? '' : 's'} · ${state.evidence.length} highlight${state.evidence.length === 1 ? '' : 's'}`;
  const toScreen = state.sources.filter(s => s.stage === 'identified').length;
  $('#badgeScreening').textContent = toScreen || '';
  $('#badgeEvidence').textContent = state.evidence.length || '';
  $('#badgeTags').textContent = state.tags.length || '';
  $('#badgeTrail').textContent = trail.pendingCount(state) || '';
  showMethodLine();
  renderCurrent();
}

// ---------------------------------------------------------------- routing

const RENDERERS = {
  overview: (r) => views.renderOverview(ctx, r),
  find: (r) => views.renderFind(ctx, r),
  screening: (r) => views.renderScreening(ctx, r),
  matrix: (r) => views.renderMatrix(ctx, r),
  frames: (r) => views.renderFrames(ctx, r),
  prisma: (r) => views.renderPrisma(ctx, r),
  settings: (r) => renderSettings(r),
  method: (r) => method.render(ctx, r),
  map: (r) => mapView.render(ctx, r),
  trail: (r) => trail.render(ctx, r),
  guide: (r) => guide.render(ctx, r),
  library: () => renderLibrary(),
  evidence: () => renderEvidence(),
  tags: () => renderTags(),
  reader: () => { renderRail(); renderPalette(); renderInspector(); },
};

function go(name) {
  state.view = name;
  for (const v of document.querySelectorAll('.view')) v.classList.toggle('hidden', v.id !== name);
  for (const b of document.querySelectorAll('.nav')) b.setAttribute('aria-current', String(b.dataset.view === name));
  renderCurrent();
}
function renderCurrent() {
  const fn = RENDERERS[state.view];
  if (fn) fn(document.querySelector('#' + state.view));
}

// ---------------------------------------------------------------- shared helpers for views

const ctx = {
  state, refresh, go, toast, openSource,
  prompt: promptFor, sheet, download, exportSheet: () => exportSheet(),
  async setStage(id, stage, reason = '') {
    const s = await db.get('sources', id);
    if (!s) return;
    s.stage = stage; s.reason = reason;
    await db.put('sources', s);
    await refresh();
    scheduleSync();
  },
  async addFromHits(hits, query) {
    const have = new Set(state.sources.map(s => s.dedupeKey));
    let added = 0;
    for (const h of hits) {
      const key = dedupeKey(h);
      if (have.has(key)) continue;
      have.add(key);
      const id = await db.put('sources', {
        projectId: state.project.id, title: h.title, authors: h.authors, year: h.year,
        venue: h.venue, doi: h.doi, abstract: h.abstract, url: h.url, pdfURL: h.pdfURL,
        provider: [h.provider, ...(h.alsoFrom || [])].join(' + '), sdgs: h.sdgs || [],
        citedBy: h.citedBy || 0, stage: 'identified', reason: '', dedupeKey: key,
        keywords: [], conclusion: '', conclusionHeading: '', notes: '', toRead: '',
        openAlexId: h.openAlexId || '', references: h.references || [],
        added: new Date().toISOString(), foundBy: query,
      });
      added++;
      // Two machine judgements worth being able to check later: that these records were the
      // same paper, and that these subject labels describe it.
      if ((h.alsoFrom || []).length) {
        await db.trail(state.project.id, 'mergeRecords', id,
          `Records from ${[h.provider, ...h.alsoFrom].join(', ')} were folded into one paper: “${h.title}”.`);
      }
      if ((h.sdgs || []).length) {
        await db.trail(state.project.id, 'labelSDG', id,
          `Labelled ${h.sdgs.join(', ')} — OpenAlex's classifier, not the authors' words.`);
      }
    }
    if (added) { await db.put('searchRuns', { projectId: state.project.id, query, added, at: new Date().toISOString() }); }
    await refresh();
    scheduleSync();
    return added;
  },
};

function showMethodLine() {
  const m = method.active(state);
  $('#methodName').textContent = m ? m.name : 'Choose a method';
  $('#methodStep').textContent = m
    ? (m.step >= m.blocks.length
        ? 'every step done'
        : `step ${m.step + 1} of ${m.blocks.length} · ${db.METHOD_BLOCKS[m.blocks[m.step]]?.label || ''}`)
    : 'optional — the app works without one';
}

function download(name, text, type = 'text/plain') {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = document.createElement('a');
  a.href = url; a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function sheet(title, build) {
  const modal = $('#modal'), body = $('#modalBody');
  body.innerHTML = '';
  body.appendChild(el('h2', null, title));
  const close = () => { modal.classList.add('hidden'); body.innerHTML = ''; };
  build(body, close);
  modal.classList.remove('hidden');
  modal.onclick = (e) => { if (e.target === modal) close(); };
}

function promptFor(title, hint, done) {
  sheet(title, (body, close) => {
    const f = el('div', 'field');
    if (hint) f.appendChild(el('label', null, hint));
    const input = el('input');
    f.appendChild(input);
    body.appendChild(f);
    const actions = el('div', 'actions');
    const cancel = el('button', 'quiet', 'Cancel'); cancel.onclick = close;
    const ok = el('button', 'primary', 'Add');
    ok.onclick = async () => { const v = input.value.trim(); close(); await done(v); };
    input.onkeydown = e => { if (e.key === 'Enter') ok.click(); };
    actions.append(cancel, ok);
    body.appendChild(actions);
    setTimeout(() => input.focus(), 30);
  });
}

// ---------------------------------------------------------------- storage safety

async function showSafety() {
  const dot = $('#safetyDot'), text = $('#safetyText'), btn = $('#folderBtn');
  const handle = await store.savedFolder(db).catch(() => null);
  const perm = await store.folderPermission(handle);
  const persisted = await store.persistenceState();

  if (handle && perm === 'granted') {
    dot.className = 'dot good'; text.textContent = `Copied to ${handle.name}`;
    btn.textContent = 'Sync now'; btn.onclick = () => syncNow(handle);
  } else if (handle && perm === 'prompt') {
    dot.className = 'dot warn'; text.textContent = 'Folder needs reconnecting';
    btn.textContent = `Reconnect ${handle.name}`;
    btn.onclick = async () => {
      if (await store.reconnectFolder(handle)) await syncNow(handle);
      else toast('Permission declined — the browser copy is still there');
      await showSafety();
    };
  } else if (persisted === 'persistent') {
    dot.className = 'dot good'; text.textContent = 'Saved on this computer';
    btn.textContent = store.folderSupported() ? 'Also keep a folder copy' : 'Back up to a file';
    btn.onclick = store.folderSupported() ? pickFolder : () => $('#exportBtn').click();
  } else {
    dot.className = 'dot bad'; text.textContent = 'Could be cleared by the browser';
    btn.textContent = store.folderSupported() ? 'Keep a copy in a folder' : 'Back up to a file';
    btn.onclick = store.folderSupported() ? pickFolder : () => $('#exportBtn').click();
  }
  await showStorage();
}

async function showStorage() {
  const u = await db.usage();
  if (!u) return;
  const size = (n) => n >= 1073741824 ? `${(n / 1073741824).toFixed(1)} GB`
             : n >= 1048576 ? `${Math.round(n / 1048576)} MB` : `${Math.round(n / 1024)} KB`;
  $('#storage').textContent = `${size(u.usage)} used · about ${size(u.quota)} available here.`;
}

async function pickFolder() {
  try { await syncNow(await store.chooseFolder(db)); }
  catch (err) { if (err.name !== 'AbortError') toast(err.message || 'Could not use that folder'); }
  await showSafety();
}

async function syncNow(handle) {
  if (!state.sources.length) { toast('Nothing to copy yet'); await showSafety(); return; }
  toast('Copying to your folder…');
  try {
    const n = await store.syncFolder(handle, { ...(await folderPayload()), fileFor: (id) => db.get('files', id) });
    toast(`${n} PDF${n === 1 ? '' : 's'} and an index written to ${handle.name}`);
  } catch { toast('Could not write to that folder — reconnect it'); }
  await showSafety();
}

/// Everything the folder copy has to carry. Built from the store list rather than from named
/// fields, so a store added to the app cannot go missing from the copy people restore from.
async function folderPayload() {
  const rest = {};
  for (const name of db.STORES) {
    if (name === 'sources' || name === 'evidence' || name === 'tags') continue;
    rest[name] = await db.all(name);
  }
  return { sources: state.sources, evidence: state.evidence, tags: state.tags, rest };
}

let syncTimer = null;
function scheduleSync() {
  clearTimeout(syncTimer);
  syncTimer = setTimeout(async () => {
    const handle = await store.savedFolder(db).catch(() => null);
    if (!handle || (await store.folderPermission(handle)) !== 'granted') return;
    try {
      await store.syncFolder(handle, { ...(await folderPayload()), fileFor: (id) => db.get('files', id) });
    } catch {}
  }, 2500);
}

// ---------------------------------------------------------------- library

function renderLibrary() {
  const list = $('#sourceList');
  const q = $('#filter').value.toLowerCase();
  const stage = $('#stageFilter').value;

  const sel = $('#stageFilter');
  if (sel.options.length <= 1) {
    for (const [k, v] of Object.entries(db.STAGES)) sel.appendChild(new Option(v.label, k));
  }
  list.innerHTML = '';
  const rows = state.sources.filter(s => {
    if (stage && s.stage !== stage) return false;
    if (!q) return true;
    return (s.title + ' ' + (s.authors || []).join(' ')).toLowerCase().includes(q);
  });
  $('#libraryCount').textContent = `${rows.length} of ${state.sources.length}`;

  if (!state.sources.length) {
    const e = el('div', 'empty');
    e.appendChild(el('h2', null, 'Nothing here yet'));
    e.appendChild(el('p', null, 'Search the databases under Find papers, or drop PDFs anywhere on this page. They are stored on this computer and never uploaded.'));
    list.appendChild(e);
    return;
  }
  for (const s of rows) list.appendChild(sourceCard(s));
}

function sourceCard(s) {
  const n = state.evidence.filter(e => e.sourceId === s.id).length;
  const card = el('div', 'card');
  card.appendChild(el('h4', null, s.title));
  card.appendChild(el('div', 'meta',
    [(s.authors || []).slice(0, 3).join(', ') || 'Unknown author', s.year, s.venue, s.pages ? `${s.pages} pages` : null]
      .filter(Boolean).join(' · ')));

  const chips = el('div', 'chips');
  const st = db.STAGES[s.stage] || db.STAGES.identified;
  chips.appendChild(chip(st.label, st.color));
  if (s.provider) chips.appendChild(chip(s.provider, 'var(--faint)'));
  if (s.hasFile) chips.appendChild(chip('PDF', 'var(--emerald)'));
  else if (s.pdfURL) chips.appendChild(chip('free PDF online', 'var(--accent)'));
  if (n) chips.appendChild(chip(`${n} highlight${n === 1 ? '' : 's'}`, 'var(--amber)'));
  for (const g of (s.sdgs || []).slice(0, 2)) chips.appendChild(chip(g, 'var(--accent)'));
  if (s.reason) chips.appendChild(chip(s.reason, 'var(--faint)'));
  card.appendChild(chips);

  if (s.abstract) {
    const p = el('p', 'meta', s.abstract.slice(0, 240) + (s.abstract.length > 240 ? '…' : ''));
    p.style.marginTop = '7px';
    card.appendChild(p);
  }

  const actions = el('div', 'actions');
  if (s.hasFile) {
    const read = el('button', 'primary', 'Read');
    read.onclick = () => { openSource(s.id); go('reader'); };
    actions.appendChild(read);
  } else {
    const get = el('button', 'primary', 'Get the PDF');
    get.title = 'Ask OpenAlex and Unpaywall for a free copy, and fetch it if the host allows it';
    get.onclick = () => getPDF(s);
    actions.appendChild(get);
  }
  if (s.url) {
    const src = el('button', 'quiet', 'Source page');
    src.onclick = () => window.open(s.url, '_blank', 'noopener');
    actions.appendChild(src);
  }
  const rm = el('button', 'quiet danger', 'Remove');
  rm.onclick = async () => {
    if (!confirm(`Remove “${s.title}”? Its highlights go too.`)) return;
    for (const e of state.evidence.filter(e => e.sourceId === s.id)) await db.del('evidence', e.id);
    await db.del('files', s.id); await db.del('sources', s.id);
    await refresh(); toast('Removed');
  };
  actions.appendChild(rm);
  card.appendChild(actions);
  return card;
}

// ---------------------------------------------------------------- import

async function addFiles(files) {
  if (!state.sources.length) await store.requestPersistence().catch(() => {});

  // A .bib or .ris is how references arrive from Zotero, Mendeley and the databases a
  // browser cannot query. It is a drop, exactly like a PDF.
  const citationFiles = [...files].filter(f => /\.(bib|bibtex|ris|txt)$/i.test(f.name));
  let fromFiles = 0;
  for (const file of citationFiles) {
    const hits = citations.parseCitations(await file.text(), file.name);
    if (!hits.length) continue;
    fromFiles += await ctx.addFromHits(hits, `Imported from ${file.name}`);
  }
  if (fromFiles) toast(`${fromFiles} reference${fromFiles === 1 ? '' : 's'} imported`);
  else if (citationFiles.length && ![...files].some(f => /\.pdf$/i.test(f.name))) {
    toast('No references found in that file');
  }

  let added = 0, already = 0, attached = 0;
  for (const file of files) {
    if (!/\.pdf$/i.test(file.name)) continue;
    const buf = await file.arrayBuffer();
    const digest = await crypto.subtle.digest('SHA-256', buf.slice(0, 262144));
    const hash = [...new Uint8Array(digest)].slice(0, 12).map(b => b.toString(16).padStart(2, '0')).join('') + '-' + buf.byteLength;
    if (state.sources.some(s => s.fileHash === hash)) { already++; continue; }

    let sec = {};
    try { sec = await Reader.readSections(new Blob([buf])); } catch {}

    // A dropped PDF is very often one of the records already found by a search. Match it on
    // title so it attaches rather than becoming a second copy of the same paper.
    const key = dedupeKey({ doi: '', title: sec.title || file.name, year: null });
    const existing = state.sources.find(s => !s.hasFile &&
      (s.dedupeKey === key || similarTitle(s.title, sec.title || '')));

    if (existing) {
      const rec = await db.get('sources', existing.id);
      Object.assign(rec, {
        fileHash: hash, pages: sec.pageCount,
        abstract: rec.abstract || sec.abstract || '',
        keywords: rec.keywords?.length ? rec.keywords : (sec.keywords || []),
        conclusion: sec.conclusion || rec.conclusion || '',
        conclusionHeading: sec.conclusionHeading || rec.conclusionHeading || '',
      });
      await db.put('sources', rec);
      await db.put('files', { sourceId: existing.id, name: file.name, blob: new Blob([buf], { type: 'application/pdf' }) });
      await logExtraction(existing.id, sec, rec);
      attached++;
      continue;
    }

    const source = {
      projectId: state.project.id,
      title: sec.title || file.name.replace(/\.pdf$/i, '').replace(/[_-]+/g, ' '),
      authors: [], year: null, stage: 'identified', reason: '', fileHash: hash,
      provider: 'Dropped PDF', dedupeKey: key, sdgs: [],
      abstract: sec.abstract || '', keywords: sec.keywords || [],
      conclusion: sec.conclusion || '', conclusionHeading: sec.conclusionHeading || '',
      pages: sec.pageCount, added: new Date().toISOString(),
    };
    const id = await db.put('sources', source);
    await db.put('files', { sourceId: id, name: file.name, blob: new Blob([buf], { type: 'application/pdf' }) });
    await logExtraction(id, sec, source, !sec.title);
    added++;
  }
  if (!added && !attached && !already) { await refresh(); return; }
  await refresh();
  const parts = [];
  if (added) parts.push(`${added} added`);
  if (attached) parts.push(`${attached} attached to records you already had`);
  if (already) parts.push(`${already} already here`);
  toast(parts.length ? parts.join(' · ') : 'No PDFs in that drop');
  await showSafety();
  scheduleSync();
}

/// Nothing here was typed by a person: an abstract and a conclusion found by matching
/// headings, and sometimes a title taken from the first plausible line on page one. Each
/// goes in the trail as a claim to check rather than as a fact.
async function logExtraction(sourceId, sec, record, titleGuessed = false) {
  if (sec.abstract && !record.abstractLogged) {
    await db.trail(state.project.id, 'extractSection', sourceId,
      `Abstract, read out of the PDF: ${sec.abstract.slice(0, 500)}`);
  }
  if (sec.conclusion) {
    await db.trail(state.project.id, 'extractSection', sourceId,
      `“${sec.conclusionHeading || 'Conclusion'}”, read out of the PDF: ${sec.conclusion.slice(0, 500)}`);
  }
  if (titleGuessed && record.title) {
    await db.trail(state.project.id, 'guessTitle', sourceId,
      `Title taken from the filename, because the PDF carried no usable metadata: “${record.title}”.`);
  } else if (sec.title && !record.dedupeKeyMatched) {
    await db.trail(state.project.id, 'guessTitle', sourceId,
      `Title read off the first page: “${sec.title}”.`);
  }
}

function similarTitle(a, b) {
  if (!a || !b) return false;
  const norm = s => new Set(s.toLowerCase().split(/[^a-z0-9]+/).filter(w => w.length > 3));
  const x = norm(a), y = norm(b);
  if (!x.size || !y.size) return false;
  const shared = [...x].filter(w => y.has(w)).length;
  return shared / Math.min(x.size, y.size) >= 0.6;
}

/// Tries every free copy of a paper anyone knows about, and says plainly what happened.
/// A browser cannot read a file from a site that does not allow it, so this either works or
/// hands you the link — never a spinner that quietly gives up.
async function getPDF(source) {
  if (source.hasFile) { toast('That one is already here'); return; }
  toast('Looking for a free copy…');
  const result = await retrieve.retrieve(source, { onProgress: toast });

  if (result.ok) {
    const buf = await result.blob.arrayBuffer();
    let sec = {};
    try { sec = await Reader.readSections(new Blob([buf])); } catch {}
    const rec = await db.get('sources', source.id);
    Object.assign(rec, {
      pages: sec.pageCount || rec.pages,
      abstract: rec.abstract || sec.abstract || '',
      conclusion: rec.conclusion || sec.conclusion || '',
      conclusionHeading: rec.conclusionHeading || sec.conclusionHeading || '',
      retrievedFrom: result.from.url,
      retrievedAt: new Date().toISOString(),
    });
    await db.put('sources', rec);
    await db.put('files', { sourceId: source.id, name: `${source.title.slice(0, 60)}.pdf`, blob: result.blob });
    await logExtraction(source.id, sec, rec);
    await refresh();
    scheduleSync();
    toast(`Got it from ${retrieve.host(result.from.url)}`);
    return;
  }

  if (result.reason === 'none') {
    sheet('No free copy found', (body, close) => {
      body.appendChild(el('p', 'meta',
        `Neither OpenAlex nor Unpaywall knows of a legally free PDF of “${source.title}”. That usually means it is behind a paywall.`));
      body.appendChild(el('p', 'meta',
        'Your library may have it. Open the paper\u2019s page, sign in there, download the PDF, then drop it anywhere on this page — it will attach to this record rather than becoming a second copy.'));
      const actions = el('div', 'actions');
      if (source.url) {
        const open = el('button', 'primary', 'Open the paper\u2019s page');
        open.onclick = () => { window.open(source.url, '_blank', 'noopener'); close(); };
        actions.appendChild(open);
      }
      const scholar = el('button', 'quiet', 'Look on Google Scholar');
      scholar.onclick = () => {
        window.open(`https://scholar.google.com/scholar?q=${encodeURIComponent(source.title)}`, '_blank', 'noopener');
        close();
      };
      actions.append(scholar);
      body.appendChild(actions);
    });
    return;
  }

  // Copies exist, but none of their hosts allows a browser on another site to read them.
  sheet('Found it — but the site will not let this page read it', (body, close) => {
    body.appendChild(el('p', 'meta',
      `There ${result.copies.length === 1 ? 'is a free copy' : `are ${result.copies.length} free copies`} of this paper, and every one is on a site that blocks cross-origin reads. That is a rule of the web rather than a limit of this app; the macOS version has no such restriction.`));
    body.appendChild(el('p', 'meta',
      'Open one, save the PDF, and drop it anywhere on this page. It will attach to this record.'));
    for (const c of result.copies.slice(0, 6)) {
      const b = el('button', 'reason wide-link');
      b.textContent = `${retrieve.host(c.url)} — via ${c.from}`;
      b.onclick = () => window.open(c.url, '_blank', 'noopener');
      body.appendChild(b);
    }
    const actions = el('div', 'actions');
    const drop = el('button', 'primary', 'I have the file — choose it');
    drop.onclick = () => { close(); $('#fileInput').click(); };
    actions.appendChild(drop);
    body.appendChild(actions);
  });
}

// ---------------------------------------------------------------- reader

async function openSource(id) {
  const source = state.sources.find(s => s.id === id);
  if (!source) return;
  const file = await db.get('files', id);
  state.openId = id;
  // A filter that hides the paper you just opened is a filter that is wrong about what you
  // are doing. Widen it rather than showing an empty list next to a full reader.
  if (!railPapers().some(s => s.id === id)) {
    state.railFilter = source.hasFile ? 'withPDF' : 'all';
  }
  showReaderHeader(source);
  renderRail();
  if (!file) {
    // A record with no PDF is a normal state — it was found by a search and not retrieved
    // yet — so the reader says so and offers the way out rather than refusing to open.
    reader = null;
    $('#pages').innerHTML = '';
    const box = el('div', 'empty');
    box.appendChild(el('h2', null, 'No PDF stored for this record'));
    box.appendChild(el('p', null, source.pdfURL
      ? 'There is a free PDF for it online. Open it, then drop the file anywhere on this page and it will attach to this record.'
      : 'Drop the file anywhere on this page and it will attach to this record.'));
    if (source.pdfURL) {
      const b = el('button', 'primary', 'Open the free PDF');
      b.onclick = () => window.open(source.pdfURL, '_blank', 'noopener');
      box.appendChild(b);
    }
    $('#pages').appendChild(box);
    renderPalette();
    renderInspector();
    return;
  }
  $('#pages').innerHTML = '<p class="hint" style="padding:20px">Rendering…</p>';
  reader = new Reader($('#pages'));
  reader.onSelectionChange = (geo) => {
    state.selection = geo;
    $('#selectionHint').textContent = geo
      ? `${geo.quote.split(/\s+/).length} words selected`
      : 'Select text, then click a colour or press its number.';
    renderPalette();
  };
  reader.onPageChange = () => showPageLabel();
  await reader.load(file.blob);
  drawEvidence();
  showPageLabel();
  renderPalette();
  renderInspector();
}

function showReaderHeader(source) {
  $('#readerTitle').textContent = source ? source.title : 'No paper open';
  $('#readerByline').textContent = source
    ? [(source.authors || []).slice(0, 3).join(', ') || 'Unknown author', source.year || 'n.d.', source.venue]
        .filter(Boolean).join(' · ')
    : '';
}

function showPageLabel() {
  $('#pageLabel').textContent = reader && reader.pageCount
    ? `${reader.currentPage + 1} / ${reader.pageCount}` : '';
}

// ---------------------------------------------------------------- the reader's paper list

const RAIL_FILTERS = {
  included: (s) => s.stage === 'included',
  withPDF: (s) => s.hasFile,
  marked: (s) => state.evidence.some(e => e.sourceId === s.id),
  all: () => true,
};

/// The reader's own view of the library. "Included" is the default because the point of this
/// screen is the papers that made it into the review.
function railPapers() {
  const q = state.railQuery.toLowerCase();
  return state.sources
    .filter(RAIL_FILTERS[state.railFilter] || RAIL_FILTERS.all)
    .filter(s => !q || (s.title + ' ' + (s.authors || []).join(' ')).toLowerCase().includes(q))
    .sort((a, b) => Number(b.hasFile) - Number(a.hasFile) || a.title.localeCompare(b.title));
}

function renderRail() {
  const list = $('#railList');
  const rows = railPapers();
  $('#railCount').textContent = String(rows.length);
  $('#railFilter').value = state.railFilter;
  list.innerHTML = '';

  if (!rows.length) {
    const box = el('div', 'rail-empty');
    box.appendChild(el('p', 'hint', state.railFilter === 'included'
      ? 'No papers included yet.' : 'Nothing here.'));
    if (state.railFilter !== 'all') {
      const b = el('button', 'quiet', 'Show every paper');
      b.onclick = () => { state.railFilter = 'all'; renderRail(); };
      box.appendChild(b);
    }
    list.appendChild(box);
    return;
  }
  for (const s of rows) {
    const n = state.evidence.filter(e => e.sourceId === s.id).length;
    const row = el('button', 'rail-item');
    row.setAttribute('aria-current', String(s.id === state.openId));
    row.appendChild(el('span', 'rail-title', s.title));
    row.appendChild(el('span', 'meta',
      `${(s.authors || [])[0] || 'Unknown author'} · ${s.year || 'n.d.'}`));
    const chips = el('div', 'chips');
    const st = db.STAGES[s.stage] || db.STAGES.identified;
    chips.appendChild(chip(st.label, st.color));
    if (n) chips.appendChild(chip(String(n), 'var(--amber)'));
    if (!s.hasFile) chips.appendChild(chip('no PDF', 'var(--faint)'));
    row.appendChild(chips);
    row.onclick = () => openSource(s.id);
    list.appendChild(row);
  }
}

function stepPaper(delta) {
  const rows = railPapers();
  if (!rows.length) return;
  const at = rows.findIndex(s => s.id === state.openId);
  const next = rows[(at + delta + rows.length) % rows.length];
  if (next) openSource(next.id);
}

function renderInspector() {
  inspector.render(ctx, {
    evidenceCard: (e, compact) => evidenceCard(e, compact),
    currentPage: () => (reader ? reader.currentPage : 0),
    saveThought: async (t) => {
      const ev = {
        projectId: state.project.id, sourceId: state.openId, page: t.page, rects: [],
        quote: t.quote, color: t.color, tag: t.tag, note: '', stance: t.stance,
        created: new Date().toISOString(),
      };
      ev.id = await db.put('evidence', ev);
      state.evidence.push(ev);
      await refresh();
      renderInspector();
      toast(`${STANCES[t.stance].label} recorded`);
      scheduleSync();
    },
  });
}

function renderPalette() {
  // The stance switch sits above the colours because it changes what the colour MEANS: the
  // same passage marked as interpretation is your thinking, not the source's words, and the
  // app must never let those blur together.
  const stances = $('#stances');
  stances.innerHTML = '';
  for (const [key, s] of Object.entries(STANCES)) {
    const b = el('button', 'swatch');
    b.style.color = s.color;
    b.textContent = s.label;
    b.setAttribute('aria-pressed', String(state.stance === key));
    b.title = s.hint;
    b.onclick = () => { state.stance = key; renderPalette(); };
    stances.appendChild(b);
  }
  $('#stanceBlurb').textContent = STANCES[state.stance].hint;

  const box = $('#palette');
  box.innerHTML = '';
  for (const t of state.tags) {
    const b = el('button', 'swatch');
    b.style.color = t.color;
    const dot = el('span', 'dot'); dot.style.background = t.color;
    b.appendChild(dot);
    b.appendChild(el('span', null, t.name));
    if (t.shortcut) b.appendChild(el('kbd', null, t.shortcut));
    b.disabled = !state.selection;
    b.title = t.detail || '';
    b.onclick = () => highlight(t);
    box.appendChild(b);
  }
  $('#thoughtBtn').disabled = !state.openId;
}

async function highlight(tag) {
  const geo = state.selection;
  if (!geo || !state.openId) { toast('Select some text first'); return; }
  const ev = {
    projectId: state.project.id, sourceId: state.openId, page: geo.page, rects: geo.rects,
    quote: geo.quote, color: tag.color, tag: tag.name, note: '', stance: state.stance,
    created: new Date().toISOString(),
  };
  ev.id = await db.put('evidence', ev);
  state.evidence.push(ev);
  window.getSelection().removeAllRanges();
  state.selection = null;
  renderPalette(); drawEvidence(); renderInspector();
  await refresh();
  scheduleSync();
  toast(`Saved as ${STANCES[state.stance].label.toLowerCase()} · ${tag.name} · page ${geo.page + 1}`);
}

function drawEvidence() {
  if (reader) reader.setEvidence(state.evidence.filter(e => e.sourceId === state.openId));
}

function evidenceCard(e, compact) {
  const source = state.sources.find(s => s.id === e.sourceId);
  const card = el('div', 'card');
  const chips = el('div', 'chips');
  const st = STANCES[e.stance] || STANCES.evidence;
  chips.appendChild(chip(st.label, st.color));
  if (e.tag) chips.appendChild(chip(e.tag, e.color));
  chips.appendChild(el('span', 'meta', `page ${e.page + 1}`));
  card.appendChild(chips);

  const q = el('p', 'quote', e.quote);
  q.style.borderColor = e.color;
  card.appendChild(q);
  if (!compact && source) card.appendChild(el('div', 'meta', source.title));
  if (e.note) card.appendChild(el('div', 'meta', e.note));

  const actions = el('div', 'actions');
  const jump = el('button', 'quiet', 'Find it');
  jump.onclick = async () => {
    if (state.openId !== e.sourceId) await openSource(e.sourceId);
    go('reader');
    setTimeout(() => reader && reader.reveal(e), 250);
  };
  const note = el('button', 'quiet', e.note ? 'Edit note' : 'Add note');
  note.onclick = () => promptFor('Note', 'Why does this matter?', async (v) => {
    if (v == null) return;
    e.note = v; await db.put('evidence', e); await refresh();
    if (state.openId === e.sourceId) renderInspector();
  });
  const rm = el('button', 'quiet danger', 'Delete');
  rm.onclick = async () => {
    await db.del('evidence', e.id);
    state.evidence = state.evidence.filter(x => x.id !== e.id);
    drawEvidence(); renderInspector(); await refresh();
  };
  actions.append(jump, note, rm);
  card.appendChild(actions);
  return card;
}

// ---------------------------------------------------------------- evidence & tags

function renderEvidence() {
  const box = $('#evidenceList');
  const q = ($('#evFilter').value || '').toLowerCase();
  const strip = $('#evStances');
  strip.innerHTML = '';
  strip.style.display = 'flex';
  strip.style.gap = '5px';
  for (const [key, s] of Object.entries(STANCES)) {
    const n = state.evidence.filter(e => (e.stance || 'evidence') === key).length;
    strip.appendChild(chip(`${s.label} ${n}`, s.color));
  }

  box.innerHTML = '';
  const rows = state.evidence.filter(e => !q || e.quote.toLowerCase().includes(q) || (e.note || '').toLowerCase().includes(q));
  if (!rows.length) {
    box.appendChild(el('p', 'hint', state.evidence.length ? 'Nothing matches that.'
      : 'Highlights collect here, each keeping its page, colour, stance and source.'));
    return;
  }
  const byStance = {};
  for (const e of rows) (byStance[e.stance || 'evidence'] ||= []).push(e);
  for (const [key, list] of Object.entries(byStance)) {
    const h = el('h3', 'meta', `${STANCES[key]?.label || key} · ${list.length}`);
    h.style.margin = '6px 0 0';
    box.appendChild(h);
    for (const e of list) box.appendChild(evidenceCard(e, false));
  }
}

function renderTags() {
  const box = $('#tagList');
  box.innerHTML = '';
  for (const t of state.tags) {
    const n = state.evidence.filter(e => e.tag === t.name).length;
    const card = el('div', 'card');
    const head = el('div', 'chips');
    const dot = el('span');
    dot.style.cssText = `width:16px;height:16px;border-radius:4px;background:${t.color}`;
    head.appendChild(dot);
    head.appendChild(el('strong', null, t.name));
    head.appendChild(el('span', 'meta', `${n} highlight${n === 1 ? '' : 's'}`));
    if (t.shortcut) head.appendChild(el('kbd', null, t.shortcut));
    card.appendChild(head);
    if (t.detail) card.appendChild(el('div', 'meta', t.detail));
    const actions = el('div', 'actions');
    const rename = el('button', 'quiet', 'Rename');
    rename.onclick = () => promptFor('Tag name', '', async (v) => {
      if (!v) return;
      const old = t.name; t.name = v; await db.put('tags', t);
      for (const e of state.evidence.filter(e => e.tag === old)) { e.tag = v; await db.put('evidence', e); }
      await refresh();
    });
    const recolour = el('button', 'quiet', 'Colour');
    recolour.onclick = () => promptFor('Hex colour', 'e.g. #4CAF7D', async (v) => {
      if (!v) return;
      t.color = v; await db.put('tags', t);
      for (const e of state.evidence.filter(e => e.tag === t.name)) { e.color = v; await db.put('evidence', e); }
      await refresh(); drawEvidence();
    });
    actions.append(rename, recolour);
    card.appendChild(actions);
    box.appendChild(card);
  }
}

// ---------------------------------------------------------------- settings

function renderSettings(root) {
  root.innerHTML = '';
  const list = el('div', 'list');
  list.appendChild(el('h2', null, 'This review'));

  const fields = [
    ['name', 'Name', 'input'],
    ['question', 'Review question', 'textarea'],
    ['inclusion', 'Include a paper if…', 'textarea'],
    ['exclusion', 'Exclude a paper if…', 'textarea'],
  ];
  for (const [key, label, kind] of fields) {
    const f = el('div', 'field');
    f.appendChild(el('label', null, label));
    const input = el(kind);
    if (kind === 'textarea') input.rows = 2;
    input.value = state.project?.[key] || '';
    input.onchange = async () => {
      state.project[key] = input.value;
      await db.put('projects', state.project);
      await refresh();
    };
    f.appendChild(input);
    list.appendChild(f);
  }
  list.appendChild(el('p', 'hint', 'Screening tints your inclusion terms green and exclusion terms red inside each abstract, so the words a decision turns on are visible before you read a line.'));

  list.appendChild(el('h3', 'section-label', 'What this version leaves out'));
  const gaps = el('div', 'card');
  gaps.appendChild(el('div', 'meta',
    'Two things the browser genuinely cannot do. It cannot search CORE or arXiv, which send no CORS header, or the four databases that need a paid API key — the ones it can reach are listed under Find papers, and the ones it cannot are named there too. And it has no assistant: running one would mean sending your library to somebody else\u2019s computer. What Sieve derives mechanically instead is recorded in the AI trail.'));
  gaps.appendChild(el('div', 'meta',
    'Beyond that the desktop app adds folders and collections, and XLSX and Word export. Everything else — screening, the reader, evidence, the citation map, the matrix, frameworks, PRISMA, methods — is here.'));
  gaps.style.display = 'grid';
  gaps.style.gap = '8px';
  list.appendChild(gaps);
  root.appendChild(list);
}

// ---------------------------------------------------------------- wiring

function wire() {
  for (const b of document.querySelectorAll('.nav')) b.onclick = () => go(b.dataset.view);
  $('#addBtn').onclick = () => $('#fileInput').click();
  $('#fileInput').onchange = (e) => { addFiles([...e.target.files]); e.target.value = ''; };
  $('#filter').oninput = renderLibrary;
  $('#stageFilter').onchange = renderLibrary;
  $('#libraryExport').onclick = () => exportSheet();
  $('#getAllPDFs').onclick = () => getMissingPDFs();
  $('#evFilter').oninput = renderEvidence;
  $('#zoomIn').onclick = () => reader?.setScale(reader.scale + 0.2).then(afterZoom);
  $('#zoomOut').onclick = () => reader?.setScale(reader.scale - 0.2).then(afterZoom);

  // The reader's paper list
  $('#railFilter').onchange = (e) => { state.railFilter = e.target.value; renderRail(); };
  $('#railSearch').oninput = (e) => { state.railQuery = e.target.value; renderRail(); };
  $('#railHide').onclick = () => showRail(false);
  $('#railShow').onclick = () => showRail(true);

  // Find in document
  let findTimer = null;
  $('#findText').oninput = () => {
    clearTimeout(findTimer);
    findTimer = setTimeout(runFind, 220);
  };
  $('#findText').onkeydown = (e) => {
    if (e.key !== 'Enter') return;
    e.preventDefault();
    if (reader?.matches.length) reader.stepMatch(e.shiftKey ? -1 : 1), showFindCount();
    else runFind();
  };
  $('#findPrev').onclick = () => { reader?.stepMatch(-1); showFindCount(); };
  $('#findNext').onclick = () => { reader?.stepMatch(1); showFindCount(); };

  $('#keysBtn').onclick = () => inspector.shortcutSheet(ctx);
  $('#thoughtBtn').onclick = () => inspector.thoughtSheet(ctx, {
    currentPage: () => (reader ? reader.currentPage : 0),
    saveThought: async (t) => {
      const ev = {
        projectId: state.project.id, sourceId: state.openId, page: t.page, rects: [],
        quote: t.quote, color: t.color, tag: t.tag, note: '', stance: t.stance,
        created: new Date().toISOString(),
      };
      ev.id = await db.put('evidence', ev);
      state.evidence.push(ev);
      await refresh();
      renderInspector();
      toast(`${STANCES[t.stance].label} recorded`);
      scheduleSync();
    },
  }, STANCES);
  $('#methodLine').onclick = () => go('method');
  $('#exportEvidence').onclick = () => download('highlights.md', evidenceMarkdown(), 'text/markdown');
  $('#exportCsv').onclick = () => download('highlights.csv', evidenceCsv(), 'text/csv');
  $('#addTag').onclick = () => promptFor('New tag', 'Name', async (name) => {
    if (!name) return;
    await db.put('tags', { projectId: state.project.id, name, color: '#8A93A3', detail: '', shortcut: '' });
    await refresh();
  });

  $('#projectPicker').onclick = () => sheet('Your reviews', (body, close) => {
    body.appendChild(el('p', 'meta',
      'Each review is its own library: its own sources, highlights, matrix, frameworks and PRISMA counts. Nothing crosses between them.'));
    for (const p of state.projects) {
      const mine = p.id === state.project?.id;
      const b = el('button', 'review-row');
      b.setAttribute('aria-current', String(mine));
      const head = el('div', 'project-line');
      head.appendChild(el('strong', null, p.name));
      if (mine) head.appendChild(chip('open', 'var(--accent)'));
      b.appendChild(head);
      if (p.question) b.appendChild(el('div', 'meta', p.question));
      const n = state.allSources.filter(s => s.projectId === p.id).length;
      const h = state.allEvidence.filter(e => e.projectId === p.id).length;
      b.appendChild(el('div', 'meta',
        `${n} source${n === 1 ? '' : 's'} · ${h} highlight${h === 1 ? '' : 's'}`));
      b.onclick = async () => {
        state.project = p;
        await db.put('meta', { key: 'currentProject', value: p.id });
        state.openId = null;
        await refresh(); close(); go('overview');
      };
      body.appendChild(b);
    }
    const actions = el('div', 'actions');
    const add = el('button', 'primary', 'New review');
    add.onclick = () => { close(); promptFor('New review', 'What are you looking into?', async (name) => {
      if (!name) return;
      const id = await db.addProject(name);
      state.projects = await db.all('projects');
      state.project = state.projects.find(p => p.id === id);
      await db.put('meta', { key: 'currentProject', value: id });
      state.openId = null;
      await refresh(); go('settings');
      toast(`“${name}” is now the open review`);
    }); };
    actions.appendChild(add);
    if (state.projects.length > 1) {
      const del = el('button', 'quiet danger', 'Delete this review');
      del.onclick = async () => {
        const doomed = state.project;
        if (!confirm(`Delete “${doomed.name}” and everything in it? Its sources, PDFs and highlights go too.`)) return;
        close();
        for (const name of db.STORES) {
          if (name === 'projects') continue;
          for (const row of await db.all(name)) {
            if (row.projectId !== doomed.id) continue;
            if (name === 'sources') await db.del('files', row.id);
            await db.del(name, row.id ?? row.key);
          }
        }
        await db.del('projects', doomed.id);
        state.projects = await db.all('projects');
        state.project = state.projects[0];
        await db.put('meta', { key: 'currentProject', value: state.project.id });
        state.openId = null;
        await refresh(); go('overview');
        toast('Review deleted');
      };
      actions.appendChild(del);
    }
    body.appendChild(actions);
  });

  $('#exportBtn').onclick = async () => {
    toast('Packing your library…');
    try {
      const blob = await exports.everythingZip(state, { onProgress: toast });
      const day = new Date().toISOString().slice(0, 10);
      downloadBlob(`${(state.project?.name || 'Sieve')} ${day}.zip`.replace(/[^\w .-]/g, ''), blob);
      toast('Backed up — that archive is your whole review, PDFs and all');
    } catch (err) {
      toast(err.message || 'Could not pack the library');
    }
  };
  $('#importBtn').onclick = async () => {
    const handle = await store.savedFolder(db).catch(() => null);
    if (handle && store.folderSupported() &&
        confirm(`Restore from the folder “${handle.name}”?\n\nCancel to pick a backup file instead.`)) {
      try {
        if ((await store.folderPermission(handle)) !== 'granted') await store.reconnectFolder(handle);
        const { index, files } = await store.readFolder(handle);
        await db.importAll({ format: 'sieve-web/1', ...index, files: [] });
        for (const f of files) await db.put('files', f);
        await refresh(); await showSafety();
        toast(`Restored ${index.sources.length} sources`);
      } catch { toast('Could not read that folder'); }
      return;
    }
    $('#jsonInput').click();
  };
  $('#jsonInput').onchange = async (e) => {
    const f = e.target.files[0]; e.target.value = '';
    if (!f) return;
    try {
      if (/\.zip$/i.test(f.name)) await restoreArchive(f);
      else { await db.importAll(JSON.parse(await f.text())); await refresh(); toast('Restored'); }
      await showSafety();
    } catch (err) {
      toast(err.message || 'That file is not a Sieve backup');
    }
  };

  document.addEventListener('keydown', (ev) => {
    if (ev.metaKey || ev.ctrlKey || ev.altKey) return;
    if (/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName)) return;
    if (!$('#modal').classList.contains('hidden')) return;
    if (state.view === 'screening') { if (views.screeningKey(ctx, ev.key.toLowerCase())) ev.preventDefault(); return; }
    if (state.view === 'reader') {
      const tag = state.tags.find(t => t.shortcut === ev.key);
      if (tag && state.selection) { ev.preventDefault(); highlight(tag); return; }
      const k = ev.key.toLowerCase();
      if (k === 'e') { state.stance = 'evidence'; renderPalette(); }
      if (k === 'i') { state.stance = 'interpretation'; renderPalette(); }
      if (k === 'q') { state.stance = 'question'; renderPalette(); }
      if (k === 'j') { ev.preventDefault(); stepPaper(1); }
      if (k === 'k') { ev.preventDefault(); stepPaper(-1); }
      if (ev.key === 'Escape') {
        window.getSelection().removeAllRanges();
        state.selection = null;
        renderPalette();
      }
    }
  });

  let depth = 0;
  window.addEventListener('dragover', e => e.preventDefault());
  window.addEventListener('dragenter', e => { e.preventDefault(); depth++; $('#drop').classList.remove('hidden'); });
  window.addEventListener('dragleave', () => { if (--depth <= 0) $('#drop').classList.add('hidden'); });
  window.addEventListener('drop', async (e) => {
    e.preventDefault(); depth = 0; $('#drop').classList.add('hidden');
    await addFiles([...e.dataTransfer.files]);
  });
}

/// Works through every record with no full text. Slow and public — each one is a request to
/// OpenAlex, Unpaywall and then a repository — so it reports as it goes and can be watched.
async function getMissingPDFs() {
  const missing = state.sources.filter(s => !s.hasFile && s.stage !== 'excludedScreening' && s.stage !== 'duplicate');
  if (!missing.length) { toast('Every record that matters already has its full text'); return; }
  if (!confirm(`Try to fetch ${missing.length} full text${missing.length === 1 ? '' : 's'}?\n\nSieve asks OpenAlex and Unpaywall where a free copy lives and downloads the ones whose hosts allow it. Nothing is uploaded.`)) return;

  let got = 0, blocked = 0, none = 0;
  for (const [i, s] of missing.entries()) {
    toast(`${i + 1} of ${missing.length} · ${got} so far`);
    const result = await retrieve.retrieve(s);
    if (result.ok) {
      const buf = await result.blob.arrayBuffer();
      let sec = {};
      try { sec = await Reader.readSections(new Blob([buf])); } catch {}
      const rec = await db.get('sources', s.id);
      Object.assign(rec, {
        pages: sec.pageCount || rec.pages,
        abstract: rec.abstract || sec.abstract || '',
        conclusion: rec.conclusion || sec.conclusion || '',
        conclusionHeading: rec.conclusionHeading || sec.conclusionHeading || '',
        retrievedFrom: result.from.url, retrievedAt: new Date().toISOString(),
      });
      await db.put('sources', rec);
      await db.put('files', { sourceId: s.id, name: `${s.title.slice(0, 60)}.pdf`, blob: result.blob });
      await logExtraction(s.id, sec, rec);
      got++;
    } else if (result.reason === 'blocked') blocked++;
    else none++;
  }
  await refresh();
  scheduleSync();
  toast(`${got} downloaded · ${blocked} exist but the host blocked us · ${none} with no free copy`);
}

/// Everything Sieve can hand you, in one place, with what each is for.
function exportSheet() {
  sheet('Export', (body, close) => {
    body.appendChild(el('p', 'meta',
      'Nothing here is a format you are stuck inside. The archive holds all of it at once.'));

    const item = (title, detail, label, run) => {
      const card = el('div', 'card export-row');
      const text = el('div');
      text.appendChild(el('h4', null, title));
      text.appendChild(el('div', 'meta', detail));
      card.appendChild(text);
      const b = el('button', 'quiet', label);
      b.onclick = async () => { try { await run(); } catch (e) { toast(e.message || 'That did not work'); } };
      card.appendChild(b);
      body.appendChild(card);
    };

    item('Everything, in one archive',
         'The report, the PDFs, the diagram, every table, BibTeX and RIS, and a full backup.',
         'Download .zip', async () => {
      close();
      toast('Packing everything…');
      const blob = await exports.everythingZip(state, { onProgress: toast });
      downloadBlob(`${(state.project?.name || 'Review').replace(/[^\w -]/g, '')}.zip`, blob);
      toast('Done');
    });

    item('Full review report',
         'The question, criteria, searches, flow diagram, every included paper with its evidence, the matrix, the frameworks and the disclosure. Print it to get a PDF.',
         'Open & print', () => {
      if (!exports.printReport(state)) toast('The browser blocked the new window — allow pop-ups for this page');
      else close();
    });
    item('Full review report as a file',
         'The same document as one HTML file you can keep, mail, or open and print later.',
         'Download .html', () => {
      download(`${(state.project?.name || 'Review')}.html`, exports.reportHTML(state), 'text/html');
      close();
    });

    item('PRISMA flow diagram', 'Vector, for a thesis or a journal figure.', 'SVG', () => {
      download('PRISMA-flow.svg', exports.prismaSVG(state), 'image/svg+xml');
    });
    item('PRISMA flow diagram', 'A 2× raster, for slides and documents that will not take SVG.', 'PNG', async () => {
      downloadBlob('PRISMA-flow.png', await exports.prismaPNG(state));
    });
    item('PRISMA 2020 checklist', 'All 27 items, with what Sieve can already show for each.', 'CSV', () => {
      download('PRISMA-2020-checklist.csv', exports.checklistCSV(state), 'text/csv');
    });

    item('The library as citations', 'For Zotero, Mendeley, EndNote or a LaTeX bibliography.', 'BibTeX', () => {
      download('library.bib', citations.toBibTeX(state.sources), 'application/x-bibtex');
    });
    item('The library as citations', 'The other interchange format.', 'RIS', () => {
      download('library.ris', citations.toRIS(state.sources), 'application/x-research-info-systems');
    });

    item('Tables', 'Sources, highlights, the extraction matrix and the machine-assistance trail.', 'CSVs', () => {
      download('sources.csv', exports.sourcesCSV(state), 'text/csv');
      download('highlights.csv', exports.evidenceCSV(state), 'text/csv');
      download('matrix.csv', exports.matrixCSV(state), 'text/csv');
      download('ai-trail.csv', exports.trailCSV(state), 'text/csv');
      close();
    });
  });
}

/// Puts an archive back: the index, then each PDF by the path the index recorded for it.
async function restoreArchive(file) {
  toast('Reading the archive…');
  const entries = await readZip(file);
  const indexEntry = entries.find(e => /(^|\/)library\.json$/.test(e.name))
                  || entries.find(e => /(^|\/)sieve-backup\.json$/.test(e.name));
  if (!indexEntry) throw new Error('That archive has no Sieve index in it');
  const index = JSON.parse(await indexEntry.blob.text());
  const root = indexEntry.name.replace(/library\.json$|sieve-backup\.json$/, '');

  await db.importAll({ ...index, files: index.files || [] });
  let restored = 0;
  for (const entry of index.pdfManifest || []) {
    const hit = entries.find(e => e.name === root + entry.path);
    if (!hit) continue;
    await db.put('files', {
      sourceId: entry.sourceId, name: entry.name,
      blob: new Blob([hit.blob], { type: 'application/pdf' }),
    });
    restored++;
  }
  await refresh();
  toast(`Restored ${index.sources?.length || 0} sources and ${restored} PDF${restored === 1 ? '' : 's'}`);
}

function downloadBlob(name, blob) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}

function afterZoom() { drawEvidence(); runFind(); }

function showRail(visible) {
  state.railHidden = !visible;
  $('#paperRail').classList.toggle('hidden', !visible);
  $('#railShow').classList.toggle('hidden', visible);
}

function runFind() {
  if (!reader) { $('#findCount').textContent = ''; return; }
  const n = reader.find($('#findText').value);
  $('#findCount').textContent = $('#findText').value.trim().length < 2 ? ''
    : n ? `${reader.matchIndex + 1} / ${n}` : 'none';
}

function showFindCount() {
  if (!reader || !reader.matches.length) return;
  $('#findCount').textContent = `${reader.matchIndex + 1} / ${reader.matches.length}`;
}

function evidenceMarkdown() {
  let out = `# ${state.project?.name || 'Review'} — highlights\n\n`;
  const byTag = {};
  for (const e of state.evidence) (byTag[e.tag || 'Untagged'] ||= []).push(e);
  for (const [tag, list] of Object.entries(byTag)) {
    out += `## ${tag}\n\n`;
    for (const e of list) {
      const s = state.sources.find(x => x.id === e.sourceId);
      out += `> ${e.quote}\n>\n> — ${s ? s.title : 'unknown'}, p.${e.page + 1} · ${STANCES[e.stance]?.label || 'Evidence'}\n\n`;
      if (e.note) out += `${e.note}\n\n`;
    }
  }
  return out;
}

function evidenceCsv() {
  const esc = v => `"${String(v ?? '').replace(/"/g, '""').replace(/\n/g, ' ')}"`;
  const rows = [['Quote', 'Note', 'Tag', 'Stance', 'Page', 'Source', 'Added'].map(esc).join(',')];
  for (const e of state.evidence) {
    const s = state.sources.find(x => x.id === e.sourceId);
    rows.push([e.quote, e.note, e.tag, e.stance, e.page + 1, s ? s.title : '', e.created].map(esc).join(','));
  }
  return rows.join('\n');
}

let toastTimer = null;
function toast(msg) {
  const t = $('#toast');
  t.textContent = msg;
  t.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.add('hidden'), 2800);
}

boot();
