// The screens beyond reading: overview, finding papers, screening, the matrix, frameworks
// and PRISMA. Each takes the app context rather than reaching for globals, so the shell owns
// state and these only render and act on it.

import * as db from './db.js';
import { PROVIDERS, BLOCKED, searchAll, dedupeKey } from './search.js';
import { EXTERNAL_SITES, siteURL } from './citations.js';

export const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
};
export const chip = (text, color) => {
  const c = el('span', 'chip', text);
  if (color) c.style.color = color;
  return c;
};

// ---------------------------------------------------------------- overview

export function renderOverview(ctx, root) {
  const { state, go } = ctx;
  const p = prismaCounts(state);
  root.innerHTML = '';
  const wrap = el('div', 'list');

  const head = el('div');
  head.appendChild(el('h2', null, state.project?.name || 'Review'));
  if (state.project?.question) {
    const q = el('p', 'abstract', state.project.question);
    q.style.margin = '4px 0 0';
    head.appendChild(q);
  } else {
    const b = el('button', 'quiet', 'Write your review question →');
    b.onclick = () => go('settings');
    head.appendChild(b);
  }
  wrap.appendChild(head);

  const stats = el('div', 'stats');
  const add = (n, label, view) => {
    const s = el('button', 'stat');
    s.appendChild(el('b', null, String(n)));
    s.appendChild(el('span', null, label));
    s.onclick = () => go(view);
    stats.appendChild(s);
  };
  add(p.identified, 'Records found', 'library');
  add(p.toScreen, 'Still to screen', 'screening');
  add(state.sources.filter(s => s.hasFile).length, 'Full texts', 'library');
  add(state.evidence.length, 'Highlights', 'evidence');
  add(p.included, 'Included', 'prisma');
  wrap.appendChild(stats);

  const gaps = findGaps(state, p);
  if (gaps.length) {
    wrap.appendChild(el('h3', 'meta', 'What needs attention'));
    for (const g of gaps) {
      const card = el('button', 'card gap');
      card.style.cssText += 'width:100%;text-align:left;cursor:pointer';
      const n = el('div', 'n', String(g.count));
      n.style.color = g.color;
      card.appendChild(n);
      const body = el('div');
      body.appendChild(el('h4', null, g.title));
      body.appendChild(el('div', 'meta', g.detail));
      card.appendChild(body);
      card.onclick = () => go(g.view);
      wrap.appendChild(card);
    }
  } else if (state.sources.length) {
    const ok = el('div', 'card');
    ok.appendChild(el('h4', null, 'Nothing outstanding'));
    ok.appendChild(el('div', 'meta', 'Every record is screened and every included paper has a full text.'));
    wrap.appendChild(ok);
  }

  if (!state.sources.length) {
    const empty = el('div', 'card');
    empty.appendChild(el('h4', null, 'Start by finding papers'));
    empty.appendChild(el('div', 'meta', 'Search seven databases at once, or drop PDFs you already have anywhere on this page.'));
    const b = el('button', 'primary', 'Find papers');
    b.style.marginTop = '9px';
    b.onclick = () => go('find');
    empty.appendChild(b);
    wrap.appendChild(empty);
  }
  root.appendChild(wrap);
}

function findGaps(state, p) {
  const out = [];
  const unscreened = state.sources.filter(s => s.stage === 'identified').length;
  if (unscreened) out.push({ count: unscreened, title: 'Records not yet screened',
    detail: 'PRISMA cannot be final while records have no decision.', view: 'screening', color: 'var(--rose)' });
  const noReason = state.sources.filter(s => s.stage === 'excludedFullText' && !s.reason).length;
  if (noReason) out.push({ count: noReason, title: 'Full-text exclusions with no reason',
    detail: 'PRISMA requires a reason for each one.', view: 'screening', color: 'var(--rose)' });
  const noPdf = state.sources.filter(s => s.stage === 'included' && !s.hasFile).length;
  if (noPdf) out.push({ count: noPdf, title: 'Included papers with no full text',
    detail: 'You cannot assess what you have not got.', view: 'library', color: 'var(--amber)' });
  const unread = state.sources.filter(s => s.stage === 'included' && s.hasFile &&
    !state.evidence.some(e => e.sourceId === s.id)).length;
  if (unread) out.push({ count: unread, title: 'Included papers with no highlights',
    detail: 'Nothing has been taken out of them yet.', view: 'reader', color: 'var(--amber)' });
  return out;
}

// ---------------------------------------------------------------- PRISMA

export function prismaCounts(state) {
  const s = state.sources;
  const n = f => s.filter(f).length;
  const identified = s.length;
  const duplicates = n(x => x.stage === 'duplicate');
  const screened = identified - duplicates;
  const excludedScreening = n(x => x.stage === 'excludedScreening');
  const toScreen = n(x => x.stage === 'identified');
  // Retrieval is a fact about the disk, as on the desktop: a record with no PDF was not
  // obtained, whatever the screening said.
  const past = x => ['sought', 'excludedFullText', 'included'].includes(x.stage);
  const sought = n(past) + n(x => x.stage === 'notRetrieved');
  const notRetrieved = n(x => x.stage === 'notRetrieved') + n(x => past(x) && !x.hasFile);
  const assessed = n(x => past(x) && x.hasFile);
  const excludedFullText = n(x => x.stage === 'excludedFullText' && x.hasFile);
  const included = n(x => x.stage === 'included' && x.hasFile);
  const reasons = {};
  for (const x of s) {
    if (x.stage !== 'excludedFullText') continue;
    const r = x.reason || 'Reason not recorded';
    reasons[r] = (reasons[r] || 0) + 1;
  }
  const bySource = {};
  for (const x of s) {
    const k = x.provider || 'Added by hand';
    bySource[k] = (bySource[k] || 0) + 1;
  }
  return { identified, duplicates, screened, excludedScreening, toScreen, sought,
           notRetrieved, assessed, excludedFullText, included, reasons, bySource };
}

