// The trail: everything in this review a machine wrote, and what you decided about it.
//
// The desktop app records what its assistant proposed. The browser has no assistant — there
// is no server to run one on, and adding one would mean sending your library somewhere. But
// the same question still applies, because Sieve still writes sentences into your review
// without you: it pulls an abstract and a conclusion out of a PDF by pattern, guesses a title
// from the first plausible line, attaches OpenAlex's subject labels, and folds two database
// records into one paper.
//
// Every one of those is a machine's claim about a source, and every one can be wrong. A badge
// saying "generated" would be enough to draw a label; it cannot answer the question a
// supervisor or a reviewer actually asks — which sentences came from a machine, and did a
// human check them against the source? This screen is that record. Rows are written once and
// only ever edited to carry your verdict.

import * as db from './db.js';
import { el, chip } from './views.js';

let filter = 'pending';
let query = '';

const FILTERS = [
  ['pending', 'Needs checking'],
  ['all', 'Everything'],
  ['accepted', 'Accepted'],
  ['rejected', 'Rejected'],
  ['edited', 'Edited'],
];

export function pendingCount(state) {
  return state.aiEvents.filter(e => e.outcome === 'pending').length;
}

export function render(ctx, root) {
  const { state } = ctx;
  root.innerHTML = '';

  const bar = el('div', 'bar');
  bar.appendChild(el('strong', null, 'AI trail'));
  const pending = pendingCount(state);
  if (pending) bar.appendChild(chip(`${pending} unchecked`, 'var(--amber)'));
  else if (state.aiEvents.length) bar.appendChild(chip('all checked', 'var(--emerald)'));

  const seg = el('div', 'segmented');
  for (const [key, label] of FILTERS) {
    const b = el('button', 'seg', label);
    b.setAttribute('aria-pressed', String(filter === key));
    b.onclick = () => { filter = key; render(ctx, root); };
    seg.appendChild(b);
  }
  bar.appendChild(seg);

  const search = el('input');
  search.type = 'search';
  search.placeholder = 'Search what it said';
  search.value = query;
  search.oninput = () => { query = search.value; paint(); };
  bar.appendChild(search);

  bar.appendChild(el('span', 'grow'));
  const disclose = el('button', 'quiet', 'Disclosure');
  disclose.onclick = () => ctx.download('ai-use-disclosure.md', disclosure(state), 'text/markdown');
  const csv = el('button', 'quiet', 'CSV');
  csv.onclick = () => ctx.download('ai-trail.csv', trailCsv(state), 'text/csv');
  bar.append(disclose, csv);
  root.appendChild(bar);

  const list = el('div', 'list');
  root.appendChild(list);

  function paint() {
    list.innerHTML = '';
    if (!state.aiEvents.length) {
      list.appendChild(explainer(state));
      return;
    }
    const q = query.toLowerCase();
    const rows = state.aiEvents.filter(e => {
      const passes = filter === 'all' ? true
        : filter === 'pending' ? e.outcome === 'pending'
        : e.outcome === filter;
      if (!passes) return false;
      if (!q) return true;
      const source = state.sources.find(s => s.id === e.sourceId);
      return (e.said || '').toLowerCase().includes(q) || (source?.title || '').toLowerCase().includes(q);
    }).sort((a, b) => String(b.at).localeCompare(String(a.at)));

    if (filter === 'pending' && !rows.length) {
      const ok = el('div', 'card good');
      ok.appendChild(el('h4', null, 'Everything a machine wrote here has been checked'));
      ok.appendChild(el('div', 'meta', 'The disclosure export can state that without qualification.'));
      list.appendChild(ok);
    }
    if (!rows.length && filter !== 'pending') {
      list.appendChild(el('p', 'hint', 'Nothing under that filter.'));
    }
    for (const e of rows) list.appendChild(row(ctx, e, paint));
    list.appendChild(explainer(state));
  }
  paint();
}

function explainer(state) {
  const card = el('div', 'card');
  card.appendChild(el('h4', null,
    state.aiEvents.length ? 'What counts as machine-written here' : 'Nothing machine-written in this review yet'));
  card.appendChild(el('div', 'meta',
    'There is no assistant in the browser version — running one would mean sending your library to somebody else’s computer, and the whole argument of this app is that it never leaves yours. But Sieve still writes into your review without you: it reads an abstract and a conclusion out of a PDF by pattern, guesses a title when the file has no metadata, carries OpenAlex’s subject labels across, and folds two database records into one paper. Each of those is recorded here as a claim to check, and the disclosure export says exactly which were checked and which were not.'));
  return card;
}

