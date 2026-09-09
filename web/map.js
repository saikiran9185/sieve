// A map of the corpus.
//
// Papers are nodes; a line means the two cite the same works often enough to matter
// (bibliographic coupling), or one cites the other. Both come from the reference lists
// OpenAlex ships with every record, so nothing here is inferred — it is citation data.
//
// It also finds the works your own papers keep citing that are not in your library yet.
// That is the reading you are missing, and it is the part a search box cannot tell you.

import * as db from './db.js';
import { el, chip } from './views.js';

const state = {
  nodes: [], edges: [], position: new Map(),
  suggestions: [], suggestionPosition: new Map(),
  threshold: 2, colorBy: 'stage', selected: null, loading: false,
  zoom: 1, panX: 0, panY: 0,
};

export function render(ctx, root) {
  root.innerHTML = '';

  const withRefs = ctx.state.sources.filter(s => (s.references || []).length).length;
  build(ctx.state);

  root.appendChild(toolbar(ctx, root));

  if (!ctx.state.sources.length) {
    root.appendChild(empty(ctx, 'Nothing to map yet',
      'Add papers under Find papers, then come back.', 'Find papers', 'find'));
    return;
  }
  if (!withRefs) {
    root.appendChild(empty(ctx, 'These papers have no citation data yet',
      `The map is drawn from the works each paper cites. Your ${ctx.state.sources.length} paper${ctx.state.sources.length === 1 ? ' was' : 's were'} added without that data — “Fetch reference lists” above asks OpenAlex for them, and then this map draws itself.`,
      'Fetch reference lists', null, () => fetchReferences(ctx)));
    return;
  }

  const split = el('div', 'map-split');
  const canvasWrap = el('div', 'map-canvas');
  const canvas = el('canvas');
  canvasWrap.appendChild(canvas);
  canvasWrap.appendChild(legend(ctx));
  split.appendChild(canvasWrap);
  split.appendChild(panel(ctx));
  root.appendChild(split);

  paint(ctx, canvas, canvasWrap);
  let raf = null;
  const repaint = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(() => paint(ctx, canvas, canvasWrap)); };
  new ResizeObserver(repaint).observe(canvasWrap);

  // Where a click landed, in the graph's own coordinates.
  const graphPoint = (e) => {
    const box = canvas.getBoundingClientRect();
    return {
      x: (e.clientX - box.left - box.width / 2 - state.panX) / state.zoom,
      y: (e.clientY - box.top - box.height / 2 - state.panY) / state.zoom,
    };
  };

  // Drag to pan. A click is a drag that went nowhere, which is how selection stays possible
  // on the same surface.
  let dragging = false, moved = 0, from = null;
  canvas.onpointerdown = (e) => {
    dragging = true; moved = 0;
    from = { x: e.clientX, y: e.clientY, panX: state.panX, panY: state.panY };
    canvas.setPointerCapture(e.pointerId);
  };
  canvas.onpointermove = (e) => {
    if (!dragging) return;
    const dx = e.clientX - from.x, dy = e.clientY - from.y;
    moved = Math.max(moved, Math.hypot(dx, dy));
    state.panX = from.panX + dx;
    state.panY = from.panY + dy;
    repaint();
  };
  canvas.onpointerup = (e) => {
    dragging = false;
    canvas.releasePointerCapture?.(e.pointerId);
    if (moved > 4) return;
    const at = graphPoint(e);
    let best = null;
    for (const n of state.nodes) {
      const p = state.position.get(n.id);
      if (!p) continue;
      const d = Math.hypot(p.x - at.x, p.y - at.y);
      if (d < Math.max(radius(ctx.state, n) + 7 / state.zoom, 13 / state.zoom) && (!best || d < best.d)) {
        best = { id: n.id, d };
      }
    }
    state.selected = best ? best.id : null;
    render(ctx, root);
  };

  // Scroll to zoom, anchored on the pointer so the thing under it stays under it.
  canvas.onwheel = (e) => {
    e.preventDefault();
    const box = canvas.getBoundingClientRect();
    const mx = e.clientX - box.left - box.width / 2;
    const my = e.clientY - box.top - box.height / 2;
    const before = state.zoom;
    state.zoom = Math.min(4, Math.max(0.2, state.zoom * (e.deltaY < 0 ? 1.12 : 1 / 1.12)));
    const k = state.zoom / before;
    state.panX = mx - (mx - state.panX) * k;
    state.panY = my - (my - state.panY) * k;
    repaint();
  };

  canvasWrap.appendChild(zoomControls(repaint));
}

