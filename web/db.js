// Storage for Sieve on the web.
//
// Everything lives in this browser: records, highlights, tags and the PDF bytes themselves.
// There is no server and no account, which is deliberate — the desktop app's whole argument
// is that a review is yours and stays on your machine, and moving to a browser is no reason
// to hand it to somebody else's.
//
// IndexedDB holds it all, including the PDFs as blobs, so the app works with the network off
// and a backup is a single file you export and keep.

const DB_NAME = 'sieve';
const DB_VERSION = 3;

let dbp = null;

/// A browser will not upgrade a database while another tab still holds the old version open,
/// and when that happens the open request fires *nothing*: no success, no error, no timeout.
/// Anything awaiting it waits forever. The first shipped version registered no
/// `versionchange` handler to step aside with, so a second tab left open on it is enough to
/// wedge this one — which is why the failure is caught here and named rather than left to
/// look like an app that simply does not start.
export class LibraryBlocked extends Error {
  constructor() {
    super('Another tab still has an older version of Sieve open.');
    this.name = 'LibraryBlocked';
    this.blocked = true;
  }
}

export function open() {
  if (dbp) return dbp;
  dbp = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    let settled = false, upgrading = false;
    const finish = (fn, value) => { if (!settled) { settled = true; clearTimeout(watchdog); fn(value); } };
    // `onblocked` is the documented signal, and a timer is the backstop for browsers that
    // stay quiet. It is cancelled the moment an upgrade actually starts, because a large
    // library can take longer than this to migrate.
    const watchdog = setTimeout(() => { if (!upgrading) finish(reject, new LibraryBlocked()); }, 5000);
    req.onblocked = () => finish(reject, new LibraryBlocked());

    req.onupgradeneeded = () => {
      upgrading = true;
      clearTimeout(watchdog);
      const db = req.result;

      if (!db.objectStoreNames.contains('sources')) {
        const s = db.createObjectStore('sources', { keyPath: 'id', autoIncrement: true });
        s.createIndex('byKey', 'dedupeKey', { unique: false });
        s.createIndex('byStage', 'stage', { unique: false });
      }
      // PDF bytes are kept apart from the record so listing the library never loads them.
      if (!db.objectStoreNames.contains('files')) {
        db.createObjectStore('files', { keyPath: 'sourceId' });
      }
      if (!db.objectStoreNames.contains('evidence')) {
        const e = db.createObjectStore('evidence', { keyPath: 'id', autoIncrement: true });
        e.createIndex('bySource', 'sourceId', { unique: false });
      }
      if (!db.objectStoreNames.contains('tags')) {
        db.createObjectStore('tags', { keyPath: 'id', autoIncrement: true });
      }
      if (!db.objectStoreNames.contains('meta')) {
        db.createObjectStore('meta', { keyPath: 'key' });
      }

      // v2: a review is a container, the way it is on the desktop. Everything below hangs
      // off one, so two pieces of work never contaminate each other's PRISMA counts.
      if (!db.objectStoreNames.contains('projects')) {
        db.createObjectStore('projects', { keyPath: 'id', autoIncrement: true });
      }
      if (!db.objectStoreNames.contains('columns')) {
        db.createObjectStore('columns', { keyPath: 'id', autoIncrement: true });
      }
      if (!db.objectStoreNames.contains('cells')) {
        db.createObjectStore('cells', { keyPath: 'key' });           // "paper-column"
      }
      if (!db.objectStoreNames.contains('frames')) {
        db.createObjectStore('frames', { keyPath: 'id', autoIncrement: true });
      }
      if (!db.objectStoreNames.contains('axes')) {
        db.createObjectStore('axes', { keyPath: 'id', autoIncrement: true });
      }
      if (!db.objectStoreNames.contains('frameCells')) {
        db.createObjectStore('frameCells', { keyPath: 'key' });      // "frame-row-col"
      }
      if (!db.objectStoreNames.contains('searchRuns')) {
        db.createObjectStore('searchRuns', { keyPath: 'id', autoIncrement: true });
      }

      // v3: the method you are running, and the record of everything a machine wrote.
      if (!db.objectStoreNames.contains('methods')) {
        db.createObjectStore('methods', { keyPath: 'id', autoIncrement: true });
      }
      if (!db.objectStoreNames.contains('aiEvents')) {
        db.createObjectStore('aiEvents', { keyPath: 'id', autoIncrement: true });
      }
    };

    req.onsuccess = () => {
      const db = req.result;
      // Step aside for a future version rather than wedging it the way v1 wedged this one.
      db.onversionchange = () => { dbp = null; db.close(); };
      finish(resolve, db);
    };
    req.onerror = () => finish(reject, req.error);
  });
  // A failed open must not be remembered, or closing the other tab would not be enough to
  // recover — reloading has to be able to try again.
  dbp.catch(() => { dbp = null; });
  return dbp;
}