function row(ctx, e, repaint) {
  const kind = db.TRAIL_KINDS[e.kind] || { label: e.kind, adjudicate: true, detail: '' };
  const outcome = db.TRAIL_OUTCOMES[e.outcome] || db.TRAIL_OUTCOMES.pending;
  const source = ctx.state.sources.find(s => s.id === e.sourceId);

  const card = el('div', 'card');
  const chips = el('div', 'chips');
  chips.appendChild(chip(kind.label, 'var(--accent)'));
  chips.appendChild(chip(outcome.label, outcome.color));
  chips.appendChild(el('span', 'grow'));
  chips.appendChild(el('span', 'meta', e.at ? new Date(e.at).toLocaleString() : ''));
  card.appendChild(chips);

  if (source) {
    const link = el('button', 'quiet linky', source.title);
    link.onclick = () => { ctx.openSource(source.id); ctx.go('reader'); };
    card.appendChild(link);
  }

  const said = el('p', 'quote');
  said.style.borderColor = 'var(--accent)';
  said.textContent = (e.said || '').slice(0, 600) + ((e.said || '').length > 600 ? '…' : '');
  card.appendChild(said);
  card.appendChild(el('div', 'hint', `${kind.detail} Produced by ${e.by || 'Sieve'}.`));

  if (e.outcome === 'pending') {
    const actions = el('div', 'actions');
    actions.appendChild(el('span', 'meta', 'Checked against the source?'));
    const verdict = (label, value, cls) => {
      const b = el('button', cls || 'quiet', label);
      b.onclick = async () => {
        e.outcome = value;
        e.outcomeAt = new Date().toISOString();
        await db.put('aiEvents', e);
        await ctx.refresh();
        repaint();
      };
      return b;
    };
    actions.append(
      verdict("It's right", 'accepted'),
      verdict('I changed it', 'edited'),
      verdict("It's wrong", 'rejected', 'quiet danger'),
      verdict("Didn't use it", 'unused'),
    );
    card.appendChild(actions);
  }
  return card;
}

// ---------------------------------------------------------------- exports

function disclosure(state) {
  const total = state.aiEvents.length;
  const pending = pendingCount(state);
  const by = (v) => state.aiEvents.filter(e => e.outcome === v).length;
  let out = `# Machine-assistance disclosure\n\n**Review:** ${state.project?.name || 'Review'}\n`;
  out += `**Generated:** ${new Date().toLocaleString()}\n\n`;
  out += `No language model was used in this review. It was carried out in Sieve on the web, which runs entirely in the browser and has no assistant.\n\n`;
  out += `Sieve does derive some text mechanically: abstracts and conclusions read out of PDFs by pattern matching, titles guessed from a page when a file carries no metadata, subject labels carried across from OpenAlex, and database records folded together when they appear to describe one paper. Each such derivation is logged and adjudicated by the researcher.\n\n`;
  out += `- Machine-derived items: **${total}**\n`;
  out += `- Accepted as given: **${by('accepted')}**\n`;
  out += `- Accepted after editing: **${by('edited')}**\n`;
  out += `- Rejected: **${by('rejected')}**\n`;
  out += `- Read but not used: **${by('unused')}**\n`;
  out += `- Not yet checked: **${pending}**\n\n`;
  out += pending
    ? `> ${pending} machine-derived item${pending === 1 ? ' has' : 's have'} not yet been checked against ${pending === 1 ? 'its' : 'their'} source.\n\n`
    : `> Every machine-derived item in this review was checked against its source by the researcher.\n\n`;
  out += `## The record\n\n`;
  for (const e of state.aiEvents) {
    const source = state.sources.find(s => s.id === e.sourceId);
    const kind = db.TRAIL_KINDS[e.kind]?.label || e.kind;
    out += `- ${e.at ? new Date(e.at).toLocaleDateString() : ''} · ${kind} · ${source ? source.title : 'the review'} · ${db.TRAIL_OUTCOMES[e.outcome]?.label || e.outcome}\n`;
  }
  return out;
}

function trailCsv(state) {
  const esc = v => `"${String(v ?? '').replace(/"/g, '""').replace(/\n/g, ' ')}"`;
  const rows = [['When', 'Kind', 'Source', 'What it said', 'Produced by', 'Verdict', 'Checked'].map(esc).join(',')];
  for (const e of state.aiEvents) {
    const source = state.sources.find(s => s.id === e.sourceId);
    rows.push([
      e.at, db.TRAIL_KINDS[e.kind]?.label || e.kind, source?.title || '',
      e.said, e.by, db.TRAIL_OUTCOMES[e.outcome]?.label || e.outcome, e.outcomeAt || '',
    ].map(esc).join(','));
  }
  return rows.join('\n');
}