function zoomControls(repaint) {
  const box = el('div', 'map-zoom');
  const step = (label, fn) => {
    const b = el('button', 'icon', label);
    b.onclick = () => { fn(); repaint(); };
    return b;
  };
  box.append(
    step('\u2212', () => { state.zoom = Math.max(0.2, state.zoom / 1.25); }),
    step('+', () => { state.zoom = Math.min(4, state.zoom * 1.25); }),
    step('\u2317', () => { state.zoom = 1; state.panX = 0; state.panY = 0; }),
  );
  box.lastChild.title = 'Fit';
  return box;
}

function empty(ctx, title, message, label, view, action) {
  const box = el('div', 'empty');
  box.appendChild(el('h2', null, title));
  box.appendChild(el('p', null, message));
  if (label) {
    const b = el('button', 'primary', label);
    b.onclick = action || (() => ctx.go(view));
    box.appendChild(b);
  }
  return box;
}

function toolbar(ctx, root) {
  const bar = el('div', 'bar');
  bar.appendChild(el('strong', null, 'Map'));
  bar.appendChild(el('span', 'meta',
    `${state.nodes.length} paper${state.nodes.length === 1 ? '' : 's'} · ${state.edges.length} connection${state.edges.length === 1 ? '' : 's'}`));

  const colour = el('select');
  for (const [v, label] of [['stage', 'Colour by stage'], ['year', 'Colour by year'], ['marks', 'Colour by highlights']]) {
    colour.appendChild(new Option(label, v));
  }
  colour.value = state.colorBy;
  colour.onchange = () => { state.colorBy = colour.value; render(ctx, root); };
  bar.appendChild(colour);

  const slider = el('input');
  slider.type = 'range'; slider.min = '1'; slider.max = '6'; slider.step = '1';
  slider.value = String(state.threshold);
  slider.className = 'slider';
  slider.oninput = () => {
    state.threshold = Number(slider.value);
    state.position.clear();
    render(ctx, root);
  };
  bar.appendChild(slider);
  bar.appendChild(el('span', 'meta', `≥${state.threshold} shared refs`));

  bar.appendChild(el('span', 'grow'));

  const fetchBtn = el('button', 'quiet', 'Fetch reference lists');
  fetchBtn.title = 'Ask OpenAlex what each paper cites';
  fetchBtn.onclick = () => fetchReferences(ctx);
  bar.appendChild(fetchBtn);

  const find = el('button', 'quiet', state.loading ? 'Looking…' : "Find what I'm missing");
  find.disabled = state.loading;
  find.title = "Works your papers cite repeatedly that aren't in your library yet";
  find.onclick = async () => {
    state.loading = true; render(ctx, root);
    await findSuggestions(ctx);
    state.loading = false; render(ctx, root);
  };
  bar.appendChild(find);

  const relayout = el('button', 'quiet', 'Re-layout');
  relayout.onclick = () => {
    state.position.clear();
    state.zoom = 1; state.panX = 0; state.panY = 0;
    render(ctx, root);
  };
  bar.appendChild(relayout);
  return bar;
}

function legend(ctx) {
  const box = el('div', 'map-legend');
  box.appendChild(el('div', 'hint', 'Bigger dot = more highlights · line = shared references · drag to pan, scroll to zoom'));
  if (state.suggestions.length) {
    box.appendChild(el('div', 'hint accent',
      `${state.suggestions.length} works you cite but haven't read — the rings on the outside`));
  }
  return box;
}

// ---------------------------------------------------------------- the graph

