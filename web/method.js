// The Method screen.
//
// A method is an ordered list of steps you choose — not a workflow the app imposes. Pick a
// preset, edit it, or build one from nothing. The steps decide what Sieve puts in front of
// you; the evidence underneath is the same whichever method you run over it. That separation
// is the point: PRISMA screening and thematic coding can happen in the same review, on the
// same passages, without either owning the data.

import * as db from './db.js';
import { el, chip } from './views.js';

export function active(state) {
  return state.methods.find(m => !m.isTemplate && m.projectId === state.project?.id) || null;
}

export function render(ctx, root) {
  const { state } = ctx;
  root.innerHTML = '';
  const wrap = el('div', 'list prose');

  const head = el('div');
  head.appendChild(el('h2', null, 'Method'));
  head.appendChild(el('p', 'meta',
    'How you work on this review. Steps are a guide, never a gate — every part of Sieve stays reachable whatever method you pick.'));
  wrap.appendChild(head);

  const mine = active(state);
  wrap.appendChild(mine ? activeCard(ctx, mine) : noMethodCard(ctx));

  wrap.appendChild(el('h3', 'section-label', 'Recipes you can adopt'));
  const grid = el('div', 'recipe-grid');
  for (const t of state.methods.filter(m => m.isTemplate)) {
    const card = el('div', 'card recipe');
    card.appendChild(el('h4', null, t.name));
    card.appendChild(el('div', 'meta', t.detail));
    const steps = el('div', 'chips');
    for (const b of t.blocks) {
      steps.appendChild(chip(db.METHOD_BLOCKS[b]?.label || b, 'var(--faint)'));
    }
    card.appendChild(steps);
    const actions = el('div', 'actions');
    const use = el('button', mine ? 'quiet' : 'primary', mine ? 'Use this instead' : 'Use this method');
    use.onclick = async () => {
      if (mine && !confirm(`Replace “${mine.name}” with “${t.name}”? Your evidence is untouched either way.`)) return;
      if (mine) await db.del('methods', mine.id);
      await db.put('methods', {
        projectId: state.project.id, name: t.name, detail: t.detail,
        blocks: [...t.blocks], isTemplate: false, step: 0,
      });
      await ctx.refresh();
      ctx.toast(`Running “${t.name}”`);
    };
    actions.appendChild(use);
    card.appendChild(actions);
    grid.appendChild(card);
  }
  wrap.appendChild(grid);

  const why = el('div', 'card');
  why.appendChild(el('h5', 'section-label', 'Why this exists'));
  why.appendChild(el('div', 'meta',
    'Most review software makes you adopt its methodology before you can use it. Sieve keeps the evidence — sources, highlights, categories, frames — separate from the method you run over it, so PRISMA screening and thematic coding can happen in the same review, on the same passages, without either owning the data.'));
  wrap.appendChild(why);

  root.appendChild(wrap);
}

function noMethodCard(ctx) {
  const card = el('div', 'card');
  card.appendChild(el('h4', null, 'No method chosen'));
  card.appendChild(el('div', 'meta',
    "You don't need one — the whole app works without it. A method just gives you an ordered path through the work, and shows how far along you are."));
  const actions = el('div', 'actions');
  const build = el('button', 'primary', 'Build one from scratch');
  build.onclick = () => builder(ctx, null);
  actions.appendChild(build);
  actions.appendChild(el('span', 'hint', 'or adopt a recipe below'));
  card.appendChild(actions);
  return card;
}

