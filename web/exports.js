// Everything that leaves Sieve.
//
// The desktop app exports a PNG, an SVG, plain text, the reporting checklist, a full report
// as PDF, and the lot in one folder. A browser can do all of it except write a real folder,
// and can produce a genuine PDF the same way every other web page does — by printing itself
// through the browser's own engine, which is a better typesetter than anything shippable in
// a few hundred lines here.

import * as db from './db.js';
import { prismaCounts, prismaText } from './views.js';
import { toBibTeX, toRIS } from './citations.js';
import { Zip, safeName } from './zip.js';

const esc = (s) => String(s ?? '')
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const csvCell = (v) => `"${String(v ?? '').replace(/"/g, '""').replace(/\r?\n/g, ' ')}"`;
const csv = (rows) => rows.map(r => r.map(csvCell).join(',')).join('\n');

export function reference(s) {
  const authors = (s.authors || []).length
    ? (s.authors.length > 3 ? s.authors[0] + ' et al.' : s.authors.join(', '))
    : 'Unknown author';
  return [authors, `(${s.year || 'n.d.'})`, s.title, s.venue, s.doi ? `https://doi.org/${s.doi}` : '']
    .filter(Boolean).join('. ');
}

// ---------------------------------------------------------------- the PRISMA diagram

/// The flow diagram as vector art, laid out exactly as the desktop app lays it out, so the
/// figure in a thesis is the same figure whichever version produced it.
export function prismaSVG(state) {
  const p = prismaCounts(state);
  const W = 760;
  const LEFT = 24, RIGHT = 420, BOX = 300;
  let y = 44;
  let body = '';

  const box = (x, top, title, n, detail, highlight) => {
    const h = 56 + detail.length * 13;
    let s = `<rect x="${x}" y="${top}" width="${BOX}" height="${h}" fill="${highlight ? '#DCFCE7' : '#ffffff'}" stroke="${highlight ? '#16A34A' : '#9CA3AF'}" stroke-width="${highlight ? 1.5 : 1}"/>`;
    s += `<text x="${x + 12}" y="${top + 21}" font-size="11.5" fill="#111827">${esc(title)}</text>`;
    s += `<text x="${x + 12}" y="${top + 40}" font-size="13" font-weight="600" fill="#374151">(n = ${n})</text>`;
    detail.forEach((d, i) => {
      s += `<text x="${x + 12}" y="${top + 56 + i * 13}" font-size="9.5" fill="#6B7280">${esc(d)}</text>`;
    });
    return { svg: s, height: h };
  };
  const phase = (top, t) =>
    `<text x="8" y="${top}" font-size="10" font-weight="700" letter-spacing="1.2" fill="#6B7280">${esc(t.toUpperCase())}</text>`;
  const vArrow = (x, y1, y2) => `<line x1="${x}" y1="${y1}" x2="${x}" y2="${y2}" stroke="#9CA3AF" marker-end="url(#a)"/>`;
  const hArrow = (x1, x2, at) => `<line x1="${x1}" y1="${at}" x2="${x2}" y2="${at}" stroke="#9CA3AF" marker-end="url(#a)"/>`;

  const stage = (label, leftTitle, leftN, leftDetail, rightTitle, rightN, rightDetail, highlight) => {
    if (label) { body += phase(y, label); y += 16; }
    const l = box(LEFT, y, leftTitle, leftN, leftDetail || [], highlight);
    body += l.svg;
    let h = l.height;
    if (rightTitle != null) {
      const r = box(RIGHT, y, rightTitle, rightN, rightDetail || [], false);
      body += r.svg + hArrow(LEFT + BOX, RIGHT, y + 30);
      h = Math.max(h, r.height);
    }
    y += h;
  };
  const flowOn = () => { body += vArrow(LEFT + BOX / 2, y, y + 30); y += 38; };

  const sources = Object.entries(p.bySource).map(([k, v]) => `${k} (n = ${v})`);
  stage('Identification', 'Records identified from:', p.identified, sources,
        'Records removed before screening:', p.duplicates, ['Duplicate records removed (n = ' + p.duplicates + ')']);
  flowOn();
  stage('Screening', 'Records screened', p.screened, [], 'Records excluded', p.excludedScreening, []);
  flowOn();
  stage(null, 'Reports sought for retrieval', p.sought, [],
        'Reports not retrieved', p.notRetrieved, ['Including any with no PDF stored here']);
  flowOn();
  const reasons = Object.entries(p.reasons).map(([k, v]) => `${k} (n = ${v})`);
  stage(null, 'Reports assessed for eligibility', p.assessed, [], 'Reports excluded:', p.excludedFullText, reasons);
  flowOn();
  stage('Included', 'Studies included in review', p.included,
        [`Reports of included studies (n = ${p.included})`], null, 0, [], true);
  y += 26;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${Math.round(y)}" viewBox="0 0 ${W} ${Math.round(y)}" font-family="Helvetica, Arial, sans-serif">
<rect width="100%" height="100%" fill="#ffffff"/>
<defs><marker id="a" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#9CA3AF"/></marker></defs>
${body}</svg>`;
}

/// The same diagram as a raster, drawn through the browser rather than by hand, at 2× so it
/// survives being placed in a document.
export function prismaPNG(state, scale = 2) {
  return new Promise((resolve, reject) => {
    const svg = prismaSVG(state);
    const size = svg.match(/width="(\d+)" height="(\d+)"/);
    const w = Number(size?.[1] || 760), h = Number(size?.[2] || 900);
    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement('canvas');
      canvas.width = w * scale; canvas.height = h * scale;
      const g = canvas.getContext('2d');
      g.fillStyle = '#ffffff';
      g.fillRect(0, 0, canvas.width, canvas.height);
      g.drawImage(img, 0, 0, canvas.width, canvas.height);
      canvas.toBlob(b => (b ? resolve(b) : reject(new Error('Could not render the diagram'))), 'image/png');
    };
    img.onerror = () => reject(new Error('Could not render the diagram'));
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
  });
}

// ---------------------------------------------------------------- the reporting checklist

/// PRISMA 2020, the 27 items a journal will ask you to account for. Sieve fills in what it
/// can prove from your own data and leaves the rest for you to say where you reported it.
export const CHECKLIST = [
  ['Title', '1', 'Title', 'Identify the report as a systematic review.'],
  ['Abstract', '2', 'Abstract', 'See the PRISMA 2020 for Abstracts checklist.'],
  ['Introduction', '3', 'Rationale', 'Describe the rationale for the review in the context of existing knowledge.'],
  ['Introduction', '4', 'Objectives', 'Provide an explicit statement of the objective(s) or question(s) the review addresses.'],
  ['Methods', '5', 'Eligibility criteria', 'Specify the inclusion and exclusion criteria and how studies were grouped.'],
  ['Methods', '6', 'Information sources', 'Specify all databases, registers and other sources searched, and the date each was last searched.'],
  ['Methods', '7', 'Search strategy', 'Present the full search strategy for all databases, including any filters and limits.'],
  ['Methods', '8', 'Selection process', 'Specify the methods used to decide whether a study met the inclusion criteria.'],
  ['Methods', '9', 'Data collection process', 'Specify the methods used to collect data from reports.'],
  ['Methods', '10a', 'Data items', 'List and define all outcomes for which data were sought.'],
  ['Methods', '10b', 'Data items', 'List and define all other variables for which data were sought.'],
  ['Methods', '11', 'Risk of bias', 'Specify the methods used to assess risk of bias in the included studies.'],
  ['Methods', '12', 'Effect measures', 'Specify for each outcome the effect measure used in synthesis or presentation.'],
  ['Methods', '13a', 'Synthesis methods', 'Describe the processes used to decide which studies were eligible for each synthesis.'],
  ['Methods', '13b', 'Synthesis methods', 'Describe any methods required to prepare the data for presentation or synthesis.'],
  ['Methods', '13c', 'Synthesis methods', 'Describe any methods used to tabulate or visually display results.'],
  ['Methods', '14', 'Reporting bias', 'Describe any methods used to assess risk of bias due to missing results.'],
  ['Methods', '15', 'Certainty assessment', 'Describe any methods used to assess certainty in the body of evidence.'],
  ['Results', '16a', 'Study selection', 'Describe the results of the search and selection process, ideally using a flow diagram.'],
  ['Results', '16b', 'Study selection', 'Cite studies that met the inclusion criteria but were excluded, and explain why.'],
  ['Results', '17', 'Study characteristics', 'Cite each included study and present its characteristics.'],
  ['Results', '18', 'Risk of bias in studies', 'Present assessments of risk of bias for each included study.'],
  ['Results', '19', 'Results of individual studies', 'Present, for each study, summary statistics for each group.'],
  ['Results', '20', 'Results of syntheses', 'Present results of all statistical syntheses conducted.'],
  ['Discussion', '23', 'Discussion', 'Provide a general interpretation of the results and discuss limitations.'],
  ['Other', '24', 'Registration and protocol', 'Provide registration information, or state that the review was not registered.'],
  ['Other', '27', 'Data availability', 'Report which of the data, code and other materials are publicly available.'],
];

/// What Sieve can honestly say about an item from the review itself. Everything else is the
/// researcher's to answer — an app that ticked its own boxes would be worth nothing.
function checklistEvidence(state, id) {
  const p = prismaCounts(state);
  switch (id) {
    case '4': return state.project?.question || '';
    case '5': return [state.project?.inclusion && `Include if: ${state.project.inclusion}`,
                      state.project?.exclusion && `Exclude if: ${state.project.exclusion}`]
                      .filter(Boolean).join(' · ');
    case '6': return Object.entries(p.bySource).map(([k, v]) => `${k} (n = ${v})`).join('; ');
    case '7': return (state.searchRuns || []).map(r => `“${r.query}” — ${r.added} added`).join('; ');
    case '16a': return `Flow diagram produced: ${p.identified} identified → ${p.included} included.`;
    case '16b': return Object.entries(p.reasons).map(([k, v]) => `${k} (n = ${v})`).join('; ');
    case '17': return `${p.included} included studies, with extraction in the matrix.`;
    default: return '';
  }
}

export function checklistCSV(state) {
  const rows = [['Section', 'Item', 'Topic', 'Checklist item', 'What Sieve can show', 'Where you reported it']];
  for (const [section, id, topic, text] of CHECKLIST) {
    rows.push([section, id, topic, text, checklistEvidence(state, id), '']);
  }
  return csv(rows) + '\n\n' +
    csvCell('From: Page MJ, McKenzie JE, Bossuyt PM, et al. The PRISMA 2020 statement. BMJ 2021;372:n71.');
}

// ---------------------------------------------------------------- the review report

/// One document containing the whole review: the question, the criteria, the searches, the
/// flow diagram, every included paper with its evidence, the matrix, the frameworks and the
/// machine-assistance disclosure.
export function reportHTML(state, { forPrint = false } = {}) {
  const p = prismaCounts(state);
  const name = state.project?.name || 'Review';
  const included = state.sources.filter(s => s.stage === 'included');
  const marked = (id) => state.evidence.filter(e => e.sourceId === id);

  const section = (title, inner) => inner ? `<section><h2>${esc(title)}</h2>${inner}</section>` : '';
  const para = (t) => (t ? `<p>${esc(t)}</p>` : '');
  const table = (head, rows) => rows.length
    ? `<table><thead><tr>${head.map(h => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${
        rows.map(r => `<tr>${r.map(c => `<td>${esc(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`
    : '';

  let out = `<h1>${esc(name)}</h1>`;
  out += `<p class="sub">Systematic review workbook · produced by Sieve on ${esc(new Date().toLocaleString())}</p>`;
  out += section('Review question', para(state.project?.question) || '<p class="none">Not written yet.</p>');
  out += section('Eligibility criteria',
    (state.project?.inclusion ? `<h3>Include if</h3>${para(state.project.inclusion)}` : '') +
    (state.project?.exclusion ? `<h3>Exclude if</h3>${para(state.project.exclusion)}` : '') ||
    '<p class="none">Not written yet.</p>');

  out += section('Information sources', table(['Source', 'Records'],
    Object.entries(p.bySource).map(([k, v]) => [k, String(v)])));
  out += section('Search strategy', table(['Query', 'Records added', 'When'],
    (state.searchRuns || []).map(r => [r.query, String(r.added), new Date(r.at).toLocaleString()])));

  out += `<section class="flow"><h2>Study selection</h2>${prismaSVG(state)}
    <p class="cite">Page MJ, McKenzie JE, Bossuyt PM, et al. The PRISMA 2020 statement. BMJ 2021;372:n71.</p></section>`;

  out += section('Excluded at full text, with reasons', table(['Reason', 'Reports'],
    Object.entries(p.reasons).map(([k, v]) => [k, String(v)])));

  const studies = included.map(s => {
    const items = marked(s.id);
    let block = `<article><h3>${esc(s.title)}</h3><p class="ref">${esc(reference(s))}</p>`;
    if (s.conclusion) block += `<h4>Conclusion</h4>${para(s.conclusion)}`;
    if (s.notes) block += `<h4>My notes</h4>${para(s.notes)}`;
    if (items.length) {
      block += `<h4>Evidence (${items.length})</h4>`;
      for (const e of items) {
        block += `<blockquote style="border-color:${esc(e.color || '#999')}">${esc(e.quote)}
          <cite>p.${e.page + 1}${e.tag ? ' · ' + esc(e.tag) : ''} · ${esc(e.stance || 'evidence')}</cite>
          ${e.note ? `<span class="note">${esc(e.note)}</span>` : ''}</blockquote>`;
      }
    }
    return block + '</article>';
  }).join('');
  out += section(`Included studies (${included.length})`, studies || '<p class="none">Nothing included yet.</p>');

  // The extraction matrix, printed as it is filled in.
  if (state.columns.length && included.length) {
    const head = ['Study', ...state.columns.map(c => c.name)];
    const rows = included.map(s => [
      reference(s),
      ...state.columns.map(c => state.cells[`${s.id}-${c.id}`]?.value || ''),
    ]);
    out += section('Extraction matrix', table(head, rows));
  }

  for (const f of state.frames) {
    const rows = state.axes.filter(a => a.frameId === f.id && a.isRow);
    const cols = state.axes.filter(a => a.frameId === f.id && !a.isRow);
    if (!rows.length || !cols.length) continue;
    out += section(f.name, table(['', ...cols.map(c => c.name)],
      rows.map(r => [r.name, ...cols.map(c => state.frameCells[`${f.id}-${r.id}-${c.id}`]?.value || '')])));
  }

  const pending = state.aiEvents.filter(e => e.outcome === 'pending').length;
  out += section('Machine-assistance disclosure',
    `<p>No language model was used. This review was carried out in Sieve on the web, which runs entirely in the browser and has no assistant.</p>
     <p>Sieve derives some text mechanically — abstracts and conclusions read out of PDFs by pattern, titles guessed where a file carries no metadata, subject labels carried across from OpenAlex, and database records folded together when they appear to describe one paper. ${state.aiEvents.length} such item${state.aiEvents.length === 1 ? '' : 's'} ${state.aiEvents.length === 1 ? 'was' : 'were'} logged; ${pending === 0 ? 'every one was checked against its source by the researcher' : `${pending} ${pending === 1 ? 'has' : 'have'} not yet been checked`}.</p>`);

  out += section('References', `<ol class="refs">${
    state.sources.filter(s => s.stage === 'included' || s.stage === 'excludedFullText')
      .map(s => `<li>${esc(reference(s))}</li>`).join('')}</ol>`);

  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>${esc(name)} — review report</title>
<style>
  :root { color-scheme: light; }
  body { font: 12pt/1.55 Georgia, "Iowan Old Style", serif; color: #14161a; background: #fff;
         max-width: 46em; margin: 0 auto; padding: 40px 28px 80px; }
  h1 { font: 600 26pt/1.2 -apple-system, Helvetica, Arial, sans-serif; margin: 0 0 4px; }
  h2 { font: 600 15pt/1.3 -apple-system, Helvetica, Arial, sans-serif; margin: 34px 0 8px;
       padding-bottom: 5px; border-bottom: 1px solid #d8dbe0; }
  h3 { font: 600 12.5pt/1.35 -apple-system, Helvetica, Arial, sans-serif; margin: 20px 0 2px; }
  h4 { font: 600 10pt/1.3 -apple-system, Helvetica, Arial, sans-serif; margin: 12px 0 3px;
       text-transform: uppercase; letter-spacing: .06em; color: #5c6370; }
  p { margin: 0 0 9px; }
  .sub { font: 10pt -apple-system, Helvetica, Arial, sans-serif; color: #5c6370; margin-bottom: 20px; }
  .ref { font: 10pt -apple-system, Helvetica, Arial, sans-serif; color: #5c6370; }
  .none { color: #8a93a3; font-style: italic; }
  .cite { font: 9pt -apple-system, Helvetica, Arial, sans-serif; color: #8a93a3; }
  article { margin: 0 0 26px; page-break-inside: avoid; }
  blockquote { margin: 8px 0; padding: 2px 0 2px 12px; border-left: 3px solid #999; }
  blockquote cite { display: block; font: 9pt -apple-system, Helvetica, Arial, sans-serif;
                    color: #5c6370; font-style: normal; margin-top: 3px; }
  blockquote .note { display: block; font: 10pt -apple-system, Helvetica, Arial, sans-serif;
                     color: #14161a; margin-top: 4px; }
  table { border-collapse: collapse; width: 100%; font: 9.5pt -apple-system, Helvetica, Arial, sans-serif;
          margin: 8px 0; page-break-inside: avoid; }
  th, td { border: 1px solid #d8dbe0; padding: 5px 7px; text-align: left; vertical-align: top; }
  th { background: #f3f4f6; font-weight: 600; }
  .flow svg { max-width: 100%; height: auto; }
  ol.refs { font: 10pt -apple-system, Helvetica, Arial, sans-serif; padding-left: 1.4em; }
  ol.refs li { margin-bottom: 6px; }
  @media print { body { padding: 0; max-width: none; } h2 { page-break-after: avoid; } }
</style></head><body>${out}${
  forPrint ? '<script>window.addEventListener("load",()=>setTimeout(()=>window.print(),300))<\/script>' : ''
}</body></html>`;
}

/// Opens the report in its own window and asks the browser to print it. "Save as PDF" in the
/// print dialog gives a real, selectable, vector PDF — the browser's typesetter is better
/// than anything that would fit in this file.
export function printReport(state) {
  const w = window.open('', '_blank');
  if (!w) return false;
  w.document.write(reportHTML(state, { forPrint: true }));
  w.document.close();
  return true;
}

// ---------------------------------------------------------------- everything at once

/// One archive holding the PDFs, the report, the diagram, every table, the citation files and
/// a full backup. Nothing in it is a Sieve format you would be stuck inside.
export async function everythingZip(state, { onProgress } = {}) {
  const zip = new Zip();
  const name = safeName(state.project?.name || 'Review');
  const p = prismaCounts(state);

  onProgress?.('Writing the report…');
  await zip.add(`${name}/Report.html`, reportHTML(state));
  await zip.add(`${name}/PRISMA/PRISMA-flow.svg`, prismaSVG(state));
  await zip.add(`${name}/PRISMA/PRISMA-flow.txt`, prismaText(state, p));
  await zip.add(`${name}/PRISMA/PRISMA-2020-checklist.csv`, checklistCSV(state));
  try { await zip.add(`${name}/PRISMA/PRISMA-flow.png`, await prismaPNG(state)); } catch {}

  onProgress?.('Writing the tables…');
  await zip.add(`${name}/Data/sources.csv`, sourcesCSV(state));
  await zip.add(`${name}/Data/highlights.csv`, evidenceCSV(state));
  await zip.add(`${name}/Data/matrix.csv`, matrixCSV(state));
  await zip.add(`${name}/Data/ai-trail.csv`, trailCSV(state));
  await zip.add(`${name}/Citations/library.bib`, toBibTeX(state.sources));
  await zip.add(`${name}/Citations/library.ris`, toRIS(state.sources));

  onProgress?.('Packing the PDFs…');
  const used = new Set();
  const manifest = [];
  for (const s of state.sources) {
    const rec = await db.get('files', s.id);
    if (!rec?.blob) continue;
    let file = safeName(`${(s.authors || [])[0]?.split(' ').pop() || 'source'} ${s.year || ''} ${s.title}`) + '.pdf';
    while (used.has(file)) file = file.replace(/\.pdf$/, '') + '-1.pdf';
    used.add(file);
    await zip.add(`${name}/PDFs/${file}`, rec.blob);
    manifest.push({ sourceId: s.id, name: rec.name || file, path: `PDFs/${file}` });
  }

  // The index carries every store but not the PDF bytes — those are in PDFs/ as real files.
  // Restoring reads both, so the archive is a backup as well as a folder of documents, and
  // no 200MB paper has to survive a round trip through base64 to get here.
  onProgress?.('Writing the index…');
  const index = await db.exportAll({ withFiles: false });
  index.pdfManifest = manifest;
  await zip.add(`${name}/library.json`, JSON.stringify(index));
  await zip.add(`${name}/README.txt`, [
    `${state.project?.name || 'Review'} — exported from Sieve on ${new Date().toLocaleString()}`,
    '',
    '  Report.html          the whole review as one document. Open it in a browser and print',
    '                       to PDF if you want a PDF.',
    '  PRISMA/              the flow diagram as SVG and PNG, the counts as text, and the',
    '                       PRISMA 2020 reporting checklist as CSV.',
    '  Data/                sources, highlights, the extraction matrix and the machine-',
    '                       assistance trail, all as CSV.',
    '  Citations/           the library as BibTeX and RIS, for Zotero, Mendeley or a LaTeX bib.',
    '  PDFs/                every full text, as ordinary PDFs.',
    '  library.json         the index: every record, highlight, table and decision.',
    '',
    'This archive is also a backup. Restore in the sidebar takes it whole — the index and',
    'the PDFs — and puts the review back exactly as it was.',
    '',
    'None of this is a format you are stuck inside.',
  ].join('\n'));

  onProgress?.('Compressing…');
  return zip.finish();
}

// ---------------------------------------------------------------- the tables

export function sourcesCSV(state) {
  const rows = [['Title', 'Authors', 'Year', 'Venue', 'DOI', 'Stage', 'Reason', 'Source database',
                 'Found by search', 'Highlights', 'PDF stored', 'Added', 'URL']];
  for (const s of state.sources) {
    rows.push([s.title, (s.authors || []).join('; '), s.year, s.venue, s.doi,
      db.STAGES[s.stage]?.label || s.stage, s.reason, s.provider, s.foundBy,
      state.evidence.filter(e => e.sourceId === s.id).length, s.hasFile ? 'yes' : 'no',
      s.added, s.url]);
  }
  return csv(rows);
}

export function evidenceCSV(state) {
  const rows = [['Quote', 'Note', 'Category', 'Stance', 'Page', 'Source', 'Authors', 'Year', 'DOI', 'Recorded']];
  for (const e of state.evidence) {
    const s = state.sources.find(x => x.id === e.sourceId) || {};
    rows.push([e.quote, e.note, e.tag, e.stance, e.page + 1, s.title, (s.authors || []).join('; '),
               s.year, s.doi, e.created]);
  }
  return csv(rows);
}

export function matrixCSV(state) {
  const rows = state.sources.filter(s => s.stage === 'included');
  const head = ['Study', 'Authors', 'Year', ...state.columns.map(c => c.name)];
  return csv([head, ...rows.map(s => [
    s.title, (s.authors || []).join('; '), s.year,
    ...state.columns.map(c => state.cells[`${s.id}-${c.id}`]?.value || ''),
  ])]);
}

export function trailCSV(state) {
  const rows = [['When', 'Kind', 'Source', 'What it said', 'Produced by', 'Verdict', 'Checked']];
  for (const e of state.aiEvents) {
    const s = state.sources.find(x => x.id === e.sourceId);
    rows.push([e.at, db.TRAIL_KINDS[e.kind]?.label || e.kind, s?.title || '', e.said, e.by,
               db.TRAIL_OUTCOMES[e.outcome]?.label || e.outcome, e.outcomeAt || '']);
  }
  return csv(rows);
}