export function renderPrisma(ctx, root) {
  const { state } = ctx;
  const p = prismaCounts(state);
  root.innerHTML = '';

  const bar = el('div', 'bar');
  bar.appendChild(el('strong', null, 'PRISMA 2020 flow'));
  bar.appendChild(el('span', 'meta', 'counted from your decisions'));
  bar.appendChild(el('span', 'grow'));
  const exp = el('button', 'quiet', 'Export…');
  exp.onclick = () => ctx.exportSheet();
  bar.appendChild(exp);
  const txt = el('button', 'quiet', 'Text');
  txt.onclick = () => ctx.download('PRISMA-flow.txt', prismaText(state, p));
  bar.appendChild(txt);
  root.appendChild(bar);

  const list = el('div', 'list');
  if (p.toScreen) {
    const warn = el('div', 'card');
    warn.style.borderColor = 'var(--amber)';
    warn.appendChild(el('h4', null, `${p.toScreen} records have no decision yet`));
    warn.appendChild(el('div', 'meta', 'They count as identified but appear in no box below, so this diagram is not final.'));
    list.appendChild(warn);
  }

  const flow = el('div', 'flow');
  const box = (title, n, sub, cls) => {
    const b = el('div', 'box' + (cls ? ' ' + cls : ''));
    b.appendChild(el('div', null, title));
    b.appendChild(el('b', null, `n = ${n}`));
    if (sub) b.appendChild(el('div', 'sub', sub));
    return b;
  };
  const row = (left, right) => {
    const r = el('div', 'flowrow');
    r.appendChild(left);
    if (right) { r.appendChild(el('div', 'arrow-right')); r.appendChild(right); }
    return r;
  };
  const down = () => el('div', 'arrow-down');

  const sources = Object.entries(p.bySource).map(([k, v]) => `${k}: ${v}`).join('\n');
  flow.appendChild(row(box('Records identified from databases', p.identified, sources),
                       box('Records removed before screening', p.duplicates, 'Duplicate records')));
  flow.appendChild(down());
  flow.appendChild(row(box('Records screened', p.screened),
                       box('Records excluded', p.excludedScreening)));
  flow.appendChild(down());
  flow.appendChild(row(box('Reports sought for retrieval', p.sought),
                       box('Reports not retrieved', p.notRetrieved, 'Including any with no PDF on this machine')));
  flow.appendChild(down());
  const reasons = Object.entries(p.reasons).map(([k, v]) => `${k}: ${v}`).join('\n');
  flow.appendChild(row(box('Reports assessed for eligibility', p.assessed),
                       box('Reports excluded', p.excludedFullText, reasons)));
  flow.appendChild(down());
  flow.appendChild(row(box('Studies included in review', p.included, null, 'included')));
  list.appendChild(flow);

  const cite = el('p', 'hint');
  cite.textContent = 'Page MJ, McKenzie JE, Bossuyt PM, et al. The PRISMA 2020 statement. BMJ 2021;372:n71.';
  list.appendChild(cite);
  root.appendChild(list);
}

export function prismaText(state, p) {
  const L = [];
  L.push(`PRISMA 2020 flow — ${state.project?.name || 'Review'}`);
  if (state.project?.question) L.push(`Review question: ${state.project.question}`);
  L.push(`Generated ${new Date().toLocaleString()}`, '');
  L.push('IDENTIFICATION');
  L.push(`  Records identified from databases (n = ${p.identified})`);
  for (const [k, v] of Object.entries(p.bySource)) L.push(`      ${k}: ${v}`);
  L.push(`  Records removed before screening — duplicates (n = ${p.duplicates})`, '');
  L.push('SCREENING');
  L.push(`  Records screened (n = ${p.screened})`);
  L.push(`  Records excluded (n = ${p.excludedScreening})`);
  L.push(`  Reports sought for retrieval (n = ${p.sought})`);
  L.push(`  Reports not retrieved (n = ${p.notRetrieved})`);
  L.push(`  Reports assessed for eligibility (n = ${p.assessed})`);
  L.push(`  Reports excluded (n = ${p.excludedFullText})`);
  for (const [k, v] of Object.entries(p.reasons)) L.push(`      ${k}: ${v}`);
  L.push('', 'INCLUDED', `  Studies included in review (n = ${p.included})`, '');
  L.push('Source: Page MJ et al. BMJ 2021;372:n71.');
  return L.join('\n');
}

// ---------------------------------------------------------------- find papers

let searchState = { query: '', results: [], progress: {}, running: false, selected: new Set(),
                    enabled: new Set(PROVIDERS.map(p => p.name)) };

