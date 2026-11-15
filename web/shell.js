// The frame around the screens (Sieve 2.0 redesign): page titles, the phone menu and tab
// bar, and the colour theme. It only watches and clicks the sidebar's own buttons, so the
// app's navigation stays the single source of truth.

import { icon, NAV_ICONS } from './icons.js';

const $ = (s) => document.querySelector(s);
const body = document.body;

const TITLES = {
  overview: ['Overview', ''],
  find: ['Find papers', 'Seven databases, one query'],
  library: ['Library', 'Every record in this review'],
  screening: ['Screening', 'Keep or exclude, with a reason for every exclusion'],
  reader: ['Reader', ''],
  evidence: ['Evidence', 'Every highlight, with its page and source'],
  map: ['Map', 'How your papers cite one another'],
  matrix: ['Matrix', 'Included papers against the questions you ask of each'],
  frames: ['Frameworks', 'Analysis grids that cite their evidence'],
  prisma: ['PRISMA', 'PRISMA 2020 flow, counted from your decisions'],
  trail: ['AI trail', 'Everything the assistant suggested, and what you decided'],
  method: ['Method', 'The steps your review follows'],
  tags: ['Tags', 'Highlight colours and what they mean'],
  settings: ['Settings', ''],
  guide: ['Guide', 'How to run a review in Sieve'],
};

// ---------------------------------------------------------------- icons
function fillIcons(root = document) {
  for (const n of root.querySelectorAll('[data-icon]:not([data-filled])')) {
    n.insertAdjacentHTML('afterbegin', icon(n.dataset.icon));
    n.dataset.filled = '1';
  }
}
for (const b of document.querySelectorAll('.nav[data-view]')) {
  const name = NAV_ICONS[b.dataset.view];
  if (name && !b.querySelector('.ico')) b.insertAdjacentHTML('afterbegin', icon(name));
}
fillIcons();

let lastView = null;
function currentView() {
  return $('.nav[aria-current="true"]')?.dataset.view || 'overview';
}

function sync() {
  const v = currentView();
  body.dataset.view = v;
  // A short fade as a screen arrives, so the switch reads as movement, not a flash.
  if (v !== lastView) {
    const sec = document.getElementById(v);
    if (sec) { sec.classList.remove('view-enter'); void sec.offsetWidth; sec.classList.add('view-enter'); }
    lastView = v;
  }
  const [t, sub] = TITLES[v] || [v, ''];
  // Overview is titled with the review's own name: it is the review's home.
  const title = v === 'overview' ? ($('#projectName')?.textContent?.trim() || 'Overview') : t;
  $('#pageTitle').textContent = title;
  $('#pageSub').textContent = sub;
  document.title = v === 'overview' ? `${title} · Sieve` : `${t} · Sieve`;
  for (const b of document.querySelectorAll('#tabbar [data-go]')) {
    const on = b.dataset.go === v || (b.dataset.go === 'more' && !['overview', 'find', 'screening', 'reader'].includes(v));
    b.setAttribute('aria-current', String(on));
  }
}

// Watch the sidebar: whatever changes the current view (a click, a keyboard shortcut, a
// link inside a screen) moves aria-current there first.
const navObserver = new MutationObserver(sync);
for (const b of document.querySelectorAll('.nav')) navObserver.observe(b, { attributes: true, attributeFilter: ['aria-current'] });
const nameEl = $('#projectName');
if (nameEl) new MutationObserver(sync).observe(nameEl, { childList: true, characterData: true, subtree: true });
sync();

// ---------------------------------------------------------------- phone drawer
const openDrawer = () => { body.classList.add('drawer-open'); $('#drawerClose')?.focus(); };
const closeDrawer = () => body.classList.remove('drawer-open');
$('#menuBtn')?.addEventListener('click', openDrawer);
$('#drawerClose')?.addEventListener('click', closeDrawer);
$('#scrim')?.addEventListener('click', closeDrawer);
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && body.classList.contains('drawer-open')) closeDrawer(); });
$('#sidebar')?.addEventListener('click', (e) => {
  if (e.target.closest('.nav, #addBtn, #projectPicker, #accountBtn, #methodLine')) closeDrawer();
});

for (const b of document.querySelectorAll('#tabbar [data-go]')) {
  b.addEventListener('click', () => {
    const v = b.dataset.go;
    if (v === 'more') { openDrawer(); return; }
    document.querySelector(`.nav[data-view="${v}"]`)?.click();
  });
}

// ---------------------------------------------------------------- theme
const root = document.documentElement;
const order = ['auto', 'light', 'dark'];
const read = () => { try { return localStorage.getItem('sieve-theme') || 'auto'; } catch { return 'auto'; } };
function applyTheme(t) {
  if (t === 'auto') delete root.dataset.theme; else root.dataset.theme = t;
  const btn = $('#themeBtn');
  if (btn) btn.textContent = `Theme: ${t}`;
  try { localStorage.setItem('sieve-theme', t); } catch { /* private mode: keep it for this visit */ }
}
applyTheme(read());
$('#themeBtn')?.addEventListener('click', () => applyTheme(order[(order.indexOf(read()) + 1) % order.length]));
