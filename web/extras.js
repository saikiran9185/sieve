// The things around the work (Sieve 2.0): a ⌘K command palette, the first-run welcome and
// the keyboard-shortcuts sheet. They take the app context and only call what the app already
// exposes, so none of them owns any state of the library.

import { icon, NAV_ICONS } from './icons.js';

const $ = (s) => document.querySelector(s);
const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
};

// ---------------------------------------------------------------- command palette

let paletteEl = null;

function screens() {
  return [...document.querySelectorAll('.nav[data-view]')].map(b => ({
    group: 'Go to',
    label: b.childNodes[b.childNodes.length > 1 ? 1 : 0]?.textContent?.trim() || b.dataset.view,
    icon: NAV_ICONS[b.dataset.view] || 'arrowRight',
    run: () => b.click(),
  }));
}

function actions(ctx) {
  const click = (sel) => () => $(sel)?.click();
  return [
    { group: 'Actions', label: 'Add PDFs or citations', icon: 'upload', run: click('#addBtn') },
    { group: 'Actions', label: 'Switch review', icon: 'chevronsUpDown', run: click('#projectPicker') },
    { group: 'Actions', label: 'Back up the library', icon: 'download', run: click('#exportBtn') },
    { group: 'Actions', label: 'Restore from a backup', icon: 'folder', run: click('#importBtn') },
    { group: 'Actions', label: 'Switch colour theme', icon: 'contrast', run: click('#themeBtn') },
    { group: 'Actions', label: 'Account and sync', icon: 'user', run: click('#accountBtn') },
    { group: 'Actions', label: 'Keyboard shortcuts', icon: 'keyboard', run: () => shortcuts(ctx) },
  ];
}

function papers(ctx) {
  return (ctx.state.sources || []).map(s => ({
    group: 'Papers',
    label: s.title,
    detail: [s.authors?.[0], s.year].filter(Boolean).join(' · '),
    icon: s.hasFile ? 'book' : 'file',
    run: () => {
      if (s.hasFile) { ctx.openSource(s.id); ctx.go('reader'); }
      else ctx.go('library');
    },
  }));
}

export function openPalette(ctx) {
  if (paletteEl) return;
  const all = [...screens(), ...actions(ctx), ...papers(ctx)];
  paletteEl = el('div', 'cmdk');
  paletteEl.setAttribute('role', 'dialog');
  paletteEl.setAttribute('aria-label', 'Search Sieve');
  const box = el('div', 'cmdk-box');
  const field = el('div', 'cmdk-field');
  field.innerHTML = icon('search');
  const input = el('input');
  input.type = 'text';
  input.placeholder = 'Search papers, screens and actions';
  input.setAttribute('aria-label', 'Search');
  input.setAttribute('role', 'combobox');
  input.setAttribute('aria-expanded', 'true');
  input.setAttribute('aria-controls', 'cmdkList');
  field.appendChild(input);
  field.appendChild(el('kbd', null, 'esc'));
  const list = el('div', 'cmdk-list');
  list.id = 'cmdkList';
  list.setAttribute('role', 'listbox');
  box.append(field, list);
  paletteEl.appendChild(box);
  document.body.appendChild(paletteEl);

  let shown = [];
  let active = 0;
  const draw = () => {
    const q = input.value.trim().toLowerCase();
    const words = q.split(/\s+/).filter(Boolean);
    const hit = (t) => words.every(w => t.toLowerCase().includes(w));
    if (words.length) shown = all.filter(x => hit(`${x.label} ${x.detail || ''}`)).slice(0, 40);
    else {
      // Nothing typed: every screen and action, plus the five most recent papers.
      const ps = all.filter(x => x.group === 'Papers').slice(-5).reverse();
      shown = [...all.filter(x => x.group !== 'Papers'), ...ps];
    }
    active = Math.min(active, Math.max(0, shown.length - 1));
    list.innerHTML = '';
    if (!shown.length) { list.appendChild(el('p', 'cmdk-empty', 'Nothing matches. Try a title, an author or a screen name.')); return; }
    let group = '';
    shown.forEach((x, i) => {
      if (x.group !== group) { group = x.group; list.appendChild(el('div', 'cmdk-group', group)); }
      const row = el('button', 'cmdk-item');
      row.setAttribute('role', 'option');
      row.setAttribute('aria-selected', String(i === active));
      row.innerHTML = icon(x.icon);
      const text = el('span', 'cmdk-text');
      text.appendChild(el('span', 'cmdk-label', x.label));
      if (x.detail) text.appendChild(el('span', 'cmdk-detail', x.detail));
      row.appendChild(text);
      row.onmousemove = () => { if (active !== i) { active = i; mark(); } };
      row.onclick = () => choose(i);
      list.appendChild(row);
    });
  };
  const mark = () => {
    [...list.querySelectorAll('.cmdk-item')].forEach((r, i) => r.setAttribute('aria-selected', String(i === active)));
    list.querySelectorAll('.cmdk-item')[active]?.scrollIntoView({ block: 'nearest' });
  };
  const choose = (i) => { const x = shown[i]; closePalette(); x?.run(); };

  input.oninput = () => { active = 0; draw(); };
  input.onkeydown = (e) => {
    if (e.key === 'ArrowDown') { e.preventDefault(); active = Math.min(active + 1, shown.length - 1); mark(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); active = Math.max(active - 1, 0); mark(); }
    else if (e.key === 'Enter') { e.preventDefault(); choose(active); }
    else if (e.key === 'Escape') { e.preventDefault(); closePalette(); }
  };
  paletteEl.onclick = (e) => { if (e.target === paletteEl) closePalette(); };
  draw();
  input.focus();
}