export function renderFind(ctx, root) {
  const { state, addFromHits } = ctx;
  root.innerHTML = '';

  const bar = el('div', 'bar');
  const input = el('input');
  input.type = 'search';
  input.placeholder = 'Search terms — e.g. cosmetic packaging sustainability';
  input.value = searchState.query;
  input.style.flex = '1';
  input.onkeydown = e => { if (e.key === 'Enter') run(); };
  bar.appendChild(input);
  const btn = el('button', 'primary', searchState.running ? 'Searching…' : 'Search');
  btn.disabled = searchState.running;
  btn.onclick = () => run();
  bar.appendChild(btn);
  root.appendChild(bar);

  const provBar = el('div', 'bar-sub');
  provBar.style.display = 'flex';
  provBar.style.flexWrap = 'wrap';
  provBar.style.gap = '5px';
  for (const p of PROVIDERS) {
    const b = el('button', 'provider');
    const st = searchState.progress[p.name];
    const label = st?.state === 'done' ? `${p.name} ${st.count}`
                : st?.state === 'running' ? `${p.name} …`
                : st?.state === 'failed' ? `${p.name} ✕` : p.name;
    b.textContent = label;
    b.setAttribute('aria-pressed', String(searchState.enabled.has(p.name)));
    b.title = p.blurb;
    b.onclick = () => {
      searchState.enabled.has(p.name) ? searchState.enabled.delete(p.name) : searchState.enabled.add(p.name);
      renderFind(ctx, root);
    };
    provBar.appendChild(b);
  }
  for (const b of BLOCKED) {
    const x = el('button', 'provider blocked', b.name);
    x.title = `Not available in a browser: ${b.why}. The desktop app searches it.`;
    x.disabled = true;
    provBar.appendChild(x);
  }
  const elsewhere = el('button', 'provider elsewhere', 'Google Scholar & others →');
  elsewhere.title = 'Search the places no browser can query, and bring the citations back';
  elsewhere.onclick = () => handOff(ctx, input.value.trim() || searchState.query);
  provBar.appendChild(elsewhere);
  root.appendChild(provBar);

  const list = el('div', 'list');
  if (!searchState.results.length && !searchState.running) {
    const e = el('div', 'empty');
    e.appendChild(el('h2', null, 'Seven databases, one query'));
    e.appendChild(el('p', null, 'OpenAlex, Crossref, Europe PMC, PubMed, DOAJ, PLOS and OpenAIRE at the same time. Records describing the same paper are merged, so you screen each paper once. Free PDFs are linked where they legally exist.'));
    const also = el('p', null, 'Google Scholar, Scopus, Web of Science and the publishers cannot be queried from any browser. Sieve opens your search there and takes the .bib or .ris you export back.');
    e.appendChild(also);
    const b = el('button', 'quiet', 'Search Google Scholar and the rest →');
    b.onclick = () => handOff(ctx, input.value.trim() || searchState.query);
    e.appendChild(b);
    list.appendChild(e);
  } else {
    const head = el('div', 'bar');
    head.style.borderBottom = '0';
    head.appendChild(el('span', 'meta', `${searchState.results.length} unique papers`));
    head.appendChild(el('span', 'grow'));
    const add = el('button', 'primary', 'Add to review');
    add.onclick = async () => {
      const chosen = searchState.results.filter(r => searchState.selected.has(dedupeKey(r)));
      if (!chosen.length) return;
      const n = await addFromHits(chosen, searchState.query);
      searchState.selected.clear();
      renderFind(ctx, root);
      ctx.toast(`Added ${n} paper${n === 1 ? '' : 's'}${n < chosen.length ? ` · ${chosen.length - n} already here` : ''}`);
    };
    head.appendChild(add);
    const all = el('button', 'quiet', 'Select all');
    head.appendChild(all);
    list.appendChild(head);

    // Ticking a box must not rebuild a hundred cards under the cursor: it changes two
    // labels, and the boxes keep their own state.
    const boxes = [];
    const syncSelection = () => {
      const n = searchState.selected.size;
      add.textContent = n ? `Add ${n} to review` : 'Add to review';
      add.disabled = !n;
      all.textContent = n && n === boxes.filter(b => !b.disabled).length ? 'Select none' : 'Select all';
    };
    all.onclick = () => {
      const selectable = boxes.filter(b => !b.disabled);
      const clearing = searchState.selected.size >= selectable.length;
      for (const b of selectable) {
        b.checked = !clearing;
        clearing ? searchState.selected.delete(b.dataset.key) : searchState.selected.add(b.dataset.key);
      }
      syncSelection();
    };

    const have = new Set(state.sources.map(s => s.dedupeKey));
    for (const r of searchState.results) {
      const key = dedupeKey(r);
      const already = have.has(key);
      const card = el('div', 'card');
      const top = el('div');
      top.style.cssText = 'display:flex;gap:9px;align-items:flex-start';
      const box = el('input');
      box.type = 'checkbox';
      box.style.marginTop = '3px';
      box.checked = searchState.selected.has(key);
      box.disabled = already;
      box.dataset.key = key;
      box.onchange = () => {
        box.checked ? searchState.selected.add(key) : searchState.selected.delete(key);
        syncSelection();
      };
      boxes.push(box);
      top.appendChild(box);
      const body = el('div');
      body.style.flex = '1';
      body.appendChild(el('h4', null, r.title));
      body.appendChild(el('div', 'meta',
        [r.authors.slice(0, 3).join(', ') || 'Unknown author', r.year, r.venue].filter(Boolean).join(' · ')));
      const chips = el('div', 'chips');
      chips.appendChild(chip(r.provider, 'var(--accent)'));
      for (const a of r.alsoFrom || []) chips.appendChild(chip(a, 'var(--faint)'));
      if (r.pdfURL) chips.appendChild(chip('free PDF', 'var(--emerald)'));
      if (r.citedBy) chips.appendChild(chip(`${r.citedBy} citations`, 'var(--faint)'));
      for (const g of r.sdgs || []) chips.appendChild(chip(g, 'var(--accent)'));
      if (already) chips.appendChild(chip('already in review', 'var(--amber)'));
      body.appendChild(chips);
      if (r.abstract) {
        const d = el('details');
        d.appendChild(el('summary', 'meta', 'Abstract'));
        d.appendChild(el('p', 'meta', r.abstract));
        body.appendChild(d);
      }
      top.appendChild(body);
      card.appendChild(top);
      list.appendChild(card);
    }
    syncSelection();
  }
  root.appendChild(list);

  async function run() {
    searchState.query = input.value.trim();
    if (!searchState.query) return;
    searchState.running = true;
    searchState.progress = {};
    searchState.results = [];
    searchState.selected.clear();
    renderFind(ctx, root);
    await searchAll(searchState.query, {
      enabled: searchState.enabled, limit: 20,
      onProgress: (name, st) => {
        searchState.progress[name] = st;
        if (st.merged) searchState.results = st.merged;
        renderFind(ctx, root);
      },
    });
    searchState.running = false;
    renderFind(ctx, root);
  }
}

