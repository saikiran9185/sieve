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
  // The label as a tooltip, for the icon-only sidebar at in-between widths.
  const label = [...b.childNodes].find(n => n.nodeType === 3 && n.textContent.trim());
  if (label && !b.title) b.title = label.textContent.trim();
  // Wrap the bare text so CSS can hide it in the icon rail without hiding the icon.
  if (label) { const s = document.createElement('span'); s.className = 'lbl'; s.textContent = label.textContent; label.replaceWith(s); }
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
  if (e.target.closest('.nav, #addBtn, #projectPicker, #accountBtn, #methodLine, #exportBtn, #importBtn')) closeDrawer();
});

for (const b of document.querySelectorAll('#tabbar [data-go]')) {
  b.addEventListener('click', () => {
    const v = b.dataset.go;
    if (v === 'more') { openDrawer(); return; }
    document.querySelector(`.nav[data-view="${v}"]`)?.click();
  });
}

// ---------------------------------------------------------------- theme
// Auto follows the system; Light and Dark pin it. Set in the profile menu or with ⌘K.
const root = document.documentElement;
const THEMES = ['auto', 'light', 'dark'];
const readTheme = () => { try { return localStorage.getItem('sieve-theme') || 'auto'; } catch { return 'auto'; } };
export function applyTheme(t) {
  if (t === 'auto') delete root.dataset.theme; else root.dataset.theme = t;
  for (const b of document.querySelectorAll('[data-theme-set]')) b.setAttribute('aria-checked', String(b.dataset.themeSet === t));
  const dark = t === 'dark' || (t === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
  for (const m of document.querySelectorAll('meta[name="theme-color"]')) m.content = dark ? '#1E1B19' : '#FFFFFF';
  try { localStorage.setItem('sieve-theme', t); } catch { /* private mode: keep it for this visit */ }
}
export function cycleTheme() { applyTheme(THEMES[(THEMES.indexOf(readTheme()) + 1) % THEMES.length]); }
applyTheme(readTheme());
for (const b of document.querySelectorAll('[data-theme-set]')) b.addEventListener('click', () => applyTheme(b.dataset.themeSet));

// ---------------------------------------------------------------- profile menu
// Everything about the person and their copy of the library, rarely needed, lives here:
// account and sync, theme, backup and restore, storage safety, and the setup screens.
const profileBtn = $('#profileBtn'), profileMenu = $('#profileMenu');
function setMenu(open) {
  if (!profileMenu) return;
  profileMenu.hidden = !open;
  profileBtn.setAttribute('aria-expanded', String(open));
  if (open) profileMenu.querySelector('button:not([hidden])')?.focus({ preventScroll: true });
}
profileBtn?.addEventListener('click', (e) => { e.stopPropagation(); setMenu(profileMenu.hidden); });
document.addEventListener('click', (e) => {
  if (!profileMenu || profileMenu.hidden) return;
  if (!e.target.closest('#profileMenu')) setMenu(false);
  else if (e.target.closest('button') && !e.target.closest('[data-theme-set], #syncLine')) setMenu(false);
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && profileMenu && !profileMenu.hidden) { setMenu(false); profileBtn.focus(); }
});

// The profile button mirrors the account button (auth.js fills it) and the sync status.
function mirrorAccount() {
  const name = $('#accountBtn .acct-name')?.textContent?.trim();
  const signedIn = !!name && name.includes('@');
  $('#profileName').textContent = signedIn ? name : 'Not signed in';
  $('#profileAvatar').textContent = signedIn ? name[0].toUpperCase() : '';
  $('#profileAvatar').classList.toggle('empty', !signedIn);
  if (!signedIn) $('#profileState').textContent = 'Saved in this browser';
}
const acct = $('#accountBtn');
if (acct) new MutationObserver(mirrorAccount).observe(acct, { childList: true, subtree: true });
mirrorAccount();
window.addEventListener('sieve:sync-status', (e) => {
  const words = { syncing: 'Syncing…', synced: 'Synced', pending: 'Changes waiting', offline: 'Offline', error: 'Sync paused' };
  const st = e.detail?.state;
  if (!st || st === 'off') return;
  $('#profileState').textContent = words[st] || '';
  profileBtn.dataset.sync = st;
});
