// Sieve on the web.
//
// The same argument as the desktop app, in a browser: evidence stays tied to where it came
// from, and the library belongs to whoever is reading it. That second half is why there is no
// login. A sign-in screen implies a server holding your reading, and the moment that exists
// the tool is renting your own research back to you. Everything here is in IndexedDB on this
// machine; "Back up" writes a file you keep.

import * as db from './db.js';
import { Reader } from './reader.js';

const $ = (s) => document.querySelector(s);
const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
};

const state = { sources: [], evidence: [], tags: [], openId: null, activeTag: null, selection: null };
let reader = null;

// ---------------------------------------------------------------- boot

async function boot() {
  state.tags = await db.seed();
  await refresh();
  wire();
  showView('library');
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }
  showStorage();
}

async function refresh() {
  [state.sources, state.evidence] = await Promise.all([db.all('sources'), db.all('evidence')]);
  state.tags = await db.all('tags');
  $('#libraryCount').textContent =
    `${state.sources.length} source${state.sources.length === 1 ? '' : 's'} · ${state.evidence.length} highlight${state.evidence.length === 1 ? '' : 's'}`;
  renderLibrary();
  renderEvidence();
  renderTags();
}

async function showStorage() {
  const u = await db.usage();
  if (!u) return;
  // "10246 MB" is not a quantity anyone reads. Scale the unit.
  const size = (n) => n >= 1073741824 ? `${(n / 1073741824).toFixed(1)} GB`
             : n >= 1048576 ? `${Math.round(n / 1048576)} MB`
             : `${Math.round(n / 1024)} KB`;
  $('#storage').textContent = `${size(u.usage)} used · about ${size(u.quota)} available here.`;
}

// ---------------------------------------------------------------- views

function showView(name) {
  for (const v of document.querySelectorAll('.view')) v.classList.toggle('hidden', v.id !== name);
  for (const b of document.querySelectorAll('.nav')) {
    b.setAttribute('aria-current', String(b.dataset.view === name));
  }
}

// ---------------------------------------------------------------- library

function renderLibrary() {
  const list = $('#sourceList');
  const q = $('#filter').value.toLowerCase();
  const stage = $('#stageFilter').value;
  list.innerHTML = '';

  const rows = state.sources.filter(s => {
    if (stage === 'excluded' ? !String(s.stage).startsWith('excluded') : stage && s.stage !== stage) return false;
    if (!q) return true;
    return (s.title + ' ' + (s.authors || []).join(' ')).toLowerCase().includes(q);
  });

  $('#libraryEmpty').classList.toggle('hidden', state.sources.length > 0);
  for (const s of rows) {
    const n = state.evidence.filter(e => e.sourceId === s.id).length;
    const card = el('div', 'card');
    card.appendChild(el('h4', null, s.title));
    card.appendChild(el('div', 'meta',
      [(s.authors || []).slice(0, 3).join(', ') || 'Unknown author', s.year, s.pages ? `${s.pages} pages` : null]
        .filter(Boolean).join(' · ')));

    const chips = el('div', 'chips');
    chips.appendChild(stageChip(s.stage));
    if (n) { const c = el('span', 'chip', `${n} highlight${n === 1 ? '' : 's'}`); c.style.color = 'var(--amber)'; chips.appendChild(c); }
    for (const k of (s.keywords || []).slice(0, 4)) {
      const c = el('span', 'chip', k); c.style.color = 'var(--faint)'; chips.appendChild(c);
    }
    card.appendChild(chips);

    if (s.abstract) {
      const p = el('p', 'meta', s.abstract.slice(0, 260) + (s.abstract.length > 260 ? '…' : ''));
      p.style.marginTop = '7px';
      card.appendChild(p);
    }
    if (s.conclusion) {
      const d = el('details');
      d.appendChild(el('summary', 'meta', s.conclusionHeading
        ? `The paper's ${s.conclusionHeading.toLowerCase()} — read from the PDF`
        : 'Closing paragraphs — read from the PDF'));
      d.appendChild(el('p', 'meta', s.conclusion.slice(0, 1200)));
      card.appendChild(d);
    }

    const actions = el('div', 'actions');
    const read = el('button', 'primary', 'Read');
    read.onclick = () => openSource(s.id);
    actions.appendChild(read);
    for (const [label, stageValue] of [['Include', 'included'], ['Exclude', 'excludedScreening']]) {
      const b = el('button', 'quiet', label);
      b.onclick = async () => { s.stage = stageValue; await db.put('sources', s); await refresh(); };
      actions.appendChild(b);
    }
    const rm = el('button', 'quiet danger', 'Remove');
    rm.onclick = async () => {
      if (!confirm(`Remove “${s.title}”? Its highlights go too.`)) return;
      for (const e of state.evidence.filter(e => e.sourceId === s.id)) await db.del('evidence', e.id);
      await db.del('files', s.id);
      await db.del('sources', s.id);
      await refresh(); toast('Removed');
    };
    actions.appendChild(rm);
    card.appendChild(actions);
    list.appendChild(card);
  }
}

