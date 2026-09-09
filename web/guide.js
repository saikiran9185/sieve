// How to use Sieve.
//
// A tool that argues for a particular way of working owes the reader an account of it. This
// is that account: what each screen is for, in the order you would meet it, and — just as
// important — what the browser version cannot do and why, so nobody wastes an afternoon
// looking for a button that is not there.

import { el, chip } from './views.js';

const STEPS = [
  {
    view: 'settings', title: 'Start by writing the question',
    body: 'Settings holds the review question and the two criteria: include a paper if…, exclude a paper if…. They are not paperwork. Screening tints your inclusion words green and your exclusion words red inside every abstract, so the words a decision turns on are visible before you read a line. Written badly they do nothing; written well they do most of the screening for you.',
    tips: ['A criterion is a sentence you could hand to somebody else and get the same decisions back.'],
  },
  {
    view: 'find', title: 'Find papers',
    body: 'One query goes to seven databases at once — OpenAlex, Crossref, Europe PMC, PubMed, DOAJ, PLOS and OpenAIRE — and records describing the same paper are folded into one row, so you screen each paper once rather than once per database. Tick what looks relevant and add it; everything keeps the database it came from and the query that found it.',
    tips: [
      'Google Scholar, Scopus, Web of Science and the big publishers cannot be queried from a browser — Scholar forbids it outright and the rest need an institutional agreement. Sieve opens your search there instead and takes the .bib or .ris you export back, which is the same route the desktop app uses.',
      'Already have references in Zotero or Mendeley? Export .bib or .ris and drop the file anywhere on the page.',
    ],
  },
  {
    view: 'screening', title: 'Screen, with a reason for every no',
    body: 'A queue, one abstract at a time, with your criteria highlighted in it. F keeps a paper, 1–9 excludes it with that reason, J and K move. An exclusion always carries a reason because PRISMA item 16b requires one per excluded report, and a diagram assembled at the end from memory is not a record.',
    tips: ['Keep now, decide later is a real option — “Full text wanted” is a stage, not a verdict.'],
  },
  {
    view: 'library', title: 'Get the full texts',
    body: 'A record is not a paper. Get the PDF on any record asks OpenAlex and Unpaywall where a legal free copy lives and tries each one; repositories usually allow it, publishers usually do not. When every copy refuses, Sieve opens the best one in a tab — save it and drop it back on the page, and it attaches to the record it belongs to rather than becoming a second copy.',
    tips: [
      'Drag PDFs anywhere on the page at any time. They are matched by content, so dropping the same file twice does nothing.',
      'Sieve reads the abstract and the conclusion out of the file by pattern matching. That is a machine reading, not a person, so it is logged in the AI trail for you to check.',
    ],
  },
  {
    view: 'reader', title: 'Read, and take things out',
    body: 'Select a passage and press a number, or click a colour. Before that, choose what you are recording: Evidence is what the source says, Interpretation is what you think it means, Question is what you do not know yet. The same sentence marked as interpretation is your thinking, and the app will never let the two blur together in an export.',
    tips: [
      'Add a thought records an interpretation that belongs to no particular passage.',
      'The right panel has three tabs: what you took out, what the paper is and where it came from, and the include/exclude decision — so you never leave the page you are reading to decide.',
      'Press ? keys in the toolbar for the full list.',
    ],
  },
  {
    view: 'evidence', title: 'Look at the evidence on its own',
    body: 'Every highlight in the review, grouped by what it was recorded as, searchable, and exportable as Markdown or CSV. This is the screen where an argument starts to have a shape — and every quote still knows its page and its source.',
  },
  {
    view: 'matrix', title: 'Extract into the matrix',
    body: 'One row per included paper, one column per question you are asking all of them. The default columns are the usual ones — research question, method, findings, limitations, relevance — and you can change them. A cell can cite the highlights it came from, which is what makes the table defensible later.',
  },
  {
    view: 'frames', title: 'Lay it into a framework',
    body: 'SWOT, a journey map, an empathy map, a 2×2 — the shapes design research actually uses. The evidence underneath does not change; the framework is a way of looking at it, and each square can cite the quotes that put it there.',
  },
  {
    view: 'map', title: 'See how the papers connect',
    body: 'Every paper is a dot; a line means the two cite the same works, drawn from the reference lists OpenAlex publishes. Find what I’m missing then lists the works your own corpus keeps citing that you have not read. That is the one question a search box cannot answer for you.',
    tips: ['Records added without citation data can be filled in with Fetch reference lists.'],
  },
  {
    view: 'prisma', title: 'Produce the flow diagram',
    body: 'Counted from your actual decisions, not typed in. The diagram warns you while it is still wrong — records with no decision, exclusions with no reason — and exports as SVG, PNG, plain text, and the PRISMA 2020 reporting checklist.',
  },
  {
    view: 'trail', title: 'Account for what a machine wrote',
    body: 'There is no assistant here; running one would mean sending your library to somebody else’s computer. But Sieve still writes into your review without you — sections read out of a PDF, guessed titles, subject labels, merged records — and each is logged as a claim for you to accept, edit or reject. The disclosure export then says exactly which were checked.',
  },
  {
    view: 'method', title: 'Optional: pick a method',
    body: 'A method is an ordered list of steps you choose, not a workflow the app imposes. Adopt PRISMA, thematic analysis, grounded theory or a design-research recipe, edit its steps, or build one. Every screen stays reachable whatever you pick — the steps are a path, never a gate.',
  },
];