/// The places that cannot be queried programmatically. Google Scholar forbids it in its
/// terms, BASE restricts its API to registered institutions, and the publishers gate search
/// behind institutional agreements. Scraping them would be both a breach and brittle, so
/// Sieve builds the search, opens it, and takes the citation file back — which is exactly
/// what the desktop app does.
export function handOff(ctx, query) {
  ctx.sheet('Search where a browser cannot', (body, close) => {
    const field = el('div', 'field');
    field.appendChild(el('label', null, 'Search terms'));
    const input = el('input');
    input.value = query || '';
    field.appendChild(input);
    body.appendChild(field);
    body.appendChild(el('p', 'meta',
      'These indexes have no API a browser may use. Open one, run the search, export the results as .bib or .ris, then drop that file anywhere on this page — every reference lands in your library with its provenance recorded.'));

    for (const site of EXTERNAL_SITES) {
      const card = el('div', 'card export-row');
      const text = el('div');
      text.appendChild(el('h4', null, site.name));
      text.appendChild(el('div', 'meta', site.blurb));
      text.appendChild(el('div', 'hint', site.howTo));
      card.appendChild(text);
      const b = el('button', 'quiet', 'Open →');
      b.onclick = () => window.open(siteURL(site, input.value.trim()), '_blank', 'noopener');
      card.appendChild(b);
      body.appendChild(card);
    }

    const actions = el('div', 'actions');
    const pick = el('button', 'primary', 'I have a .bib or .ris — import it');
    pick.onclick = () => { close(); document.querySelector('#fileInput').click(); };
    const done = el('button', 'quiet', 'Close');
    done.onclick = close;
    actions.append(pick, done);
    body.appendChild(actions);
  });
}

// ---------------------------------------------------------------- screening

let screenState = { index: 0, mode: 'toScreen' };

