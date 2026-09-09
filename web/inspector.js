// The right-hand panel in the reader: what this paper is, where it came from, and every
// piece of evidence pulled out of it — plus the two sheets the reader opens.
//
// It is three tabs rather than one long column because they answer three different
// questions, and only one of them is ever the one you have. Highlights is what you took
// out; Paper is what it is and where it came from; Decision is whether it stays in.

import * as db from './db.js';
import { el, chip } from './views.js';

let tab = 'highlights';

const TABS = [
  ['highlights', 'Highlights'],
  ['paper', 'Paper'],
  ['decision', 'Decision'],
];

export function render(ctx, io) {
  const tabs = document.querySelector('#inspectorTabs');
  const body = document.querySelector('#inspectorBody');
  const source = ctx.state.sources.find(s => s.id === ctx.state.openId) || null;

  tabs.innerHTML = '';
  for (const [key, label] of TABS) {
    const b = el('button', 'tab', label);
    b.setAttribute('aria-pressed', String(tab === key));
    b.onclick = () => { tab = key; render(ctx, io); };
    tabs.appendChild(b);
  }

  body.innerHTML = '';
  if (!source) {
    body.appendChild(empty('No paper open', 'Pick one from the list on the left.'));
    return;
  }
  if (tab === 'highlights') highlights(ctx, io, body, source);
  else if (tab === 'paper') paper(ctx, io, body, source);
  else decision(ctx, io, body, source);
}

function empty(title, message) {
  const box = el('div', 'empty');
  box.appendChild(el('h2', null, title));
  box.appendChild(el('p', null, message));
  return box;
}

// ---------------------------------------------------------------- highlights

function highlights(ctx, io, body, source) {
  const items = ctx.state.evidence
    .filter(e => e.sourceId === source.id)
    .sort((a, b) => a.page - b.page);

  const head = el('div', 'inspector-head');
  head.appendChild(el('span', 'meta', `${items.length} highlight${items.length === 1 ? '' : 's'}`));
  head.appendChild(el('span', 'grow'));
  const copy = el('button', 'quiet', 'Copy');
  copy.title = 'Copy these highlights';
  copy.disabled = !items.length;
  copy.onclick = () => ctx.sheet('Copy highlights', (sheet, close) => {
    const asQuotes = el('button', 'quiet', 'Copy all as quotes');
    asQuotes.onclick = () => {
      write(items.map(e => `“${e.quote}” (${citeKey(source)}, p.${e.page + 1})`).join('\n\n'), ctx);
      close();
    };
    const asMd = el('button', 'quiet', 'Copy as Markdown');
    asMd.onclick = () => { write(markdown(ctx, source, items), ctx); close(); };
    const actions = el('div', 'actions');
    actions.append(asQuotes, asMd);
    sheet.appendChild(actions);
  });
  head.appendChild(copy);
  body.appendChild(head);

  if (!items.length) {
    body.appendChild(empty('No highlights yet',
      'Select text in the PDF and click a colour above — or press its number key. Each highlight keeps its page, its category, and the paper it came from.'));
    return;
  }
  const list = el('div', 'list compact');
  for (const e of items) list.appendChild(io.evidenceCard(e, true));
  body.appendChild(list);
}

function citeKey(s) {
  const first = (s.authors || [])[0] || '';
  const surname = first.split(/\s+/).pop() || (s.title || '').split(/\s+/)[0] || 'source';
  return `${surname}${s.year || 'n.d.'}`;
}

function markdown(ctx, source, items) {
  let out = `## ${source.title}\n${reference(source)}\n\n`;
  const grouped = {};
  for (const e of items) (grouped[e.tag || 'Untagged'] ||= []).push(e);
  for (const [name, group] of Object.entries(grouped).sort()) {
    out += `### ${name}\n`;
    for (const e of group) {
      out += `- “${e.quote}” (p.${e.page + 1})\n`;
      if (e.note) out += `  - ${e.note}\n`;
    }
    out += '\n';
  }
  return out;
}

function write(text, ctx) {
  navigator.clipboard?.writeText(text)
    .then(() => ctx.toast('Copied'))
    .catch(() => ctx.toast('The browser would not let us reach the clipboard'));
}

/// A plain reference line. Not a citation style — enough to paste into one.
export function reference(s) {
  const authors = (s.authors || []).length
    ? (s.authors.length > 3 ? s.authors[0] + ' et al.' : s.authors.join(', '))
    : 'Unknown author';
  return [authors, `(${s.year || 'n.d.'})`, s.title, s.venue, s.doi ? `https://doi.org/${s.doi}` : '']
    .filter(Boolean).join('. ');
}

// ---------------------------------------------------------------- the paper itself