function build(appState) {
  const papers = appState.sources.filter(s => !String(s.stage || '').startsWith('excluded') && s.stage !== 'duplicate');
  state.nodes = papers.map(p => ({
    id: p.id,
    label: citeKey(p),
    refs: new Set(p.references || []),
    oaId: p.openAlexId || '',
  }));

  const edges = [];
  for (let i = 0; i < state.nodes.length; i++) {
    for (let j = i + 1; j < state.nodes.length; j++) {
      const a = state.nodes[i], b = state.nodes[j];
      let weight = 0;
      for (const r of a.refs) if (b.refs.has(r)) weight++;
      if (b.oaId && a.refs.has(b.oaId)) weight += 4;
      if (a.oaId && b.refs.has(a.oaId)) weight += 4;
      if (weight >= state.threshold) edges.push({ a: a.id, b: b.id, weight });
    }
  }
  state.edges = edges;
  const known = new Set(state.nodes.map(n => n.id));
  for (const id of [...state.position.keys()]) if (!known.has(id)) state.position.delete(id);
  if (state.position.size !== state.nodes.length) relayout();
}

function citeKey(s) {
  const first = (s.authors || [])[0] || '';
  const surname = first.split(/\s+/).pop() || (s.title || 'source').split(/\s+/)[0];
  return `${surname} ${s.year || ''}`.trim().slice(0, 18);
}

/// A small force-directed layout: linked papers pull together, everything pushes apart. Run
/// to convergence once rather than animated, so the map is stable to read.
function relayout() {
  state.position.clear();
  if (!state.nodes.length) return;
  const ring = 180 + state.nodes.length * 3;
  state.nodes.forEach((n, i) => {
    const a = (i / state.nodes.length) * Math.PI * 2;
    state.position.set(n.id, { x: Math.cos(a) * ring, y: Math.sin(a) * ring });
  });

  const ids = state.nodes.map(n => n.id);
  for (let step = 0; step < 260; step++) {
    const cooling = 1 - step / 260;
    const force = new Map(ids.map(id => [id, { x: 0, y: 0 }]));

    for (let i = 0; i < ids.length; i++) {
      for (let j = i + 1; j < ids.length; j++) {
        const pa = state.position.get(ids[i]), pb = state.position.get(ids[j]);
        let dx = pa.x - pb.x, dy = pa.y - pb.y;
        let dist = Math.hypot(dx, dy);
        if (dist < 0.01) { dx = Math.random() * 2 - 1; dy = Math.random() * 2 - 1; dist = 1; }
        const repel = 5200 / (dist * dist);
        const fa = force.get(ids[i]), fb = force.get(ids[j]);
        fa.x += (dx / dist) * repel; fa.y += (dy / dist) * repel;
        fb.x -= (dx / dist) * repel; fb.y -= (dy / dist) * repel;
      }
    }
    for (const e of state.edges) {
      const pa = state.position.get(e.a), pb = state.position.get(e.b);
      if (!pa || !pb) continue;
      const dx = pb.x - pa.x, dy = pb.y - pa.y;
      const dist = Math.max(Math.hypot(dx, dy), 0.01);
      const pull = (dist - 120) * 0.012 * Math.min(e.weight, 6);
      const fa = force.get(e.a), fb = force.get(e.b);
      fa.x += (dx / dist) * pull; fa.y += (dy / dist) * pull;
      fb.x -= (dx / dist) * pull; fb.y -= (dy / dist) * pull;
    }
    for (const id of ids) {
      const p = state.position.get(id), f = force.get(id);
      // A weak pull to the origin keeps unconnected papers from drifting off-screen.
      p.x += (f.x - p.x * 0.004) * cooling * 0.6;
      p.y += (f.y - p.y * 0.004) * cooling * 0.6;
    }
  }
  layoutSuggestions();
}

function layoutSuggestions() {
  state.suggestionPosition.clear();
  const ring = 260 + state.nodes.length * 3;
  state.suggestions.forEach((s, i) => {
    const a = (i / Math.max(state.suggestions.length, 1)) * Math.PI * 2 + 0.3;
    state.suggestionPosition.set(s.openAlexId, { x: Math.cos(a) * ring, y: Math.sin(a) * ring });
  });
}

// ---------------------------------------------------------------- drawing