export function renderScreening(ctx, root) {
  const { state, setStage, go, openSource } = ctx;
  const queues = {
    toScreen: state.sources.filter(s => s.stage === 'identified'),
    fullText: state.sources.filter(s => ['sought', 'notRetrieved'].includes(s.stage)),
    decided: state.sources.filter(s => ['included', 'excludedScreening', 'excludedFullText'].includes(s.stage)),
  };
  const queue = queues[screenState.mode];
  if (screenState.index >= queue.length) screenState.index = Math.max(0, queue.length - 1);
  const paper = queue[screenState.index];
  root.innerHTML = '';

  const bar = el('div', 'bar');
  for (const [key, label] of [['toScreen', 'Title & abstract'], ['fullText', 'Full text'], ['decided', 'Decided']]) {
    const b = el('button', 'quiet', `${label} (${queues[key].length})`);
    if (screenState.mode === key) { b.style.borderColor = 'var(--accent)'; b.style.color = 'var(--accent)'; }
    b.onclick = () => { screenState.mode = key; screenState.index = 0; renderScreening(ctx, root); };
    bar.appendChild(b);
  }
  bar.appendChild(el('span', 'grow'));
  if (queue.length) bar.appendChild(el('span', 'meta', `${screenState.index + 1} of ${queue.length}`));
  root.appendChild(bar);

  if (!paper) {
    const e = el('div', 'empty');
    e.appendChild(el('h2', null, screenState.mode === 'decided' ? 'Nothing decided yet' : 'Nothing waiting'));
    e.appendChild(el('p', null, screenState.mode === 'toScreen'
      ? 'Every record has a decision. Anything you kept is under Full text.'
      : 'Decisions you make appear here and can always be changed.'));
    root.appendChild(e);
    return;
  }

  const wrap = el('div', 'screen-wrap');

  const q = el('div', 'screen-queue');
  queue.forEach((s, i) => {
    const item = el('div', 'queue-item');
    item.setAttribute('aria-current', String(i === screenState.index));
    item.appendChild(el('h5', null, s.title));
    item.appendChild(el('div', 'meta', [s.authors?.[0], s.year].filter(Boolean).join(' · ')));
    if (screenState.mode === 'decided') item.appendChild(chip(db.STAGES[s.stage]?.label || s.stage, db.STAGES[s.stage]?.color));
    item.onclick = () => { screenState.index = i; renderScreening(ctx, root); };
    q.appendChild(item);
  });
  wrap.appendChild(q);

  const body = el('div', 'screen-body');
  const chips = el('div', 'chips');
  chips.appendChild(chip(db.STAGES[paper.stage]?.label || paper.stage, db.STAGES[paper.stage]?.color));
  if (paper.provider) chips.appendChild(chip(paper.provider, 'var(--faint)'));
  if (paper.hasFile) chips.appendChild(chip('PDF ready', 'var(--emerald)'));
  for (const g of paper.sdgs || []) chips.appendChild(chip(g, 'var(--accent)'));
  body.appendChild(chips);
  const h = el('h2', null, paper.title);
  h.style.margin = '8px 0 3px';
  body.appendChild(h);
  body.appendChild(el('div', 'meta',
    [paper.authors?.join(', '), paper.year, paper.venue].filter(Boolean).join(' · ')));

  const inc = state.project?.inclusion || '';
  const exc = state.project?.exclusion || '';
  if (inc || exc) {
    const crit = el('div', 'chips');
    crit.style.marginTop = '10px';
    if (inc) { const c = el('div', 'card'); c.style.flex = '1';
      c.appendChild(el('div', 'meta', 'INCLUDE IF')); c.appendChild(el('div', null, inc)); crit.appendChild(c); }
    if (exc) { const c = el('div', 'card'); c.style.flex = '1';
      c.appendChild(el('div', 'meta', 'EXCLUDE IF')); c.appendChild(el('div', null, exc)); crit.appendChild(c); }
    body.appendChild(crit);
  }

  const abs = el('div');
  abs.style.marginTop = '14px';
  abs.appendChild(el('div', 'meta', 'ABSTRACT'));
  if (paper.abstract) {
    const p = el('p', 'abstract');
    // Criteria words tinted inside the abstract, the way Rayyan does it: a screening
    // decision usually turns on two or three words and finding them is the slow part.
    p.innerHTML = highlightCriteria(paper.abstract, inc, exc);
    abs.appendChild(p);
    const hits = countTerms(paper.abstract, inc), misses = countTerms(paper.abstract, exc);
    const c = el('div', 'chips');
    if (hits) c.appendChild(chip(`${hits} include terms`, 'var(--emerald)'));
    if (misses) c.appendChild(chip(`${misses} exclude terms`, 'var(--rose)'));
    if (!hits && !misses && (inc || exc)) c.appendChild(chip('no criteria words found', 'var(--faint)'));
    abs.appendChild(c);
  } else {
    abs.appendChild(el('p', 'hint', 'No abstract came with this record.'));
  }
  body.appendChild(abs);

  if (paper.conclusion) {
    const d = el('details');
    d.style.marginTop = '14px';
    d.open = true;
    d.appendChild(el('summary', 'meta',
      paper.conclusionHeading ? `THE PAPER'S ${paper.conclusionHeading.toUpperCase()} — READ FROM THE PDF`
                              : 'CLOSING PARAGRAPHS — READ FROM THE PDF'));
    d.appendChild(el('p', 'abstract', paper.conclusion));
    body.appendChild(d);
  }
  wrap.appendChild(body);

  const rail = el('div', 'screen-rail');
  const keep = el('button', 'primary');
  keep.style.cssText = 'width:100%;padding:11px;font-weight:600';
  keep.textContent = screenState.mode === 'toScreen' ? 'Keep — get full text' : 'Include in review';
  keep.onclick = () => decide(screenState.mode === 'toScreen' ? 'sought' : 'included');
  rail.appendChild(keep);

  if (paper.hasFile) {
    const read = el('button', 'quiet');
    read.style.cssText = 'width:100%;margin-top:6px';
    read.textContent = 'Read the full text';
    read.onclick = () => { openSource(paper.id); go('reader'); };
    rail.appendChild(read);
  }

  const label = el('div', 'meta');
  label.style.margin = '14px 0 5px';
  label.textContent = 'EXCLUDE — PICK A REASON';
  rail.appendChild(label);
  db.EXCLUSION_REASONS.forEach((r, i) => {
    const b = el('button', 'reason', `${i < 9 ? i + 1 + '  ' : '   '}${r}`);
    b.onclick = () => decide(screenState.mode === 'toScreen' ? 'excludedScreening' : 'excludedFullText', r);
    rail.appendChild(b);
  });

  if (screenState.mode === 'decided') {
    const undo = el('button', 'quiet', 'Undo this decision');
    undo.style.cssText = 'width:100%;margin-top:10px';
    undo.onclick = async () => { await setStage(paper.id, 'identified', ''); renderScreening(ctx, root); };
    rail.appendChild(undo);
  }

  const nav = el('div', 'actions');
  nav.style.marginTop = '12px';
  const prev = el('button', 'quiet', '← Prev');
  prev.disabled = screenState.index === 0;
  prev.onclick = () => { screenState.index--; renderScreening(ctx, root); };
  const next = el('button', 'quiet', 'Skip →');
  next.disabled = screenState.index >= queue.length - 1;
  next.onclick = () => { screenState.index++; renderScreening(ctx, root); };
  nav.append(prev, next);
  rail.appendChild(nav);
  rail.appendChild(el('p', 'hint', 'F keep · 1–9 exclude with that reason · J next · K previous'));
  wrap.appendChild(rail);
  root.appendChild(wrap);

  async function decide(stage, reason = '') {
    await setStage(paper.id, stage, reason);
    renderScreening(ctx, root);
  }
  screenState.decide = decide;
  screenState.queueLength = queue.length;
}