function stageChip(stage) {
  const map = {
    identified: ['To screen', 'var(--faint)'],
    included: ['Included', 'var(--emerald)'],
    excludedScreening: ['Excluded', 'var(--rose)'],
  };
  const [label, color] = map[stage] || map.identified;
  const c = el('span', 'chip', label);
  c.style.color = color;
  return c;
}

// ---------------------------------------------------------------- import

async function addFiles(files) {
  let added = 0, already = 0;
  for (const file of files) {
    if (!/\.pdf$/i.test(file.name)) continue;
    const buf = await file.arrayBuffer();
    // Same idea as the desktop app: identify by content so re-dropping the same paper does
    // not make a second copy of it.
    const digest = await crypto.subtle.digest('SHA-256', buf.slice(0, 262144));
    const hash = [...new Uint8Array(digest)].slice(0, 12).map(b => b.toString(16).padStart(2, '0')).join('') + '-' + buf.byteLength;
    if (state.sources.some(s => s.fileHash === hash)) { already++; continue; }

    const source = {
      title: file.name.replace(/\.pdf$/i, '').replace(/[_-]+/g, ' '),
      authors: [], year: null, stage: 'identified', fileHash: hash,
      added: new Date().toISOString(), abstract: '', keywords: [], conclusion: '', conclusionHeading: '',
    };
    const id = await db.put('sources', source);
    source.id = id;
    await db.put('files', { sourceId: id, name: file.name, blob: new Blob([buf], { type: 'application/pdf' }) });

    // Read the paper's own title, abstract, keywords and conclusion straight out of the file.
    try {
      const sec = await Reader.readSections(new Blob([buf]));
      Object.assign(source, {
        title: sec.title || source.title,
        abstract: sec.abstract || '', keywords: sec.keywords || [],
        conclusion: sec.conclusion || '', conclusionHeading: sec.conclusionHeading || '',
        pages: sec.pageCount,
      });
      if (!sec.hasText) {
        source.note = 'This PDF is a scan with no text layer — nothing to read or highlight without OCR.';
      }
      await db.put('sources', source);
    } catch (err) {
      console.warn('could not read sections', err);
    }
    added++;
  }
  await refresh();
  toast(added
    ? `Added ${added} PDF${added === 1 ? '' : 's'}${already ? ` · ${already} already here` : ''}`
    : (already ? 'Already in your library — nothing duplicated' : 'No PDFs in that drop'));
  showStorage();
}

// ---------------------------------------------------------------- reader

async function openSource(id) {
  const source = state.sources.find(s => s.id === id);
  const file = await db.get('files', id);
  if (!source || !file) { toast('That file is missing'); return; }
  state.openId = id;
  showView('reader');
  $('#readerTitle').textContent = source.title;
  $('#pages').innerHTML = '<p class="hint" style="padding:20px">Rendering…</p>';

  reader = new Reader($('#pages'));
  reader.onSelectionChange = (geo) => {
    state.selection = geo;
    $('#selectionHint').textContent = geo
      ? `${geo.quote.split(/\s+/).length} words selected — click a colour or press its number.`
      : 'Select text, then click a colour or press its number.';
    renderPalette();
  };
  await reader.load(file.blob);
  drawEvidence();
  renderPalette();
  renderReaderEvidence();
}

function renderPalette() {
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
    b.onclick = () => highlight(t);
    box.appendChild(b);
  }
}

async function highlight(tag) {
  const geo = state.selection;
  if (!geo || !state.openId) { toast('Select some text first'); return; }
  const ev = {
    sourceId: state.openId, page: geo.page, rects: geo.rects, quote: geo.quote,
    color: tag.color, tag: tag.name, note: '', stance: 'evidence',
    created: new Date().toISOString(),
  };
  ev.id = await db.put('evidence', ev);
  state.evidence.push(ev);
  window.getSelection().removeAllRanges();
  state.selection = null;
  renderPalette();
  drawEvidence();
  renderReaderEvidence();
  await refresh();
  toast(`Saved as ${tag.name} · page ${geo.page + 1}`);
}