const SAFETY = [
  ['Everything is on this computer', 'No account, no server, nothing uploaded. Your sources, highlights and the PDF files themselves live in this browser.'],
  ['Which is why backing up matters', 'A browser is allowed to clear its own storage when a disk fills up. Keep a copy in a folder (Chrome and Edge) mirrors everything to a real folder as you work — PDFs as ordinary PDFs, the index as readable JSON. Back up writes the whole library to one file. The sidebar always says which state you are in.'],
  ['One review per topic', 'The button at the top of the sidebar switches reviews and makes new ones. Each is its own library: its own sources, highlights, matrix and PRISMA counts, with nothing crossing between them.'],
];

const LIMITS = [
  ['Google Scholar, Scopus, Web of Science, IEEE, ScienceDirect',
   'Cannot be queried from any browser. Scholar forbids automated querying; the others gate search behind institutional agreements. Find papers opens your search there and imports the .bib or .ris you export.'],
  ['CORE and arXiv',
   'Send no CORS header, so a browser cannot read their answers. The desktop app can.'],
  ['Downloading a PDF straight from a publisher',
   'A page may only read a file from another site if that site permits it, and most publishers do not. Sieve tries every free copy it can find first, and opens the rest for you to save and drop back.'],
  ['An AI assistant',
   'Deliberately absent. It would mean sending your library somewhere else, which is the one thing this app promises not to do.'],
];

export function render(ctx, root) {
  root.innerHTML = '';
  const wrap = el('div', 'list prose');

  const head = el('div');
  head.appendChild(el('h2', null, 'How to use Sieve'));
  head.appendChild(el('p', 'meta',
    'A literature review, end to end, in the order you would actually do it. Nothing here is compulsory — every screen works on its own.'));
  wrap.appendChild(head);

  wrap.appendChild(el('h3', 'section-label', 'The work, in order'));
  STEPS.forEach((step, i) => {
    const card = el('div', 'card guide-step');
    const title = el('div', 'guide-title');
    title.appendChild(el('span', 'step-n', String(i + 1)));
    title.appendChild(el('h4', null, step.title));
    title.appendChild(el('span', 'grow'));
    const go = el('button', 'quiet', 'Open →');
    go.onclick = () => ctx.go(step.view);
    title.appendChild(go);
    card.appendChild(title);
    card.appendChild(el('p', 'guide-body', step.body));
    for (const t of step.tips || []) {
      const tip = el('p', 'guide-tip', t);
      card.appendChild(tip);
    }
    wrap.appendChild(card);
  });

  wrap.appendChild(el('h3', 'section-label', 'Where your work lives'));
  for (const [title, body] of SAFETY) {
    const c = el('div', 'card');
    c.appendChild(el('h4', null, title));
    c.appendChild(el('div', 'meta', body));
    wrap.appendChild(c);
  }

  wrap.appendChild(el('h3', 'section-label', 'What a browser cannot do, and why'));
  const limits = el('div', 'card');
  limits.appendChild(el('div', 'meta',
    'Named rather than hidden, so you do not spend an afternoon looking for a button that is not there.'));
  for (const [what, why] of LIMITS) {
    const row = el('div', 'kv wide');
    row.appendChild(el('span', 'k', what));
    row.appendChild(el('span', 'v', why));
    limits.appendChild(row);
  }
  wrap.appendChild(limits);

  wrap.appendChild(el('h3', 'section-label', 'Keys'));
  const keys = el('div', 'card');
  for (const [k, what] of [
    ['1 – 8', 'Highlight the selection as that category'],
    ['E · I · Q', 'Record as evidence, interpretation or a question'],
    ['J · K', 'Next and previous paper, in the reader and in screening'],
    ['F', 'Keep this paper (screening)'],
    ['1 – 9', 'Exclude with that reason (screening)'],
    ['Esc', 'Drop the selection'],
  ]) {
    const row = el('div', 'kv');
    row.appendChild(el('kbd', null, k));
    row.appendChild(el('span', 'v', what));
    keys.appendChild(row);
  }
  wrap.appendChild(keys);

  const foot = el('p', 'hint');
  foot.textContent = 'There is also a macOS app, which adds the databases a browser cannot reach, folders and collections, and XLSX and Word export. Everything else is here.';
  wrap.appendChild(foot);

  root.appendChild(wrap);
}