export function closePalette() {
  if (!paletteEl) return;
  paletteEl.remove();
  paletteEl = null;
}

// ---------------------------------------------------------------- shortcuts

export function shortcuts(ctx) {
  ctx.sheet('Keyboard shortcuts', (sheet) => {
    const groups = [
      ['Anywhere', [['⌘ K', 'Search papers, screens and actions'], ['?', 'This list']]],
      ['Screening', [['F', 'Keep (or include, at full text)'], ['1 … 9', 'Exclude with that reason'], ['J / K', 'Next / previous record']]],
      ['Reader', [['1 … 8', 'Highlight the selection as that category'], ['E · I · Q', 'Record as evidence, interpretation or a question'],
                  ['J / K', 'Next / previous paper'], ['Esc', 'Drop the selection']]],
    ];
    for (const [title, rows] of groups) {
      sheet.appendChild(el('h3', 'keys-group', title));
      for (const [key, what] of rows) {
        const row = el('div', 'kv');
        row.appendChild(el('kbd', null, key));
        row.appendChild(el('span', 'v', what));
        sheet.appendChild(row);
      }
    }
    sheet.appendChild(el('p', 'hint', 'Keys work when no text field is focused.'));
  });
}

// ---------------------------------------------------------------- first-run welcome

const WELCOME_KEY = 'sieve-welcomed';
const STEPS = [
  { img: 'img/cat-wave.png', title: 'You do the research.', body: 'Sieve keeps it together: every search, decision, passage and idea stays tied to its source.' },
  { img: 'img/cat-find.png', title: 'Find, then screen.', body: 'Search seven databases at once. Keep or exclude each record with a reason, and PRISMA counts itself.' },
  { img: 'img/cat-clipboard.svg', title: 'Read with proof.', body: 'Highlight in the PDF. Each passage keeps its page and paper, so your matrix and report can always point back.' },
];

export function maybeWelcome(ctx) {
  let seen = false;
  try { seen = !!localStorage.getItem(WELCOME_KEY); } catch { seen = true; }
  if (seen || (ctx.state.sources || []).length) return;
  // Wait until the sign-in screen (if any) is out of the way.
  const auth = document.getElementById('auth');
  if (auth && !auth.hidden) { setTimeout(() => maybeWelcome(ctx), 800); return; }
  welcome(ctx);
}

export function welcome(ctx) {
  let i = 0;
  ctx.sheet('', (sheet, close) => {
    sheet.classList.add('welcome');
    sheet.querySelector('h2')?.remove();
    const done = () => { try { localStorage.setItem(WELCOME_KEY, '1'); } catch { /* fine */ } close(); };
    const draw = () => {
      const s = STEPS[i];
      sheet.innerHTML = '';
      const pic = el('div', 'illus welcome-illus');
      const img = el('img'); img.src = s.img; img.alt = '';
      pic.appendChild(img);
      sheet.appendChild(pic);
      sheet.appendChild(el('h2', null, s.title));
      sheet.appendChild(el('p', 'note', s.body));
      const dots = el('div', 'welcome-dots');
      STEPS.forEach((_, k) => { const d = el('span'); if (k === i) d.className = 'on'; dots.appendChild(d); });
      const actions = el('div', 'actions');
      const skip = el('button', 'quiet', i < STEPS.length - 1 ? 'Skip' : 'Close');
      skip.onclick = done;
      const next = el('button', 'primary', i < STEPS.length - 1 ? 'Next' : 'Find papers');
      next.onclick = () => {
        if (i < STEPS.length - 1) { i++; draw(); }
        else { done(); ctx.go('find'); }
      };
      actions.append(dots, el('span', 'grow'), skip, next);
      sheet.appendChild(actions);
      next.focus();
    };
    draw();
  });
}

// ---------------------------------------------------------------- keys

export function wireExtras(ctx) {
  document.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      paletteEl ? closePalette() : openPalette(ctx);
      return;
    }
    if (paletteEl) return;
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName) || document.activeElement?.isContentEditable;
    if (!typing && e.key === '?' && document.getElementById('modal')?.classList.contains('hidden')) {
      e.preventDefault();
      shortcuts(ctx);
    }
  });
  $('#paletteBtn')?.addEventListener('click', () => openPalette(ctx));
}