function drawEvidence() {
  if (!reader) return;
  reader.setEvidence(state.evidence.filter(e => e.sourceId === state.openId));
}

function renderReaderEvidence() {
  const box = $('#readerEvidence');
  box.innerHTML = '';
  const here = state.evidence.filter(e => e.sourceId === state.openId)
    .sort((a, b) => a.page - b.page);
  if (!here.length) {
    box.appendChild(el('p', 'hint', 'Nothing highlighted yet. Each highlight is stored with its page, its colour and the source it came from.'));
    return;
  }
  for (const e of here) box.appendChild(evidenceCard(e, true));
}

function evidenceCard(e, compact) {
  const source = state.sources.find(s => s.id === e.sourceId);
  const card = el('div', 'card');
  const chips = el('div', 'chips');
  const tagChip = el('span', 'chip', e.tag || 'Untagged');
  tagChip.style.color = e.color;
  chips.appendChild(tagChip);
  chips.appendChild(el('span', 'meta', `page ${e.page + 1}`));
  card.appendChild(chips);

  const q = el('p', 'quote', e.quote);
  q.style.borderColor = e.color;
  card.appendChild(q);

  if (!compact && source) {
    card.appendChild(el('div', 'meta', `${source.title} · added ${new Date(e.created).toLocaleDateString()}`));
  }

  const actions = el('div', 'actions');
  const jump = el('button', 'quiet', compact ? 'Find it' : 'Open');
  jump.onclick = async () => {
    if (state.openId !== e.sourceId) { await openSource(e.sourceId); }
    showView('reader');
    setTimeout(() => reader && reader.reveal(e), 250);
  };
  actions.appendChild(jump);

  const note = el('button', 'quiet', e.note ? 'Edit note' : 'Add note');
  note.onclick = async () => {
    const v = prompt('Why does this matter?', e.note || '');
    if (v === null) return;
    e.note = v; await db.put('evidence', e); await refresh();
    if (state.openId === e.sourceId) renderReaderEvidence();
  };
  actions.appendChild(note);

  const rm = el('button', 'quiet danger', 'Delete');
  rm.onclick = async () => {
    await db.del('evidence', e.id);
    state.evidence = state.evidence.filter(x => x.id !== e.id);
    drawEvidence(); renderReaderEvidence(); await refresh();
  };
  actions.appendChild(rm);
  card.appendChild(actions);

  if (e.note) card.appendChild(el('div', 'meta', e.note));
  return card;
}

// ---------------------------------------------------------------- evidence & tags

function renderEvidence() {
  const box = $('#evidenceList');
  const q = ($('#evFilter').value || '').toLowerCase();
  box.innerHTML = '';
  const rows = state.evidence.filter(e => !q || e.quote.toLowerCase().includes(q) || (e.note || '').toLowerCase().includes(q));
  if (!rows.length) {
    box.appendChild(el('p', 'hint', state.evidence.length
      ? 'Nothing matches that.'
      : 'Highlights you make in the reader collect here, each one keeping its page, colour and source.'));
    return;
  }
  const byTag = {};
  for (const e of rows) (byTag[e.tag || 'Untagged'] ||= []).push(e);
  for (const [tag, list] of Object.entries(byTag)) {
    const h = el('h3', 'meta', `${tag} · ${list.length}`);
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
    const dot = el('span', 'dot'); dot.style.cssText = `width:16px;height:16px;border-radius:4px;background:${t.color}`;
    head.appendChild(dot);
    head.appendChild(el('strong', null, t.name));
    head.appendChild(el('span', 'meta', `${n} highlight${n === 1 ? '' : 's'}`));
    card.appendChild(head);
    if (t.detail) card.appendChild(el('div', 'meta', t.detail));
    const actions = el('div', 'actions');
    const rename = el('button', 'quiet', 'Rename');
    rename.onclick = async () => {
      const v = prompt('Tag name', t.name); if (!v) return;
      const old = t.name; t.name = v; await db.put('tags', t);
      for (const e of state.evidence.filter(e => e.tag === old)) { e.tag = v; await db.put('evidence', e); }
      await refresh();
    };
    const recolour = el('button', 'quiet', 'Colour');
    recolour.onclick = async () => {
      const v = prompt('Hex colour', t.color); if (!v) return;
      t.color = v; await db.put('tags', t);
      for (const e of state.evidence.filter(e => e.tag === t.name)) { e.color = v; await db.put('evidence', e); }
      await refresh(); drawEvidence();
    };
    actions.append(rename, recolour);
    card.appendChild(actions);
    box.appendChild(card);
  }
}

