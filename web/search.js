// Searching the academic databases from a browser.
//
// The desktop app queries fourteen sources. A browser can only reach hosts that send CORS
// headers, and that was tested from the deployed origin rather than assumed: seven answer,
// two refuse outright. CORE and arXiv send no CORS header at all, so they are listed as
// unavailable here rather than failing silently on every search.
//
// Everything else is the same idea as the desktop version: fire at all of them at once, and
// fold records describing the same paper into one row so you screen each paper once.

const enc = encodeURIComponent;

const str = v => (typeof v === 'string' ? v : '');
const arr = v => (Array.isArray(v) ? v : []);
const dict = v => (v && typeof v === 'object' ? v : {});

function cleanDOI(s) {
  let d = str(s).toLowerCase();
  for (const p of ['https://doi.org/', 'http://doi.org/', 'https://dx.doi.org/', 'doi:']) {
    if (d.startsWith(p)) d = d.slice(p.length);
  }
  return d.trim();
}
const strip = s => str(s).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();

/// Same rule as the desktop app. Year is left out of the title key on purpose: the same
/// paper is routinely dated a year apart across databases because of online-first publishing.
export function dedupeKey({ doi, title, year }) {
  const d = cleanDOI(doi);
  if (d) return 'doi:' + d;
  const t = str(title).toLowerCase().replace(/[^a-z0-9]/g, '');
  return t.length >= 25 ? 't:' + t.slice(0, 90) : 't:' + t + ':' + (year || '');
}

async function json(url, signal) {
  const res = await fetch(url, { signal });
  if (!res.ok) throw new Error('HTTP ' + res.status);
  return res.json();
}