function paper(ctx, io, body, source) {
  const wrap = el('div', 'list');

  const head = el('div');
  head.appendChild(el('h3', null, source.title));
  head.appendChild(el('div', 'meta', (source.authors || []).join(', ') || 'Unknown author'));
  const line = el('div', 'chips');
  if (source.year) line.appendChild(chip(String(source.year), 'var(--faint)'));
  if (source.venue) line.appendChild(el('span', 'meta', source.venue));
  head.appendChild(line);
  wrap.appendChild(head);

  // Provenance. The whole reason a highlight can be trusted six months later.
  const prov = el('div', 'card');
  prov.appendChild(el('h5', 'section-label', 'Where this came from'));
  const kv = (k, v, href) => {
    if (!v) return;
    const row = el('div', 'kv');
    row.appendChild(el('span', 'k', k));
    if (href) {
      const a = el('a', null, v);
      a.href = href; a.target = '_blank'; a.rel = 'noopener';
      row.appendChild(a);
    } else row.appendChild(el('span', 'v', v));
    prov.appendChild(row);
  };
  kv('Database', source.provider || '—');
  kv('Found by search', source.foundBy);
  kv('Added to review', source.added ? new Date(source.added).toLocaleString() : '');
  kv('DOI', source.doi, source.doi ? `https://doi.org/${source.doi}` : null);
  if (source.url) { try { kv('Source link', new URL(source.url).host, source.url); } catch {} }
  kv('SDG', (source.sdgs || []).join(', '));
  kv('Cited by', source.citedBy ? String(source.citedBy) : '');
  kv('Pages', source.pages ? String(source.pages) : '');
  kv('Works cited', (source.references || []).length ? String(source.references.length) : '');
  kv('PDF stored here', source.hasFile ? 'Yes, in this browser' : 'No');
  wrap.appendChild(prov);

  const copyRef = el('button', 'quiet', 'Copy reference');
  copyRef.onclick = () => write(reference(source), ctx);
  const acts = el('div', 'actions');
  acts.appendChild(copyRef);
  if (source.hasFile) {
    const save = el('button', 'quiet', 'Save the PDF');
    save.onclick = async () => {
      const f = await db.get('files', source.id);
      if (!f) return;
      const url = URL.createObjectURL(f.blob);
      const a = document.createElement('a');
      a.href = url; a.download = f.name || 'paper.pdf'; a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    };
    acts.appendChild(save);
  }
  wrap.appendChild(acts);

  if (source.keywords?.length) {
    const chips = el('div', 'chips');
    for (const k of source.keywords) chips.appendChild(chip(k, 'var(--faint)'));
    wrap.appendChild(chips);
  }

  if (source.abstract) {
    wrap.appendChild(el('h5', 'section-label', 'Abstract'));
    wrap.appendChild(el('p', 'abstract small', source.abstract));
  }

  const field = (label, key, rows, note) => {
    const f = el('div', 'field');
    f.appendChild(el('label', null, label));
    const t = el('textarea');
    t.rows = rows;
    t.value = source[key] || '';
    t.onchange = async () => {
      const rec = await db.get('sources', source.id);
      if (!rec) return;
      rec[key] = t.value;
      await db.put('sources', rec);
      await ctx.refresh();
    };
    f.appendChild(t);
    if (note) f.appendChild(el('p', 'hint', note));
    wrap.appendChild(f);
  };
  field(source.conclusionHeading
          ? `Conclusion — read from the PDF's “${source.conclusionHeading}” section`
          : 'Conclusion — what this paper concludes',
        'conclusion', 5,
        source.conclusion && source.conclusionHeading
          ? 'Pulled out of the file by pattern, not by a person. Check it before you cite it.' : '');
  field('What I still need to read in it', 'toRead', 2);
  field('My notes on this paper', 'notes', 4);

  body.appendChild(wrap);
}

// ---------------------------------------------------------------- the decision

function decision(ctx, io, body, source) {
  const wrap = el('div', 'list');
  const stage = db.STAGES[source.stage] || db.STAGES.identified;

  wrap.appendChild(el('h5', 'section-label', 'Current stage'));
  const now = el('div', 'chips');
  now.appendChild(chip(stage.label, stage.color));
  if (source.reason) now.appendChild(el('span', 'meta', source.reason));
  wrap.appendChild(now);

  const p = ctx.state.project || {};
  if (p.inclusion || p.exclusion) {
    const card = el('div', 'card');
    if (p.inclusion) {
      card.appendChild(el('h5', 'section-label', 'Include if'));
      card.appendChild(el('div', 'meta', p.inclusion));
    }
    if (p.exclusion) {
      card.appendChild(el('h5', 'section-label', 'Exclude if'));
      card.appendChild(el('div', 'meta', p.exclusion));
    }
    wrap.appendChild(card);
  } else {
    const b = el('button', 'quiet', 'Write your inclusion criteria →');
    b.onclick = () => ctx.go('settings');
    wrap.appendChild(b);
  }

  wrap.appendChild(el('h5', 'section-label', 'Full-text decision'));
  const include = el('button', 'primary wide', 'Include in review');
  include.onclick = async () => { await ctx.setStage(source.id, 'included'); ctx.toast('Included in the review'); };
  wrap.appendChild(include);

  const exclude = el('button', 'wide danger', 'Exclude…');
  exclude.onclick = () => ctx.sheet('Why is this excluded?', (sheet, close) => {
    sheet.appendChild(el('p', 'meta',
      'PRISMA requires a reason for every full-text exclusion. It goes straight into your flow diagram.'));
    for (const r of db.EXCLUSION_REASONS) {
      const b = el('button', 'reason', r);
      b.onclick = async () => {
        close();
        await ctx.setStage(source.id, 'excludedFullText', r);
        ctx.toast(`Excluded — ${r}`);
      };
      sheet.appendChild(b);
    }
    const f = el('div', 'field');
    f.appendChild(el('label', null, 'Another reason'));
    const input = el('input');
    f.appendChild(input);
    sheet.appendChild(f);
    const actions = el('div', 'actions');
    const ok = el('button', 'primary', 'Exclude');
    ok.onclick = async () => {
      const v = input.value.trim();
      if (!v) return;
      close();
      await ctx.setStage(source.id, 'excludedFullText', v);
      ctx.toast(`Excluded — ${v}`);
    };
    input.onkeydown = e => { if (e.key === 'Enter') ok.click(); };
    actions.appendChild(ok);
    sheet.appendChild(actions);
  });
  wrap.appendChild(exclude);

  const back = el('button', 'wide', 'Send back to screening');
  back.onclick = async () => { await ctx.setStage(source.id, 'identified'); ctx.toast('Back in the screening queue'); };
  wrap.appendChild(back);

  body.appendChild(wrap);
}