async function tx(store, mode, fn) {
  const db = await open();
  return new Promise((resolve, reject) => {
    const t = db.transaction(store, mode);
    const s = t.objectStore(store);
    let out;
    try { out = fn(s); } catch (err) { reject(err); return; }
    t.oncomplete = () => resolve(out && out.result !== undefined ? out.result : out);
    t.onerror = () => reject(t.error);
  });
}

export const put = (store, value) => tx(store, 'readwrite', s => s.put(value));
export const del = (store, key) => tx(store, 'readwrite', s => s.delete(key));
export const get = (store, key) => tx(store, 'readonly', s => s.get(key));
export const all = (store) => tx(store, 'readonly', s => s.getAll());

export async function byIndex(store, index, value) {
  const db = await open();
  return new Promise((resolve, reject) => {
    const t = db.transaction(store, 'readonly');
    const req = t.objectStore(store).index(index).getAll(value);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

// The categories a highlight can carry. Same defaults as the desktop app, and the colour is
// the category — that is the whole interaction.
export const STAGES = {
  identified:        { label: 'To screen',            color: 'var(--faint)' },
  duplicate:         { label: 'Duplicate',            color: 'var(--faint)' },
  excludedScreening: { label: 'Excluded · abstract',  color: 'var(--rose)' },
  sought:            { label: 'Full text wanted',     color: 'var(--accent)' },
  notRetrieved:      { label: 'Not retrieved',        color: 'var(--rose)' },
  excludedFullText:  { label: 'Excluded · full text', color: 'var(--rose)' },
  included:          { label: 'Included',             color: 'var(--emerald)' },
};

export const EXCLUSION_REASONS = [
  'Wrong population', 'Wrong intervention', 'Wrong outcome', 'Wrong study design',
  'Not peer reviewed', 'Not in English', 'Outside date range', 'Duplicate data',
  'No full text available', 'Off topic',
];

export const DEFAULT_TAGS = [
  { name: 'Definition',    color: '#4C8DF2', shortcut: '1', detail: 'How the source defines a key idea.' },
  { name: 'Method',        color: '#9B6BE8', shortcut: '2', detail: 'Design, sample, instrument, procedure.' },
  { name: 'Finding',       color: '#4CAF7D', shortcut: '3', detail: 'A result the authors actually report.' },
  { name: 'Limitation',    color: '#EF8A45', shortcut: '4', detail: 'What the work cannot claim.' },
  { name: 'Gap',           color: '#E86A9A', shortcut: '5', detail: 'Something unstudied — your opening.' },
  { name: 'Contradiction', color: '#E2564D', shortcut: '6', detail: 'Conflicts with another source.' },
  { name: 'Quote',         color: '#F2C14E', shortcut: '7', detail: 'Worth quoting verbatim.' },
  { name: 'Theory',        color: '#3FB8AF', shortcut: '8', detail: 'A frame or model invoked.' },
];

export const DEFAULT_COLUMNS = [
  ['Research question', 'What does this paper set out to answer?'],
  ['Method', 'Design, sample size, participants, instruments.'],
  ['Key findings', "The main results, in the authors' own terms."],
  ['Limitations', 'What the study cannot claim.'],
  ['Relevance to me', 'Why this matters for my question.'],
];

/// One step in a methodology. A method is an ordered list of these, so a researcher can build
/// the process their discipline actually uses instead of adopting the app's. Same set as the
/// desktop app, including which screen each step opens.
export const METHOD_BLOCKS = {
  search:     { label: 'Search',             view: 'find',      blurb: 'Query databases for candidate sources.' },
  import:     { label: 'Import',             view: 'library',   blurb: 'Bring in PDFs you already have.' },
  screen:     { label: 'Screen',             view: 'screening', blurb: 'Decide what is in and what is out, with reasons.' },
  retrieve:   { label: 'Retrieve full texts',view: 'library',   blurb: 'Get the full texts of what survived screening.' },
  read:       { label: 'Read',               view: 'reader',    blurb: 'Read the sources properly.' },
  highlight:  { label: 'Highlight',          view: 'reader',    blurb: 'Mark the passages that matter.' },
  code:       { label: 'Code',               view: 'reader',    blurb: 'Attach analytic codes to passages.' },
  tag:        { label: 'Tag',                view: 'tags',      blurb: 'Set up the categories you code with.' },
  memo:       { label: 'Memo',               view: 'reader',    blurb: 'Write your own thinking alongside the evidence.' },
  cluster:    { label: 'Cluster',            view: 'frames',    blurb: 'Group observations into themes.' },
  compare:    { label: 'Compare',            view: 'matrix',    blurb: 'Set findings side by side.' },
  relate:     { label: 'Relate',             view: 'map',       blurb: 'Link papers that cite the same work.' },
  vote:       { label: 'Vote',               view: 'screening', blurb: 'Rate or vote on what to include.' },
  rank:       { label: 'Rank',               view: 'matrix',    blurb: 'Order sources by importance.' },
  extract:    { label: 'Extract',            view: 'matrix',    blurb: 'Pull structured data into the matrix.' },
  frame:      { label: 'Frame it',           view: 'frames',    blurb: 'Lay the evidence into a method — SWOT, a journey map, an empathy map.' },
  synthesize: { label: 'Synthesize',         view: 'evidence',  blurb: 'Build the argument from the evidence.' },
  validate:   { label: 'Validate',           view: 'evidence',  blurb: 'Check claims against their sources.' },
  export:     { label: 'Export',             view: 'prisma',    blurb: 'Produce the report, diagram and data files.' },
};

/// The standard methodologies, shipped as editable recipes. They are templates, not rails:
/// adopting one copies its steps into the review, where they can be changed freely.
export const METHOD_PRESETS = [
  ['Systematic review (PRISMA)',
   'The full PRISMA 2020 process: a documented search, two-stage screening with recorded reasons, structured extraction and a flow diagram.',
   ['search','import','screen','retrieve','screen','extract','synthesize','export']],
  ['Scoping review',
   'Maps what exists on a topic rather than answering a narrow question. Charting replaces extraction; no risk-of-bias step.',
   ['search','import','screen','retrieve','extract','cluster','synthesize','export']],
  ['Literature review',
   'The ordinary reading-and-writing review: gather, read, code, and build the argument.',
   ['search','import','read','highlight','code','synthesize','export']],
  ['Thematic analysis',
   "Braun & Clarke's six phases: familiarise, code, search for themes, review, define, write up.",
   ['import','read','highlight','code','cluster','relate','validate','synthesize']],
  ['Grounded theory',
   'Open coding, then constant comparison and memoing until categories are saturated.',
   ['import','read','code','memo','compare','cluster','relate','synthesize']],
  ['Content analysis',
   'A fixed coding frame applied consistently, then counted.',
   ['tag','import','read','code','extract','compare','export']],
  ['Comparative analysis',
   'Set cases side by side on the same dimensions and read across them.',
   ['import','read','extract','compare','rank','synthesize','export']],
  ['Just reading',
   'Three steps. Open a paper, mark what matters, write a note.',
   ['read','highlight','memo']],
  ['UX research study',
   'Interviews and sessions rather than papers: collect, read, code what people said, cluster it, and lay it into a journey or empathy map that cites the quotes.',
   ['import','read','highlight','code','cluster','frame','synthesize','export']],
  ['Design research — discover',
   'The front half of a design project: find out what is true before deciding anything. Ends in a framing you can defend.',
   ['search','import','read','highlight','code','frame','validate','synthesize']],
  ['Competitive and positioning',
   'Look at what already exists, compare it on the same dimensions, and work out where the gap is.',
   ['search','import','read','highlight','compare','frame','synthesize','export']],
];

/// What a machine wrote, and what the researcher decided about it.
///
/// A badge saying "this was generated" is enough to draw a label. It cannot answer the
/// question a supervisor or a reviewer will actually ask — *which* sentences came from a
/// machine, and did a human check them against the source? Rows are written once and only
/// ever edited to record the human's verdict.
export const TRAIL_KINDS = {
  extractSection: { label: 'Section pulled out of a PDF', adjudicate: true,
                    detail: 'Read out of the file by pattern, not by a person.' },
  labelSDG:       { label: 'Subject labels attached',     adjudicate: true,
                    detail: "OpenAlex's own classifier, not the authors' words." },
  mergeRecords:   { label: 'Records folded together',     adjudicate: true,
                    detail: 'Two database records judged to describe one paper.' },
  guessTitle:     { label: 'Title guessed from the page', adjudicate: true,
                    detail: 'Taken from the first plausible line, with no metadata to check it.' },
  assistant:      { label: 'Assistant suggestion',        adjudicate: true,
                    detail: 'Restored from a desktop review.' },
};

export const TRAIL_OUTCOMES = {
  pending:  { label: 'Not yet checked',        color: 'var(--amber)' },
  accepted: { label: 'Accepted as given',      color: 'var(--accent)' },
  edited:   { label: 'Accepted after editing', color: 'var(--emerald)' },
  rejected: { label: 'Rejected',               color: 'var(--rose)' },
  unused:   { label: 'Read, not used',         color: 'var(--faint)' },
};

/// Records one machine-written thing. Never called for anything the researcher typed.
export async function trail(projectId, kind, sourceId, said, extra = {}) {
  if (!said) return null;
  return put('aiEvents', {
    projectId, kind, sourceId: sourceId || 0, said: String(said).slice(0, 4000),
    outcome: 'pending', at: new Date().toISOString(), by: 'Sieve on the web (no model)',
    ...extra,
  });
}

/// Sets up a first review and its tags. Everything belongs to a review, including work that
/// existed before reviews did — that gets adopted rather than orphaned.
export async function seed() {
  let projects = await all('projects');
  if (!projects.length) {
    const id = await put('projects', {
      name: 'My first review', question: '', inclusion: '', exclusion: '',
      created: new Date().toISOString(),
    });
    projects = await all('projects');
    for (const [name, prompt] of DEFAULT_COLUMNS) await put('columns', { projectId: id, name, prompt });
    // Anything stored before this version had no review; adopt it into the first one.
    for (const store of ['sources', 'evidence', 'tags']) {
      for (const row of await all(store)) {
        if (row.projectId == null) { row.projectId = id; await put(store, row); }
      }
    }
  }
  const methods = await all('methods');
  if (!methods.length) {
    for (const [name, detail, blocks] of METHOD_PRESETS) {
      await put('methods', { projectId: null, name, detail, blocks, isTemplate: true, step: 0 });
    }
  }
  const tags = await all('tags');
  if (!tags.length) {
    for (const t of DEFAULT_TAGS) await put('tags', { ...t, projectId: projects[0].id, kind: 'type' });
  }
  return projects;
}

export async function addProject(name) {
  const id = await put('projects', {
    name, question: '', inclusion: '', exclusion: '', created: new Date().toISOString(),
  });
  for (const [n, prompt] of DEFAULT_COLUMNS) await put('columns', { projectId: id, name: n, prompt });
  for (const t of DEFAULT_TAGS) await put('tags', { ...t, projectId: id, kind: 'type' });
  return id;
}

/// A whole library as one JSON file. Owning your data means being able to walk away with it,
/// and that has to mean all of it — the matrix, the frameworks and the method included.
export const STORES = ['projects', 'sources', 'evidence', 'tags', 'columns', 'cells',
                       'frames', 'axes', 'frameCells', 'searchRuns', 'methods', 'aiEvents'];

export async function exportAll() {
  const out = { format: 'sieve-web/1', exported: new Date().toISOString() };
  for (const name of STORES) out[name] = await all(name);
  const encoded = [];
  for (const f of await all('files')) {
    const buf = await f.blob.arrayBuffer();
    let bin = '';
    const bytes = new Uint8Array(buf);
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) {
      bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    encoded.push({ sourceId: f.sourceId, name: f.name, base64: btoa(bin) });
  }
  out.files = encoded;
  return out;
}

export async function importAll(data) {
  if (!data || data.format !== 'sieve-web/1') throw new Error('Not a Sieve export.');
  for (const name of STORES) {
    for (const row of data[name] || []) await put(name, row);
  }
  for (const f of data.files || []) {
    const bin = atob(f.base64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    await put('files', { sourceId: f.sourceId, name: f.name, blob: new Blob([bytes], { type: 'application/pdf' }) });
  }
}

/// How much room the browser has given us, and how much is used. Worth showing, because a
/// library of PDFs in IndexedDB is not weightless.
export async function usage() {
  if (!navigator.storage || !navigator.storage.estimate) return null;
  const { usage, quota } = await navigator.storage.estimate();
  return { usage, quota };
}