function radius(appState, n) {
  const marks = appState.evidence.filter(e => e.sourceId === n.id).length;
  return 6 + Math.min(marks * 0.8, 10);
}

function tint(appState, n) {
  const css = getComputedStyle(document.documentElement);
  const s = appState.sources.find(x => x.id === n.id);
  if (!s) return css.getPropertyValue('--faint');
  if (state.colorBy === 'marks') {
    const marks = appState.evidence.filter(e => e.sourceId === n.id).length;
    return marks ? css.getPropertyValue('--amber') : css.getPropertyValue('--faint');
  }
  if (state.colorBy === 'year') {
    const years = appState.sources.map(x => x.year).filter(Boolean);
    const lo = Math.min(...years), hi = Math.max(...years);
    if (!s.year || hi === lo) return css.getPropertyValue('--faint');
    const t = (s.year - lo) / (hi - lo);
    return `hsl(${(0.62 - t * 0.45) * 360}deg 55% 58%)`;
  }
  const stage = db.STAGES[s.stage] || db.STAGES.identified;
  const raw = stage.color;
  return raw.startsWith('var(') ? css.getPropertyValue(raw.slice(4, -1)) : raw;
}

function paint(ctx, canvas, wrap) {
  const ratio = window.devicePixelRatio || 1;
  const w = wrap.clientWidth, h = wrap.clientHeight;
  if (!w || !h) return;
  canvas.width = w * ratio; canvas.height = h * ratio;
  canvas.style.width = `${w}px`; canvas.style.height = `${h}px`;
  const g = canvas.getContext('2d');
  g.scale(ratio, ratio);
  g.translate(w / 2 + state.panX, h / 2 + state.panY);
  g.scale(state.zoom, state.zoom);
  const cx = 0, cy = 0;
  const css = getComputedStyle(document.documentElement);
  const line = css.getPropertyValue('--line');
  const text = css.getPropertyValue('--text');
  const accent = css.getPropertyValue('--accent');

  for (const e of state.edges) {
    const a = state.position.get(e.a), b = state.position.get(e.b);
    if (!a || !b) continue;
    g.strokeStyle = line;
    g.globalAlpha = e.weight >= 4 ? 0.85 : 0.4;
    g.lineWidth = (e.weight >= 4 ? 1.4 : 0.7) / state.zoom;
    g.beginPath();
    g.moveTo(cx + a.x, cy + a.y);
    g.lineTo(cx + b.x, cy + b.y);
    g.stroke();
  }
  g.globalAlpha = 1;

  for (const n of state.nodes) {
    const p = state.position.get(n.id);
    if (!p) continue;
    const r = radius(ctx.state, n);
    g.fillStyle = tint(ctx.state, n);
    g.beginPath();
    g.arc(cx + p.x, cy + p.y, r, 0, Math.PI * 2);
    g.fill();
    if (state.selected === n.id) {
      g.strokeStyle = text; g.lineWidth = 2 / state.zoom;
      g.beginPath();
      g.arc(cx + p.x, cy + p.y, r + 3, 0, Math.PI * 2);
      g.stroke();
    }
    g.fillStyle = text;
    // Labels stay legible rather than scaling with the graph.
    if (state.zoom > 0.55 || state.selected === n.id) {
      g.font = `${state.selected === n.id ? '600 ' : ''}${9 / state.zoom}px -apple-system, system-ui, sans-serif`;
      g.textAlign = 'center';
      g.fillText(n.label, cx + p.x, cy + p.y + r + 11 / state.zoom);
    }
  }

  // Suggested reading is drawn as hollow rings — clearly not yours yet.
  for (const s of state.suggestions) {
    const p = state.suggestionPosition.get(s.openAlexId);
    if (!p) continue;
    g.strokeStyle = accent; g.lineWidth = 1.4 / state.zoom;
    g.beginPath();
    g.arc(cx + p.x, cy + p.y, 5, 0, Math.PI * 2);
    g.stroke();
    if (state.zoom > 0.7) {
      g.fillStyle = accent;
      g.font = `${8 / state.zoom}px -apple-system, system-ui, sans-serif`;
      g.fillText(`${s.citedByMine}×`, cx + p.x, cy + p.y + 14 / state.zoom);
    }
  }
}