function activeCard(ctx, m) {
  const box = el('div');
  const head = el('div', 'inspector-head');
  head.appendChild(el('h5', 'section-label', "This review's method"));
  head.appendChild(el('span', 'grow'));
  const edit = el('button', 'quiet', 'Edit steps');
  edit.onclick = () => builder(ctx, m);
  const drop = el('button', 'quiet danger', 'Remove');
  drop.onclick = async () => {
    if (!confirm('Remove this method? Nothing else changes.')) return;
    await db.del('methods', m.id);
    await ctx.refresh();
  };
  head.append(edit, drop);
  box.appendChild(head);

  const card = el('div', 'card');
  card.appendChild(el('h4', null, m.name));
  if (m.detail) card.appendChild(el('div', 'meta', m.detail));

  const path = el('div', 'steps');
  m.blocks.forEach((key, i) => {
    const block = db.METHOD_BLOCKS[key];
    if (!block) return;
    const row = el('div', 'step');
    row.dataset.state = i < m.step ? 'done' : i === m.step ? 'now' : 'todo';
    const bullet = el('span', 'step-n', i < m.step ? '✓' : String(i + 1));
    row.appendChild(bullet);
    const bodyCol = el('div', 'step-body');
    bodyCol.appendChild(el('strong', null, block.label));
    bodyCol.appendChild(el('span', 'meta', block.blurb));
    row.appendChild(bodyCol);

    const acts = el('div', 'step-actions');
    const open = el('button', 'quiet', 'Open');
    open.onclick = () => ctx.go(block.view);
    acts.appendChild(open);
    if (i === m.step) {
      const done = el('button', 'quiet', 'Mark done');
      done.onclick = async () => {
        m.step = Math.min(m.step + 1, m.blocks.length);
        await db.put('methods', m);
        await ctx.refresh();
      };
      acts.appendChild(done);
    } else if (i < m.step) {
      const back = el('button', 'quiet', 'Reopen');
      back.onclick = async () => { m.step = i; await db.put('methods', m); await ctx.refresh(); };
      acts.appendChild(back);
    }
    row.appendChild(acts);
    path.appendChild(row);
  });
  card.appendChild(path);

  if (m.step >= m.blocks.length && m.blocks.length) {
    card.appendChild(el('p', 'hint', 'Every step is done. The work does not stop there — the steps were only a path through it.'));
  }
  box.appendChild(card);
  return box;
}

/// Build or edit a method. Steps are picked from the same vocabulary the presets use, so a
/// method you build is exactly as legible as one that shipped with the app.
function builder(ctx, existing) {
  let name = existing?.name || '';
  let detail = existing?.detail || '';
  let blocks = existing ? [...existing.blocks] : [];

  ctx.sheet(existing ? 'Edit the steps' : 'Build a method', (sheet, close) => {
    const nf = el('div', 'field');
    nf.appendChild(el('label', null, 'Name'));
    const ni = el('input');
    ni.value = name;
    ni.oninput = () => { name = ni.value; };
    nf.appendChild(ni);
    sheet.appendChild(nf);

    const df = el('div', 'field');
    df.appendChild(el('label', null, 'What it is for'));
    const di = el('textarea');
    di.rows = 2; di.value = detail;
    di.oninput = () => { detail = di.value; };
    df.appendChild(di);
    sheet.appendChild(df);

    const chosen = el('div', 'chosen-steps');
    const bank = el('div', 'chips');

    const paint = () => {
      chosen.innerHTML = '';
      if (!blocks.length) chosen.appendChild(el('p', 'hint', 'No steps yet — click one below to add it.'));
      blocks.forEach((key, i) => {
        const row = el('div', 'chosen-step');
        row.appendChild(el('span', 'step-n', String(i + 1)));
        row.appendChild(el('strong', null, db.METHOD_BLOCKS[key]?.label || key));
        row.appendChild(el('span', 'grow'));
        const up = el('button', 'icon', '↑');
        up.disabled = i === 0;
        up.onclick = () => { [blocks[i - 1], blocks[i]] = [blocks[i], blocks[i - 1]]; paint(); };
        const down = el('button', 'icon', '↓');
        down.disabled = i === blocks.length - 1;
        down.onclick = () => { [blocks[i + 1], blocks[i]] = [blocks[i], blocks[i + 1]]; paint(); };
        const rm = el('button', 'icon danger', '×');
        rm.onclick = () => { blocks.splice(i, 1); paint(); };
        row.append(up, down, rm);
        chosen.appendChild(row);
      });
    };
    paint();
    sheet.appendChild(el('h5', 'section-label', 'Steps, in order'));
    sheet.appendChild(chosen);

    sheet.appendChild(el('h5', 'section-label', 'Add a step'));
    for (const [key, block] of Object.entries(db.METHOD_BLOCKS)) {
      const b = el('button', 'swatch');
      b.title = block.blurb;
      b.textContent = block.label;
      b.onclick = () => { blocks.push(key); paint(); };
      bank.appendChild(b);
    }
    sheet.appendChild(bank);

    const actions = el('div', 'actions');
    const cancel = el('button', 'quiet', 'Cancel');
    cancel.onclick = close;
    const save = el('button', 'primary', 'Save');
    save.onclick = async () => {
      if (!name.trim() || !blocks.length) { ctx.toast('A method needs a name and at least one step'); return; }
      close();
      const record = existing
        ? { ...existing, name: name.trim(), detail, blocks, step: Math.min(existing.step, blocks.length) }
        : { projectId: ctx.state.project.id, name: name.trim(), detail, blocks, isTemplate: false, step: 0 };
      await db.put('methods', record);
      await ctx.refresh();
      ctx.toast('Method saved');
    };
    actions.append(cancel, save);
    sheet.appendChild(actions);
  });
}