export const PROVIDERS = [
  {
    name: 'OpenAlex', blurb: '250M works · finds the free PDF · supplies SDGs',
    async search(q, limit, signal) {
      const d = await json(`https://api.openalex.org/works?search=${enc(q)}&per-page=${limit}`, signal);
      const shortId = (u) => str(u).replace('https://openalex.org/', '');
      return arr(d.results).map(w => {
        const loc = dict(w.best_oa_location || w.primary_location);
        return {
          title: strip(w.display_name), doi: cleanDOI(w.doi),
          authors: arr(w.authorships).map(a => str(dict(a.author).display_name)).filter(Boolean),
          year: w.publication_year || null,
          venue: str(dict(loc.source).display_name),
          abstract: invertedAbstract(w.abstract_inverted_index),
          url: w.doi ? 'https://doi.org/' + cleanDOI(w.doi) : str(loc.landing_page_url),
          pdfURL: str(loc.pdf_url), citedBy: w.cited_by_count || 0, provider: 'OpenAlex',
          // The reference list is what the citation map is drawn from. It comes free with
          // the record, so taking it here means the map needs no extra request later.
          openAlexId: shortId(w.id),
          references: arr(w.referenced_works).map(shortId).filter(Boolean),
          sdgs: arr(w.sustainable_development_goals).filter(g => (g.score || 0) >= 0.4)
                  .map(g => str(g.display_name)),
        };
      });
    },
  },
  {
    name: 'Crossref', blurb: 'The DOI registry · authoritative records',
    async search(q, limit, signal) {
      const d = await json(`https://api.crossref.org/works?query=${enc(q)}&rows=${limit}&select=DOI,title,author,issued,container-title,abstract,URL,is-referenced-by-count,link`, signal);
      return arr(dict(d.message).items).map(w => ({
        title: strip(arr(w.title)[0]), doi: cleanDOI(w.DOI),
        authors: arr(w.author).map(a => [str(a.given), str(a.family)].filter(Boolean).join(' ')).filter(Boolean),
        year: arr(arr(dict(w.issued)['date-parts'])[0])[0] || null,
        venue: str(arr(w['container-title'])[0]),
        abstract: strip(w.abstract), url: str(w.URL),
        pdfURL: str(dict(arr(w.link).find(l => str(l['content-type']) === 'application/pdf')).URL),
        citedBy: w['is-referenced-by-count'] || 0, provider: 'Crossref', sdgs: [],
      })).filter(x => x.title);
    },
  },
  {
    name: 'Europe PMC', blurb: 'All of PubMed/MEDLINE plus preprints',
    async search(q, limit, signal) {
      const d = await json(`https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=${enc(q)}&format=json&pageSize=${limit}&resultType=core`, signal);
      return arr(dict(d.resultList).result).map(w => ({
        title: strip(w.title), doi: cleanDOI(w.doi),
        authors: arr(dict(w.authorList).author).map(a => str(a.fullName)).filter(Boolean),
        year: Number(w.pubYear) || null, venue: str(w.journalTitle),
        abstract: strip(w.abstractText),
        url: w.doi ? 'https://doi.org/' + cleanDOI(w.doi) : `https://europepmc.org/article/${str(w.source)}/${str(w.id)}`,
        pdfURL: w.pmcid ? `https://europepmc.org/articles/${str(w.pmcid)}?pdf=render` : '',
        citedBy: w.citedByCount || 0, provider: 'Europe PMC', sdgs: [],
      })).filter(x => x.title);
    },
  },
  {
    name: 'PubMed', blurb: 'MEDLINE · biomedical and life sciences',
    async search(q, limit, signal) {
      const s = await json(`https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&retmax=${limit}&sort=relevance&term=${enc(q)}`, signal);
      const ids = arr(dict(s.esearchresult).idlist);
      if (!ids.length) return [];
      const d = await json(`https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&retmode=json&id=${ids.join(',')}`, signal);
      const r = dict(d.result);
      return ids.map(id => {
        const w = dict(r[id]);
        const doi = str(dict(arr(w.articleids).find(a => str(a.idtype) === 'doi')).value);
        const pmc = str(dict(arr(w.articleids).find(a => str(a.idtype) === 'pmcid')).value);
        return {
          title: strip(w.title), doi: cleanDOI(doi),
          authors: arr(w.authors).map(a => str(a.name)).filter(Boolean),
          year: Number(str(w.pubdate).slice(0, 4)) || null,
          venue: str(w.fulljournalname) || str(w.source), abstract: '',
          url: `https://pubmed.ncbi.nlm.nih.gov/${id}/`,
          pdfURL: pmc ? `https://www.ncbi.nlm.nih.gov/pmc/articles/${pmc}/pdf/` : '',
          citedBy: 0, provider: 'PubMed', sdgs: [],
        };
      }).filter(x => x.title);
    },
  },
  {
    name: 'DOAJ', blurb: 'Open-access journals · design and humanities',
    async search(q, limit, signal) {
      const d = await json(`https://doaj.org/api/search/articles/${enc(q)}?pageSize=${limit}`, signal);
      return arr(d.results).map(r => {
        const w = dict(dict(r).bibjson);
        const doi = cleanDOI(str(dict(arr(w.identifier).find(i => str(i.type) === 'doi')).id));
        const link = dict(arr(w.link).find(l => str(l.type) === 'fulltext'));
        return {
          title: strip(w.title), doi,
          authors: arr(w.author).map(a => str(a.name)).filter(Boolean),
          year: Number(w.year) || null, venue: str(dict(w.journal).title),
          abstract: strip(w.abstract),
          url: str(link.url) || (doi ? 'https://doi.org/' + doi : ''),
          pdfURL: str(link.content_type).toLowerCase().includes('pdf') ? str(link.url) : '',
          citedBy: 0, provider: 'DOAJ', sdgs: [],
        };
      }).filter(x => x.title);
    },
  },
  {
    name: 'PLOS', blurb: 'Fully open-access science journals',
    async search(q, limit, signal) {
      const d = await json(`https://api.plos.org/search?q=${enc(q)}&rows=${limit}&wt=json&fl=id,title_display,author_display,journal,publication_date,abstract`, signal);
      return arr(dict(d.response).docs).map(w => {
        const doi = cleanDOI(w.id);
        return {
          title: strip(w.title_display), doi,
          authors: arr(w.author_display), year: Number(str(w.publication_date).slice(0, 4)) || null,
          venue: str(w.journal), abstract: strip(arr(w.abstract).join(' ')),
          url: 'https://doi.org/' + doi,
          pdfURL: `https://journals.plos.org/plosone/article/file?id=${doi}&type=printable`,
          citedBy: 0, provider: 'PLOS', sdgs: [],
        };
      }).filter(x => x.title && x.doi.startsWith('10.'));
    },
  },
  {
    name: 'OpenAIRE', blurb: 'Thousands of repositories · European aggregator',
    async search(q, limit, signal) {
      const d = await json(`https://api.openaire.eu/search/publications?keywords=${enc(q)}&size=${limit}&format=json`, signal);
      const results = arr(dict(dict(dict(d).response).results).result);
      const text = v => {
        if (typeof v === 'string') return v;
        if (Array.isArray(v)) return v.length ? text(v[0]) : '';
        if (v && typeof v === 'object') return text(v.$ ?? v.value ?? '');
        return '';
      };
      const list = v => (Array.isArray(v) ? v : v ? [v] : []);
      return results.map(r => {
        const m = dict(dict(dict(dict(r).metadata)['oaf:entity'])['oaf:result']);
        const doi = cleanDOI(text(list(m.pid).find(p => text(dict(p)['@classid']) === 'doi') || list(m.pid)[0]));
        const date = text(m.dateofacceptance);
        return {
          title: strip(text(m.title)),
          doi: doi.startsWith('10.') ? doi : '',
          authors: list(m.creator).map(text).filter(Boolean),
          year: Number(date.slice(0, 4)) || null, venue: text(m.publisher),
          abstract: strip(text(m.description)),
          url: doi.startsWith('10.') ? 'https://doi.org/' + doi : '', pdfURL: '',
          citedBy: 0, provider: 'OpenAIRE', sdgs: [],
        };
      }).filter(x => x.title);
    },
  },
];