// ---------------------------------------------------------------- the two sheets

/// A thought that is not anchored to a passage. Your own thinking belongs in the corpus —
/// but stored as thinking, never as something the source said.
export function thoughtSheet(ctx, io, STANCES) {
  const source = ctx.state.sources.find(s => s.id === ctx.state.openId);
  if (!source) { ctx.toast('Open a paper first'); return; }
  const page = io.currentPage();
  let stance = 'interpretation';
  let tag = null;

  ctx.sheet('Add a thought', (sheet, close) => {
    sheet.appendChild(el('p', 'meta', `About “${source.title}”`));

    const picker = el('div', 'stance-picker');
    const buttons = {};
    for (const key of ['interpretation', 'question', 'evidence']) {
      const s = STANCES[key];
      const b = el('button', 'stance-option');
      b.style.color = s.color;
      b.appendChild(el('strong', null, s.label));
      b.appendChild(el('span', 'meta', s.hint));
      b.onclick = () => {
        stance = key;
        for (const [k, btn] of Object.entries(buttons)) btn.setAttribute('aria-pressed', String(k === key));
      };
      buttons[key] = b;
      picker.appendChild(b);
    }
    buttons[stance].setAttribute('aria-pressed', 'true');
    sheet.appendChild(picker);

    const f = el('div', 'field');
    f.appendChild(el('label', null, 'What you are thinking'));
    const text = el('textarea');
    text.rows = 5;
    f.appendChild(text);
    sheet.appendChild(f);

    const cat = el('div', 'chips');
    cat.appendChild(el('span', 'meta', 'Category'));
    for (const t of ctx.state.tags) {
      const b = el('button', 'swatch');
      b.style.color = t.color;
      const dot = el('span', 'dot');
      dot.style.background = t.color;
      b.append(dot, el('span', null, t.name));
      b.onclick = () => {
        tag = t;
        for (const other of cat.querySelectorAll('.swatch')) other.setAttribute('aria-pressed', 'false');
        b.setAttribute('aria-pressed', 'true');
      };
      cat.appendChild(b);
    }
    sheet.appendChild(cat);

    const actions = el('div', 'actions');
    actions.appendChild(el('span', 'hint', `Filed against page ${page + 1}`));
    actions.appendChild(el('span', 'grow'));
    const cancel = el('button', 'quiet', 'Cancel');
    cancel.onclick = close;
    const save = el('button', 'primary', 'Save');
    save.onclick = async () => {
      const v = text.value.trim();
      if (!v) return;
      close();
      await io.saveThought({
        page, quote: v, stance,
        tag: tag?.name || '', color: tag?.color || STANCES[stance].color,
      });
    };
    actions.append(cancel, save);
    sheet.appendChild(actions);
    setTimeout(() => text.focus(), 30);
  });
}

export function shortcutSheet(ctx) {
  ctx.sheet('Keys', (sheet) => {
    const rows = [
      ['1 … 8', 'Highlight the selection as that category'],
      ['E', 'Record as evidence — what the source says'],
      ['I', 'Record as interpretation — what you think it means'],
      ['Q', 'Record as a question — what you do not know yet'],
      ['J / K', 'Next / previous paper in the list'],
      ['Esc', 'Drop the selection'],
    ];
    const list = el('div', 'list');
    for (const [key, what] of rows) {
      const row = el('div', 'kv');
      const k = el('kbd', null, key);
      row.appendChild(k);
      row.appendChild(el('span', 'v', what));
      list.appendChild(row);
    }
    sheet.appendChild(list);
    sheet.appendChild(el('p', 'hint',
      'Keys work while the reader is open and nothing is focused in a text field. Screening has its own: I to include, E to exclude, D for duplicate, and the arrow keys to move.'));
  });
}