// ---------------------------------------------------------------- exports

function download(name, text, type = 'text/plain') {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = document.createElement('a');
  a.href = url; a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function evidenceMarkdown() {
  let out = `# Highlights\n\n_${state.evidence.length} from ${new Set(state.evidence.map(e => e.sourceId)).size} sources, exported ${new Date().toLocaleDateString()}_\n\n`;
  const byTag = {};
  for (const e of state.evidence) (byTag[e.tag || 'Untagged'] ||= []).push(e);
  for (const [tag, list] of Object.entries(byTag)) {
    out += `## ${tag}\n\n`;
    for (const e of list) {
      const s = state.sources.find(x => x.id === e.sourceId);
      out += `> ${e.quote}\n>\n> — ${s ? s.title : 'unknown source'}, p.${e.page + 1}\n\n`;
      if (e.note) out += `${e.note}\n\n`;
    }
  }
  return out;
}

function evidenceCsv() {
  const esc = v => `"${String(v ?? '').replace(/"/g, '""').replace(/\n/g, ' ')}"`;
  const rows = [['Quote', 'Note', 'Tag', 'Page', 'Source', 'Added'].map(esc).join(',')];
  for (const e of state.evidence) {
    const s = state.sources.find(x => x.id === e.sourceId);
    rows.push([e.quote, e.note, e.tag, e.page + 1, s ? s.title : '', e.created].map(esc).join(','));
  }
  return rows.join('\n');
}

// ---------------------------------------------------------------- wiring

function wire() {
  for (const b of document.querySelectorAll('.nav')) b.onclick = () => showView(b.dataset.view);
  $('#addBtn').onclick = () => $('#fileInput').click();
  $('#fileInput').onchange = (e) => { addFiles([...e.target.files]); e.target.value = ''; };
  $('#filter').oninput = renderLibrary;
  $('#stageFilter').onchange = renderLibrary;
  $('#evFilter').oninput = renderEvidence;
  $('#zoomIn').onclick = () => reader && reader.setScale(reader.scale + 0.2).then(drawEvidence);
  $('#zoomOut').onclick = () => reader && reader.setScale(reader.scale - 0.2).then(drawEvidence);
  $('#exportEvidence').onclick = () => download('highlights.md', evidenceMarkdown(), 'text/markdown');
  $('#exportCsv').onclick = () => download('highlights.csv', evidenceCsv(), 'text/csv');

  $('#exportBtn').onclick = async () => {
    toast('Packing your library…');
    const data = await db.exportAll();
    download(`sieve-backup-${new Date().toISOString().slice(0, 10)}.json`,
             JSON.stringify(data), 'application/json');
    toast('Backed up — that file is your whole library');
  };
  $('#importBtn').onclick = () => $('#jsonInput').click();
  $('#jsonInput').onchange = async (e) => {
    const f = e.target.files[0]; e.target.value = '';
    if (!f) return;
    try {
      await db.importAll(JSON.parse(await f.text()));
      await refresh(); toast('Restored');
    } catch (err) { toast('That file is not a Sieve backup'); }
  };
  $('#addTag').onclick = async () => {
    const name = prompt('New tag'); if (!name) return;
    await db.put('tags', { name, color: '#8A93A3', detail: '', shortcut: '' });
    await refresh();
  };

  // Number keys highlight, the same as the desktop app.
  document.addEventListener('keydown', (ev) => {
    if (ev.metaKey || ev.ctrlKey || ev.altKey) return;
    if (/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName)) return;
    const tag = state.tags.find(t => t.shortcut === ev.key);
    if (tag && state.selection) { ev.preventDefault(); highlight(tag); }
  });

  // Drop anywhere.
  let depth = 0;
  window.addEventListener('dragover', e => e.preventDefault());
  window.addEventListener('dragenter', e => { e.preventDefault(); depth++; $('#drop').classList.remove('hidden'); });
  window.addEventListener('dragleave', () => { if (--depth <= 0) $('#drop').classList.add('hidden'); });
  window.addEventListener('drop', async (e) => {
    e.preventDefault(); depth = 0; $('#drop').classList.add('hidden');
    await addFiles([...e.dataTransfer.files]);
  });
}

let toastTimer = null;
function toast(msg) {
  const t = $('#toast');
  t.textContent = msg;
  t.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.add('hidden'), 2600);
}

boot();
