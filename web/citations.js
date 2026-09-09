// Reading and writing citation files.
//
// Some of the best places to search cannot be searched from here. Google Scholar forbids
// automated querying outright, BASE restricts its API to registered institutions, and the
// big publishers keep search behind institutional agreements. Pretending otherwise would
// mean scraping them, which is both against their terms and fragile.
//
// So Sieve does what the desktop app does: it builds the search URL, opens it, and takes the
// .bib or .ris you export back. The reference is then a real record in your library, with its
// provenance saying it came from a file rather than from an API.

const clean = (s) => String(s || '')
  .replace(/[{}]/g, '')
  .replace(/\\[a-zA-Z]+\{?([^}]*)\}?/g, '$1')
  .replace(/\s+/g, ' ')
  .trim();

/// "Family, Given" and "Given Family" both appear in the wild, often in the same file.
function personName(raw) {
  const t = clean(raw);
  if (!t.includes(',')) return t;
  const [family, given] = t.split(',');
  return `${(given || '').trim()} ${family.trim()}`.trim();
}

export const EXTERNAL_SITES = [
  { id: 'gscholar', name: 'Google Scholar',
    blurb: 'The broadest free index — but it has no API, and automated querying is against its terms.',
    template: 'https://scholar.google.com/scholar?q={q}',
    howTo: 'Under a result, click the quotation mark → BibTeX → save the file → bring it back here.' },
  { id: 'base', name: 'BASE',
    blurb: '300M+ open-access documents. Its API is restricted to registered institutions.',
    template: 'https://www.base-search.net/Search/Results?lookfor={q}',
    howTo: 'Tick the results you want → Export → RIS.' },
  { id: 'scopus', name: 'Scopus',
    blurb: 'Elsevier’s index. Needs your institution’s login.',
    template: 'https://www.scopus.com/results/results.uri?st1={q}',
    howTo: 'Select results → Export → BibTeX or RIS.' },
  { id: 'wos', name: 'Web of Science',
    blurb: 'Clarivate’s index. Needs your institution’s login.',
    template: 'https://www.webofscience.com/wos/woscc/basic-search',
    howTo: 'Search there → Export → BibTeX.' },
  { id: 'ieee', name: 'IEEE Xplore',
    blurb: 'Engineering, computing, electronics.',
    template: 'https://ieeexplore.ieee.org/search/searchresult.jsp?queryText={q}',
    howTo: 'Select results → Export → Citations → BibTeX.' },
  { id: 'acm', name: 'ACM Digital Library',
    blurb: 'Computing and human–computer interaction.',
    template: 'https://dl.acm.org/action/doSearch?AllField={q}',
    howTo: 'Select results → Export Citations → BibTeX.' },
  { id: 'sciencedirect', name: 'ScienceDirect',
    blurb: 'Elsevier — science, technology, medicine, social sciences.',
    template: 'https://www.sciencedirect.com/search?qs={q}',
    howTo: 'Select results → Export → BibTeX.' },
  { id: 'springer', name: 'SpringerLink',
    blurb: 'Broad and multidisciplinary.',
    template: 'https://link.springer.com/search?query={q}',
    howTo: 'Open an article → Cite this article → download the .bib.' },
  { id: 'jstor', name: 'JSTOR',
    blurb: 'Humanities, art and design history, social sciences.',
    template: 'https://www.jstor.org/action/doBasicSearch?Query={q}',
    howTo: 'Select items → Export a RIS file.' },
];

export function siteURL(site, query) {
  return site.template.replace('{q}', encodeURIComponent(query || ''));
}

// ---------------------------------------------------------------- reading