/// Sources a browser cannot reach. Named rather than hidden, so the absence is explained.
export const BLOCKED = [
  { name: 'CORE', why: 'sends no CORS header, so a browser cannot read its response' },
  { name: 'arXiv', why: 'sends no CORS header' },
  { name: 'Semantic Scholar', why: 'needs an API key' },
  { name: 'IEEE · Springer · ScienceDirect · Lens', why: 'need paid or registered API keys' },
];

export function invertedAbstract(inv) {
  if (!inv || typeof inv !== 'object') return '';
  const words = [];
  for (const [word, positions] of Object.entries(inv)) {
    for (const p of positions) words.push([p, word]);
  }
  return words.sort((a, b) => a[0] - b[0]).map(w => w[1]).join(' ');
}

/// Folds records describing the same paper into one, keeping the richest field from each —
/// so a Crossref record can inherit OpenAlex's abstract and Europe PMC's free PDF.
export function merge(hits) {
  const byKey = new Map();
  for (const h of hits) {
    const k = dedupeKey(h);
    const existing = byKey.get(k);
    if (!existing) {
      byKey.set(k, { ...h, openAlexId: h.openAlexId || '', references: h.references || [], alsoFrom: [] });
      continue;
    }
    if (existing.provider !== h.provider && !existing.alsoFrom.includes(h.provider)) {
      existing.alsoFrom.push(h.provider);
    }
    if (existing.abstract.length < h.abstract.length) existing.abstract = h.abstract;
    if (!existing.pdfURL) existing.pdfURL = h.pdfURL;
    if (!existing.doi) existing.doi = h.doi;
    if (!existing.venue) existing.venue = h.venue;
    if (!existing.url) existing.url = h.url;
    if (!existing.year) existing.year = h.year;
    if (existing.authors.length < h.authors.length) existing.authors = h.authors;
    if (existing.citedBy < h.citedBy) existing.citedBy = h.citedBy;
    if (!existing.sdgs.length) existing.sdgs = h.sdgs;
    if (!existing.openAlexId) existing.openAlexId = h.openAlexId || '';
    if (!(existing.references || []).length) existing.references = h.references || [];
  }
  return [...byKey.values()];
}

/// Runs every enabled provider at once, reporting each as it lands so results stream in and
/// one slow or broken source never holds up the rest.
export async function searchAll(query, { enabled, limit = 20, onProgress, signal } = {}) {
  const active = PROVIDERS.filter(p => !enabled || enabled.has(p.name));
  let collected = [];
  await Promise.all(active.map(async (p) => {
    onProgress?.(p.name, { state: 'running' });
    try {
      const hits = await p.search(query, limit, signal);
      collected = collected.concat(hits);
      onProgress?.(p.name, { state: 'done', count: hits.length, merged: merge(collected) });
    } catch (err) {
      onProgress?.(p.name, { state: 'failed', error: err.name === 'AbortError' ? 'cancelled' : 'unreachable' });
    }
  }));
  return merge(collected);
}
