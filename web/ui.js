// Shared building blocks for every screen (Sieve 2.1). Screens pass content and a kind;
// the look is decided here once, so an empty Library and an empty Matrix can never drift.
// Every state is shown in catalogue.html.

import { icon } from './icons.js';

const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
};

const ART = { first: 'img/cat-wave.png', find: 'img/cat-find.png', clear: 'img/cat-wave.png', read: 'img/cat-clipboard.svg' };

/// An empty state. kind: 'first' (nothing yet: invite to start), 'nomatch' (a filter hid
/// everything: offer the way back), 'clear' (nothing needs you: no action), 'setup' (one
/// setting missing), 'error' (what failed + retry). placement: 'page' | 'section' | 'panel'.
export function emptyState({ kind = 'first', title, body, art, primary, secondary, placement = 'page' } = {}) {
  const box = el('div', `empty empty-${kind} empty-${placement}`);
  box.setAttribute('role', kind === 'error' ? 'alert' : 'status');
  const pic = art === false ? null : (art || (placement === 'page' && (kind === 'first' || kind === 'clear') ? ART.first : null));
  if (pic) {
    const p = el('div', 'illus'); p.setAttribute('aria-hidden', 'true');
    const img = el('img'); img.src = ART[pic] || pic; img.alt = '';
    p.appendChild(img); box.appendChild(p);
  } else if (kind === 'nomatch' || kind === 'error') {
    const i = el('div', 'empty-icon'); i.setAttribute('aria-hidden', 'true');
    i.innerHTML = icon(kind === 'nomatch' ? 'search' : 'close', 22);
    box.appendChild(i);
  }
  if (title) box.appendChild(el('h2', null, title));
  if (body) (Array.isArray(body) ? body : [body]).forEach(t => box.appendChild(el('p', null, t)));
  if (primary || secondary) {
    const row = el('div', 'empty-actions');
    for (const [a, cls] of [[primary, 'primary'], [secondary, 'quiet']]) {
      if (!a) continue;
      const b = el('button', cls);
      if (a.icon) b.insertAdjacentHTML('afterbegin', icon(a.icon, 16));
      b.appendChild(document.createTextNode(a.label));
      b.onclick = a.onClick;
      row.appendChild(b);
    }
    box.appendChild(row);
  }
  return box;
}

/// A segmented control: one choice among a few, each with an optional count.
/// options: [{ value, label, count }]. Returns the element; onChange(value) on pick.
export function segmented(options, value, onChange, label = 'Show') {
  const seg = el('div', 'segmented');
  seg.setAttribute('role', 'radiogroup');
  seg.setAttribute('aria-label', label);
  for (const o of options) {
    const b = el('button', 'seg');
    b.type = 'button';
    b.setAttribute('role', 'radio');
    b.setAttribute('aria-checked', String(o.value === value));
    b.appendChild(document.createTextNode(o.label));
    if (o.count != null) b.appendChild(el('span', 'n', o.count.toLocaleString()));
    b.onclick = () => { if (o.value !== value) onChange(o.value); };
    seg.appendChild(b);
  }
  return seg;
}

/// "186 records" or "12 of 186 records", with the right plural, for list toolbars.
export function countLabel(shown, total, noun = ['record', 'records']) {
  const n = (k) => `${k.toLocaleString()} ${k === 1 ? noun[0] : noun[1]}`;
  return shown === total ? n(total) : `${shown.toLocaleString()} of ${n(total)}`;
}

/// A quiet toolbar button with an icon that never wraps its label.
export function toolButton(label, iconName, onClick, title) {
  const b = el('button', 'quiet tool-btn');
  b.type = 'button';
  if (iconName) b.insertAdjacentHTML('afterbegin', icon(iconName, 16));
  b.appendChild(el('span', 'lbl', label));
  if (title) b.title = title;
  b.onclick = onClick;
  return b;
}

/// A real checkbox row (for pickers), instead of a text tick.
export function checkRow(label, checked, onChange, detail) {
  const row = el('label', 'check-row');
  const box = el('input'); box.type = 'checkbox'; box.checked = checked;
  box.onchange = () => onChange(box.checked);
  const text = el('span', 'check-text', label);
  row.append(box, text);
  if (detail) row.appendChild(el('span', 'meta', detail));
  return row;
}