export function screeningKey(ctx, key) {
  if (!screenState.decide) return false;
  const root = document.querySelector('#screening');
  if (key === 'f' || key === 'i') { screenState.decide(screenState.mode === 'toScreen' ? 'sought' : 'included'); return true; }
  if (key === 'j') { screenState.index = Math.min(screenState.index + 1, screenState.queueLength - 1); renderScreening(ctx, root); return true; }
  if (key === 'k') { screenState.index = Math.max(screenState.index - 1, 0); renderScreening(ctx, root); return true; }
  const n = Number(key);
  if (n >= 1 && n <= 9 && db.EXCLUSION_REASONS[n - 1]) {
    screenState.decide(screenState.mode === 'toScreen' ? 'excludedScreening' : 'excludedFullText',
                       db.EXCLUSION_REASONS[n - 1]);
    return true;
  }
  return false;
}

const STOP = new Set(['the','and','or','not','with','without','any','all','for','from','that','this',
  'than','then','must','should','have','has','was','were','are','is','be','been','which','when','who',
  'into','onto','over','under','more','less','most','least','only','also','such','some','each','per',
  'study','studies','paper','papers','article','articles','research','based','years','year','old','its']);

function terms(criteria) {
  return [...new Set((criteria || '').split(/[\s,;·•\n\t()[\]/]+/)
    .map(t => t.replace(/^[.\-—]+|[.\-—]+$/g, ''))
    .filter(t => t.length >= 4 && !STOP.has(t.toLowerCase())))]
    .sort((a, b) => b.length - a.length);
}
const stem = t => {
  let s = t.toLowerCase();
  for (const suf of ['ing', 'ies', 'es', 's']) if (s.length > 5 && s.endsWith(suf)) { s = s.slice(0, -suf.length); break; }
  return s;
};
function countTerms(text, criteria) {
  const lower = (text || '').toLowerCase();
  return terms(criteria).filter(t => lower.includes(stem(t))).length;
}
function highlightCriteria(text, inc, exc) {
  const escape = s => s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
  let html = escape(text);
  const mark = (list, cls) => {
    for (const t of list) {
      const s = stem(t);
      if (s.length < 4) continue;
      const re = new RegExp(`(${s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[a-z]*)`, 'gi');
      html = html.replace(re, m => `<mark class="${cls}">${m}</mark>`);
    }
  };
  mark(terms(inc), 'inc');
  mark(terms(exc), 'exc');
  return html;
}

// ---------------------------------------------------------------- matrix

export function renderMatrix(ctx, root) {
  const { state, go, openSource } = ctx;
  const rows = state.sources.filter(s => s.stage === 'included');
  const cols = state.columns;
  root.innerHTML = '';

  const bar = el('div', 'bar');
  bar.appendChild(el('strong', null, 'Literature review matrix'));
  bar.appendChild(el('span', 'meta', `${rows.length} papers × ${cols.length} columns`));
  bar.appendChild(el('span', 'grow'));
  const addCol = el('button', 'quiet', 'Add column');
  addCol.onclick = () => ctx.prompt('New column', 'What this column asks of every paper', async (name) => {
    if (name) { await db.put('columns', { projectId: state.project.id, name, prompt: '' }); await ctx.refresh(); }
  });
  bar.appendChild(addCol);
  const exp = el('button', 'quiet', 'Export CSV');
  exp.onclick = () => ctx.download('review-matrix.csv', matrixCsv(state, rows, cols));
  bar.appendChild(exp);
  root.appendChild(bar);

  if (!rows.length) {
    const e = el('div', 'empty');
    e.appendChild(el('h2', null, 'No papers included yet'));
    e.appendChild(el('p', null, 'The matrix shows the papers you decided to include. Screen some records first.'));
    const b = el('button', 'primary', 'Go to screening');
    b.onclick = () => go('screening');
    e.appendChild(b);
    root.appendChild(e);
    return;
  }

  const wrap = el('div', 'grid');
  const table = el('table');
  const thead = el('thead');
  const hr = el('tr');
  hr.appendChild(el('th', 'rowhead', 'Paper'));
  for (const c of cols) {
    const th = el('th');
    th.appendChild(el('div', null, c.name));
    if (c.prompt) th.appendChild(el('span', 'cellnote', c.prompt));
    th.ondblclick = async () => {
      if (confirm(`Delete the column “${c.name}”?`)) { await db.del('columns', c.id); await ctx.refresh(); }
    };
    hr.appendChild(th);
  }
  thead.appendChild(hr);
  table.appendChild(thead);

  const tbody = el('tbody');
  for (const s of rows) {
    const tr = el('tr');
    const head = el('td', 'rowhead');
    head.appendChild(el('div', null, s.title));
    head.appendChild(el('span', 'cellnote', [s.authors?.[0], s.year].filter(Boolean).join(' · ')));
    const open = el('button', 'quiet', 'Open');
    open.style.marginTop = '6px';
    open.onclick = () => { openSource(s.id); go('reader'); };
    head.appendChild(open);
    tr.appendChild(head);
    for (const c of cols) {
      const key = `${s.id}-${c.id}`;
      const cell = state.cells[key];
      const td = el('td');
      td.textContent = cell?.value || '—';
      if (!cell?.value) td.style.color = 'var(--faint)';
      if (cell?.evidenceIds?.length) {
        td.appendChild(el('span', 'cellnote', `${cell.evidenceIds.length} highlight${cell.evidenceIds.length === 1 ? '' : 's'} cited`));
      }
      td.onclick = () => editCell(ctx, s, c, key);
      tr.appendChild(td);
    }
    tbody.appendChild(tr);
  }
  table.appendChild(tbody);
  wrap.appendChild(table);
  root.appendChild(wrap);
}