/// Parses a .bib file well enough for real exports from Zotero, Mendeley and Google Scholar.
export function parseBibTeX(text) {
  const hits = [];
  const entries = String(text).split(/\n\s*@/).map((s, i) => (i === 0 ? s : '@' + s));
  for (const raw of entries) {
    if (!raw.trim().startsWith('@')) continue;
    const open = raw.indexOf('{');
    if (open < 0) continue;
    let body = raw.slice(open + 1);
    const firstComma = body.indexOf(',');       // drop the cite key
    if (firstComma >= 0) body = body.slice(firstComma + 1);

    const fields = {};
    let key = '', value = '', depth = 0, readingKey = true, inQuote = false;
    const commit = () => {
      const k = key.trim().toLowerCase();
      if (k) fields[k] = value.trim().replace(/^[{"\s]+|[}"\s,]+$/g, '');
      key = ''; value = ''; readingKey = true;
    };
    for (const ch of body) {
      if (readingKey) {
        if (ch === '=') { readingKey = false; value = ''; }
        else if (ch === ',' && depth === 0) key = '';
        else key += ch;
        continue;
      }
      if (ch === '{') { depth++; if (depth === 1) continue; }
      if (ch === '}') { depth--; if (depth === 0) continue; if (depth < 0) break; }
      if (ch === '"' && depth === 0) { inQuote = !inQuote; continue; }
      if (ch === ',' && depth === 0 && !inQuote) { commit(); continue; }
      value += ch;
    }
    commit();

    const title = clean(fields.title);
    if (!title) continue;
    hits.push({
      title,
      authors: (fields.author || '').split(/\s+and\s+/).map(personName).filter(Boolean),
      year: Number(String(clean(fields.year)).slice(0, 4)) || null,
      venue: clean(fields.journal || fields.booktitle || fields.publisher || ''),
      doi: clean(fields.doi).toLowerCase().replace(/^https?:\/\/(dx\.)?doi\.org\//, ''),
      abstract: clean(fields.abstract),
      url: clean(fields.url),
      pdfURL: '', provider: 'BibTeX file', sdgs: [], citedBy: 0,
      openAlexId: '', references: [],
    });
  }
  return hits;
}

export function parseRIS(text) {
  const hits = [];
  let cur = {};
  const push = (tag, v) => { (cur[tag] ||= []).push(v); };
  const flush = () => {
    const title = (cur.TI || cur.T1 || cur.BT || [])[0];
    if (title) {
      hits.push({
        title: clean(title),
        authors: [...(cur.AU || []), ...(cur.A1 || [])].map(personName).filter(Boolean),
        year: Number(String((cur.PY || cur.Y1 || cur.DA || [''])[0]).slice(0, 4)) || null,
        venue: clean((cur.JO || cur.JF || cur.T2 || cur.PB || [''])[0]),
        doi: clean((cur.DO || [''])[0]).toLowerCase().replace(/^https?:\/\/(dx\.)?doi\.org\//, ''),
        abstract: clean((cur.AB || cur.N2 || [''])[0]),
        url: clean((cur.UR || [''])[0]),
        pdfURL: clean((cur.L1 || cur.L2 || [''])[0]),
        provider: 'RIS file', sdgs: [], citedBy: 0, openAlexId: '', references: [],
      });
    }
    cur = {};
  };
  let lastTag = null;
  for (const line of String(text).split(/\r?\n/)) {
    const m = line.match(/^([A-Z][A-Z0-9])\s{2}-\s?(.*)$/);
    if (m) {
      lastTag = m[1];
      if (lastTag === 'ER') { flush(); lastTag = null; continue; }
      push(lastTag, m[2].trim());
    } else if (lastTag && line.trim()) {
      // A wrapped continuation line belongs to the tag above it.
      const list = cur[lastTag];
      if (list?.length) list[list.length - 1] += ' ' + line.trim();
    }
  }
  flush();
  return hits;
}

/// Picks the parser from the content, not the extension — files are routinely misnamed.
export function parseCitations(text, name = '') {
  const looksRIS = /^\s*TY\s{2}-/m.test(text) || /\.ris$/i.test(name);
  const looksBib = /@\w+\s*\{/.test(text) || /\.bibs?$/i.test(name);
  if (looksRIS && !looksBib) return parseRIS(text);
  if (looksBib) return parseBibTeX(text);
  return [];
}

// ---------------------------------------------------------------- writing

const bibKey = (s, used) => {
  const surname = ((s.authors || [])[0] || 'anon').split(/\s+/).pop().replace(/[^A-Za-z]/g, '') || 'anon';
  const word = (s.title || '').split(/\s+/).find(w => w.length > 4)?.replace(/[^A-Za-z]/g, '') || '';
  let key = `${surname}${s.year || 'nd'}${word.slice(0, 8)}`.toLowerCase();
  while (used.has(key)) key += 'a';
  used.add(key);
  return key;
};

export function toBibTeX(sources) {
  const used = new Set();
  const esc = v => String(v || '').replace(/[{}]/g, '');
  return sources.map(s => {
    const lines = [
      ['title', esc(s.title)],
      ['author', (s.authors || []).join(' and ')],
      ['year', s.year || ''],
      ['journal', esc(s.venue)],
      ['doi', s.doi || ''],
      ['url', s.url || ''],
      ['abstract', esc(s.abstract)],
      ['note', s.provider ? `Found via ${s.provider}` : ''],
    ].filter(([, v]) => String(v).length);
    return `@article{${bibKey(s, used)},\n` +
      lines.map(([k, v]) => `  ${k} = {${v}}`).join(',\n') + '\n}';
  }).join('\n\n') + '\n';
}

export function toRIS(sources) {
  return sources.map(s => {
    const L = ['TY  - JOUR'];
    for (const a of s.authors || []) L.push(`AU  - ${a}`);
    L.push(`TI  - ${s.title || ''}`);
    if (s.year) L.push(`PY  - ${s.year}`);
    if (s.venue) L.push(`JO  - ${s.venue}`);
    if (s.doi) L.push(`DO  - ${s.doi}`);
    if (s.url) L.push(`UR  - ${s.url}`);
    if (s.abstract) L.push(`AB  - ${s.abstract}`);
    L.push('ER  - ');
    return L.join('\n');
  }).join('\n\n') + '\n';
}