// ---------------------------------------------------------------- side panel

function panel(ctx) {
  const side = el('aside', 'map-panel');
  const chosen = state.selected != null && ctx.state.sources.find(s => s.id === state.selected);
  if (chosen) {
    const stage = db.STAGES[chosen.stage] || db.STAGES.identified;
    const chips = el('div', 'chips');
    chips.appendChild(chip(stage.label, stage.color));
    side.appendChild(chips);
    side.appendChild(el('h3', null, chosen.title));
    side.appendChild(el('div', 'meta',
      `${(chosen.authors || []).slice(0, 3).join(', ') || 'Unknown author'} · ${chosen.year || 'n.d.'}`));

    if (chosen.hasFile) {
      const open = el('button', 'primary wide', 'Open in reader');
      open.onclick = () => { ctx.openSource(chosen.id); ctx.go('reader'); };
      side.appendChild(open);
    }
    if ((chosen.references || []).length) {
      side.appendChild(el('div', 'meta', `${chosen.references.length} works cited`));
    }

    side.appendChild(el('h5', 'section-label', 'Most connected to'));
    const near = state.edges
      .map(e => (e.a === chosen.id ? [e.b, e.weight] : e.b === chosen.id ? [e.a, e.weight] : null))
      .filter(Boolean)
      .sort((x, y) => y[1] - x[1])
      .slice(0, 12);
    if (!near.length) {
      side.appendChild(el('p', 'hint', 'No shared references with anything else in the review yet.'));
    }
    for (const [id, weight] of near) {
      const other = ctx.state.sources.find(s => s.id === id);
      if (!other) continue;
      const row = el('button', 'near');
      row.appendChild(el('span', 'near-n', String(weight)));
      const bodyCol = el('span', 'near-body');
      bodyCol.appendChild(el('span', null, other.title));
      bodyCol.appendChild(el('span', 'meta', (other.authors || [])[0] || ''));
      row.appendChild(bodyCol);
      row.onclick = () => { state.selected = id; ctx.go('map'); };
      side.appendChild(row);
    }
    const clear = el('button', 'quiet', 'Show what I am missing instead');
    clear.onclick = () => { state.selected = null; ctx.go('map'); };
    side.appendChild(clear);
    return side;
  }

  side.appendChild(el('h3', null, "What you're missing"));
  side.appendChild(el('p', 'meta',
    "Works cited by two or more of your papers that aren't in your library. The number is how many of your papers cite it."));
  if (!state.suggestions.length) {
    side.appendChild(el('p', 'hint', 'Press “Find what I’m missing” above.'));
    return side;
  }
  for (const s of state.suggestions) {
    const card = el('div', 'card');
    const chips = el('div', 'chips');
    chips.appendChild(chip(`cited by ${s.citedByMine} of yours`, 'var(--accent)'));
    if (s.year) chips.appendChild(el('span', 'meta', String(s.year)));
    card.appendChild(chips);
    card.appendChild(el('h4', null, s.title));
    card.appendChild(el('div', 'meta', (s.authors || []).slice(0, 3).join(', ')));
    const actions = el('div', 'actions');
    const add = el('button', 'quiet', 'Add to review');
    add.onclick = async () => {
      const n = await ctx.addFromHits([{
        title: s.title, authors: s.authors, year: s.year, venue: '', doi: s.doi,
        abstract: '', url: s.doi ? `https://doi.org/${s.doi}` : '', pdfURL: '',
        provider: 'OpenAlex (found on the map)', sdgs: [], citedBy: 0,
        openAlexId: s.openAlexId, references: [],
      }], 'Found via the map');
      state.suggestions = state.suggestions.filter(x => x.openAlexId !== s.openAlexId);
      layoutSuggestions();
      ctx.toast(n ? 'Added to the review' : 'Already in this review');
      ctx.go('map');
    };
    actions.appendChild(add);
    if (s.doi) {
      const open = el('button', 'quiet', 'Open');
      open.onclick = () => window.open(`https://doi.org/${s.doi}`, '_blank', 'noopener');
      actions.appendChild(open);
    }
    card.appendChild(actions);
    side.appendChild(card);
  }
  return side;
}