function editCell(ctx, source, column, key) {
  const { state } = ctx;
  const cell = state.cells[key] || { value: '', evidenceIds: [] };
  const mine = state.evidence.filter(e => e.sourceId === source.id);
  ctx.sheet(`${column.name}`, (body, close) => {
    body.appendChild(el('div', 'meta', source.title));
    const f = el('div', 'field');
    f.appendChild(el('label', null, 'Cell'));
    const ta = el('textarea');
    ta.rows = 4;
    ta.value = cell.value;
    f.appendChild(ta);
    body.appendChild(f);

    const picked = new Set(cell.evidenceIds || []);
    const f2 = el('div', 'field');
    f2.appendChild(el('label', null, mine.length ? 'Cite highlights from this paper' : 'No highlights from this paper yet'));
    for (const e of mine) {
      const b = el('button', 'quiet');
      b.style.cssText = 'text-align:left;width:100%;margin-bottom:4px';
      const tick = () => b.textContent = (picked.has(e.id) ? '✓ ' : '   ') + e.quote.slice(0, 90);
      tick();
      b.onclick = () => {
        if (picked.has(e.id)) picked.delete(e.id);
        else { picked.add(e.id); if (!ta.value.trim()) ta.value = e.quote; }
        tick();
      };
      f2.appendChild(b);
    }
    body.appendChild(f2);

    const actions = el('div', 'actions');
    const cancel = el('button', 'quiet', 'Cancel');
    cancel.onclick = close;
    const save = el('button', 'primary', 'Save');
    save.onclick = async () => {
      await db.put('cells', { key, projectId: state.project.id, sourceId: source.id,
                              columnId: column.id, value: ta.value, evidenceIds: [...picked] });
      await ctx.refresh();
      close();
    };
    actions.append(cancel, save);
    body.appendChild(actions);
  });
}

function matrixCsv(state, rows, cols) {
  const esc = v => `"${String(v ?? '').replace(/"/g, '""').replace(/\n/g, ' ')}"`;
  const out = [['Paper', 'Authors', 'Year', ...cols.map(c => c.name)].map(esc).join(',')];
  for (const s of rows) {
    const line = [s.title, (s.authors || []).join('; '), s.year || ''];
    for (const c of cols) line.push(state.cells[`${s.id}-${c.id}`]?.value || '');
    out.push(line.map(esc).join(','));
  }
  return out.join('\n');
}

// ---------------------------------------------------------------- frameworks

export const TEMPLATES = {
  swot: { label: 'SWOT', blurb: 'Strengths, weaknesses, opportunities, threats — each made to cite what it rests on.',
    rows: ['Strengths', 'Weaknesses', 'Opportunities', 'Threats'],
    cols: ['What we found', 'What it rests on', 'So what'] },
  journey: { label: 'User journey', blurb: "Stages of a user's experience, with what they do, think and struggle with.",
    rows: ['Before — trigger', 'Discover', 'Decide', 'First use', 'Habitual use', 'Trouble', 'Leave or renew'],
    cols: ['Doing', 'Thinking', 'Feeling', 'Pain points', 'Opportunity'] },
  empathy: { label: 'Empathy map', blurb: 'Separates what was observed from what you inferred.',
    rows: ['Says', 'Thinks', 'Does', 'Feels', 'Pains', 'Gains'],
    cols: ['Observed', 'Inferred', 'Evidence'] },
  competitive: { label: 'Competitive analysis', blurb: 'One row per product, compared on the same dimensions.',
    rows: [], cols: ['What it does well', 'Where it falls short', 'Who it is for', 'What we would do differently'] },
  assumptions: { label: 'Assumptions and risks', blurb: 'What you are taking for granted, and how you would test it.',
    rows: [], cols: ['Why we believe it', 'Evidence for', 'Evidence against', 'How we would test it', 'Risk if wrong'] },
  themes: { label: 'Affinity themes', blurb: 'Themes down the side, with the observations behind each.',
    rows: [], cols: ['What the theme says', 'Observations behind it', 'How many sources', 'Counter-evidence'] },
};

export function renderFrames(ctx, root) {
  const { state } = ctx;
  root.innerHTML = '';
  const bar = el('div', 'bar');
  bar.appendChild(el('strong', null, 'Frameworks'));
  bar.appendChild(el('span', 'grow'));
  const add = el('button', 'primary', 'New framework');
  add.onclick = () => pickTemplate(ctx);
  bar.appendChild(add);
  root.appendChild(bar);

  if (!state.frames.length) {
    const e = el('div', 'empty');
    e.appendChild(el('h2', null, 'A SWOT that cites its evidence'));
    e.appendChild(el('p', null, 'A framework here is a grid whose cells link to your actual highlights, in the same project as your sources. That citation is the difference between this and a whiteboard.'));
    root.appendChild(e);
    return;
  }

  const list = el('div', 'list');
  for (const f of state.frames) {
    const rows = state.axes.filter(a => a.frameId === f.id && a.isRow);
    const cols = state.axes.filter(a => a.frameId === f.id && !a.isRow);
    let filled = 0, cited = 0;
    for (const r of rows) for (const c of cols) {
      const cell = state.frameCells[`${f.id}-${r.id}-${c.id}`];
      if (cell?.value) filled++;
      if (cell?.evidenceIds?.length) cited++;
    }
    const head = el('div', 'bar');
    head.style.cssText = 'border:0;padding:4px 0';
    head.appendChild(el('strong', null, f.name));
    head.appendChild(chip(`${filled} filled`, 'var(--faint)'));
    if (filled) head.appendChild(chip(`${cited} cite evidence`, cited === filled ? 'var(--emerald)' : 'var(--amber)'));
    head.appendChild(el('span', 'grow'));
    const addRow = el('button', 'quiet', 'Add row');
    addRow.onclick = () => ctx.prompt('New row', '', async (name) => {
      if (name) { await db.put('axes', { frameId: f.id, projectId: state.project.id, isRow: true, name,
        sort: rows.length }); await ctx.refresh(); }
    });
    head.appendChild(addRow);
    const del = el('button', 'quiet danger', 'Delete');
    del.onclick = async () => {
      if (!confirm(`Delete “${f.name}”?`)) return;
      for (const a of state.axes.filter(a => a.frameId === f.id)) await db.del('axes', a.id);
      await db.del('frames', f.id); await ctx.refresh();
    };
    head.appendChild(del);
    list.appendChild(head);

    if (!rows.length) {
      list.appendChild(el('p', 'hint', 'The columns are set up. Add your first row.'));
      continue;
    }
    const wrap = el('div', 'grid');
    const table = el('table');
    const hr = el('tr');
    hr.appendChild(el('th', 'rowhead', ''));
    for (const c of cols) hr.appendChild(el('th', null, c.name));
    table.appendChild(hr);
    for (const r of rows) {
      const tr = el('tr');
      tr.appendChild(el('td', 'rowhead', r.name));
      for (const c of cols) {
        const key = `${f.id}-${r.id}-${c.id}`;
        const cell = state.frameCells[key];
        const td = el('td');
        td.textContent = cell?.value || '—';
        if (!cell?.value) td.style.color = 'var(--faint)';
        if (cell?.value && !cell?.evidenceIds?.length) {
          const n = el('span', 'cellnote', 'no evidence');
          n.style.color = 'var(--rose)';
          td.appendChild(n);
        } else if (cell?.evidenceIds?.length) {
          td.appendChild(el('span', 'cellnote', `${cell.evidenceIds.length} cited`));
        }
        td.onclick = () => editFrameCell(ctx, f, r, c, key);
        tr.appendChild(td);
      }
      table.appendChild(tr);
    }
    wrap.appendChild(table);
    list.appendChild(wrap);
  }
  root.appendChild(list);
}

function pickTemplate(ctx) {
  ctx.sheet('Add a framework', (body, close) => {
    body.appendChild(el('p', 'meta', 'A grid whose cells cite your evidence. It sits in this project alongside your sources, so a quote from a paper and one from an interview can share a cell.'));
    for (const [key, t] of Object.entries(TEMPLATES)) {
      const b = el('button', 'card');
      b.style.cssText = 'width:100%;text-align:left;margin-top:8px;cursor:pointer';
      b.appendChild(el('h4', null, t.label));
      b.appendChild(el('div', 'meta', t.blurb));
      b.appendChild(el('div', 'meta', t.rows.length
        ? `${t.rows.length} rows × ${t.cols.length} columns, ready to fill`
        : `${t.cols.length} columns · you add the rows`));
      b.onclick = async () => {
        const id = await db.put('frames', { projectId: ctx.state.project.id, name: t.label, kind: key });
        t.rows.forEach((name, i) => db.put('axes', { frameId: id, projectId: ctx.state.project.id, isRow: true, name, sort: i }));
        for (let i = 0; i < t.cols.length; i++) {
          await db.put('axes', { frameId: id, projectId: ctx.state.project.id, isRow: false, name: t.cols[i], sort: i });
        }
        await ctx.refresh();
        close();
      };
      body.appendChild(b);
    }
  });
}

function editFrameCell(ctx, frame, row, col, key) {
  const { state } = ctx;
  const cell = state.frameCells[key] || { value: '', evidenceIds: [] };
  ctx.sheet(`${row.name} · ${col.name}`, (body, close) => {
    const f = el('div', 'field');
    f.appendChild(el('label', null, 'What goes here'));
    const ta = el('textarea');
    ta.rows = 3;
    ta.value = cell.value;
    f.appendChild(ta);
    body.appendChild(f);

    const picked = new Set(cell.evidenceIds || []);
    const f2 = el('div', 'field');
    f2.appendChild(el('label', null, 'What this rests on'));
    if (!state.evidence.length) {
      f2.appendChild(el('p', 'hint', 'No highlights yet. Mark passages in the reader and they become citable here.'));
    }
    for (const e of state.evidence.slice(0, 60)) {
      const src = state.sources.find(s => s.id === e.sourceId);
      const b = el('button', 'quiet');
      b.style.cssText = 'text-align:left;width:100%;margin-bottom:4px';
      const tick = () => b.textContent = (picked.has(e.id) ? '✓ ' : '   ') +
        e.quote.slice(0, 70) + (src ? ` — ${(src.title || '').slice(0, 26)}` : '');
      tick();
      b.onclick = () => {
        if (picked.has(e.id)) picked.delete(e.id);
        else { picked.add(e.id); if (!ta.value.trim()) ta.value = e.quote; }
        tick();
      };
      f2.appendChild(b);
    }
    body.appendChild(f2);

    const actions = el('div', 'actions');
    const cancel = el('button', 'quiet', 'Cancel');
    cancel.onclick = close;
    const save = el('button', 'primary', 'Save');
    save.onclick = async () => {
      await db.put('frameCells', { key, projectId: state.project.id, frameId: frame.id,
                                   rowId: row.id, colId: col.id, value: ta.value, evidenceIds: [...picked] });
      await ctx.refresh();
      close();
    };
    actions.append(cancel, save);
    body.appendChild(actions);
  });
}