// ---------------------------------------------------------------- network

/// Fills in the reference lists for records that have none. Papers added before the map
/// existed, or found through a database that does not ship citations, come in blank —
/// OpenAlex will match most of them on their DOI.
async function fetchReferences(ctx) {
  const need = ctx.state.sources.filter(s => !(s.references || []).length && (s.doi || s.openAlexId));
  if (!need.length) {
    const anyId = ctx.state.sources.some(s => s.doi || s.openAlexId);
    ctx.toast(anyId
      ? 'Every record that can be matched already has its references'
      : 'None of these records has a DOI, so OpenAlex has nothing to match them against');
    return;
  }
  ctx.toast(`Asking OpenAlex about ${need.length} record${need.length === 1 ? '' : 's'}…`);
  let filled = 0;
  for (const chunk of chunked(need, 25)) {
    const filter = chunk.map(s => (s.openAlexId ? s.openAlexId : `doi:${s.doi}`)).join('|');
    const key = chunk[0].openAlexId ? 'openalex_id' : 'doi';
    try {
      const res = await fetch(`https://api.openalex.org/works?filter=${key}:${encodeURIComponent(filter)}&per-page=25&select=id,doi,referenced_works`);
      if (!res.ok) continue;
      const data = await res.json();
      for (const w of data.results || []) {
        const oa = String(w.id || '').replace('https://openalex.org/', '');
        const doi = String(w.doi || '').replace('https://doi.org/', '').toLowerCase();
        const match = chunk.find(s => s.openAlexId === oa || (doi && s.doi === doi));
        if (!match) continue;
        const rec = await db.get('sources', match.id);
        if (!rec) continue;
        rec.openAlexId = oa;
        rec.references = (w.referenced_works || []).map(r => String(r).replace('https://openalex.org/', ''));
        await db.put('sources', rec);
        if (rec.references.length) filled++;
      }
    } catch { /* one bad chunk should not stop the rest */ }
  }
  state.position.clear();
  await ctx.refresh();
  ctx.toast(filled ? `Reference lists for ${filled} paper${filled === 1 ? '' : 's'}` : 'OpenAlex had nothing for those');
}

/// Counts every work your papers cite, drops the ones already in the library, and looks up
/// the most-cited remainder. These are the papers your own corpus keeps pointing at.
async function findSuggestions(ctx) {
  const mine = new Set(ctx.state.sources.map(s => s.openAlexId).filter(Boolean));
  const tally = new Map();
  for (const n of state.nodes) {
    for (const r of n.refs) if (!mine.has(r)) tally.set(r, (tally.get(r) || 0) + 1);
  }
  const top = [...tally.entries()].filter(([, n]) => n >= 2).sort((a, b) => b[1] - a[1]).slice(0, 40);
  if (!top.length) {
    state.suggestions = [];
    layoutSuggestions();
    ctx.toast('No work is cited by two of your papers yet — add a few more OpenAlex records');
    return;
  }
  const found = [];
  for (const chunk of chunked(top, 25)) {
    const ids = chunk.map(([id]) => id).join('|');
    try {
      const res = await fetch(`https://api.openalex.org/works?filter=openalex_id:${ids}&per-page=25`);
      if (!res.ok) continue;
      const data = await res.json();
      for (const w of data.results || []) {
        const oa = String(w.id || '').replace('https://openalex.org/', '');
        found.push({
          openAlexId: oa,
          title: w.display_name || '',
          authors: (w.authorships || []).map(a => a.author?.display_name).filter(Boolean),
          year: w.publication_year || null,
          doi: String(w.doi || '').replace('https://doi.org/', '').toLowerCase(),
          citedByMine: tally.get(oa) || 0,
        });
      }
    } catch { /* skip the chunk */ }
  }
  state.suggestions = found.filter(f => f.title).sort((a, b) => b.citedByMine - a.citedByMine);
  layoutSuggestions();
  ctx.toast(state.suggestions.length
    ? `${state.suggestions.length} works your papers cite but you haven't read`
    : 'Nothing new found');
}

function chunked(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}
