// Getting the full text.
//
// The desktop app can download any PDF it has a URL for. A browser cannot: a page may only
// read a file from another site if that site sends a CORS header saying so, and most
// publishers do not. That is a rule of the web, not a gap in this app, and no amount of
// effort here removes it.
//
// What can be done is worth doing properly, and it is more than nothing:
//
//   1. Ask OpenAlex and Unpaywall — both of which do allow cross-origin reads — where a
//      legal free copy of this DOI lives. Between them they know about most of them.
//   2. Try each copy in turn. Repositories (Europe PMC, arXiv, PubMed Central, university
//      archives) mostly do send the header; publishers mostly do not, so repositories are
//      tried first.
//   3. If every copy refuses, open the best one in a tab and say plainly what to do with it.
//
// Nothing is uploaded and nothing is proxied through a third party: the file goes from the
// repository to this browser and no further.

const PDF_MAGIC = '%PDF';

/// Repository copies are tried before publisher copies, because a repository is far more
/// likely to allow a cross-origin read, and its PDF is the same paper.
const REPOSITORY = /(europepmc|ncbi\.nlm\.nih\.gov|arxiv\.org|biorxiv|medrxiv|osf\.io|zenodo|hal\.|repec|core\.ac\.uk|dspace|eprints|diva-portal|semanticscholar)/i;

function rank(url) {
  if (!url) return 99;
  if (REPOSITORY.test(url)) return 0;
  if (/\.pdf($|\?)/i.test(url)) return 1;
  return 2;
}

/// Every free copy anyone knows about, best candidate first.
export async function findCopies(source) {
  const out = [];
  const add = (url, from) => {
    const u = String(url || '').trim();
    if (u.startsWith('http') && !out.some(c => c.url === u)) out.push({ url: u, from });
  };
  add(source.pdfURL, 'the record');

  const doi = (source.doi || '').trim();
  const oaId = (source.openAlexId || '').trim();
  if (doi || oaId) {
    try {
      const key = oaId ? oaId : `doi:${encodeURIComponent(doi)}`;
      const res = await fetch(`https://api.openalex.org/works/${key}?select=id,doi,best_oa_location,locations`);
      if (res.ok) {
        const w = await res.json();
        add(w.best_oa_location?.pdf_url, 'OpenAlex');
        for (const loc of w.locations || []) add(loc.pdf_url, 'OpenAlex');
      }
    } catch { /* a lookup that fails is one fewer candidate, not an error */ }
  }
  if (doi) {
    try {
      // Unpaywall asks for an address as a courtesy identifier; its own is the documented
      // one to use, and no address of the researcher's is sent anywhere.
      const res = await fetch(`https://api.unpaywall.org/v2/${encodeURIComponent(doi)}?email=unpaywall@impactstory.org`);
      if (res.ok) {
        const w = await res.json();
        add(w.best_oa_location?.url_for_pdf, 'Unpaywall');
        for (const loc of w.oa_locations || []) add(loc.url_for_pdf, 'Unpaywall');
      }
    } catch { /* likewise */ }
  }
  return out.sort((a, b) => rank(a.url) - rank(b.url));
}

/// Tries each copy until one lets us read it. Returns the bytes, or the list it could not
/// read so the caller can offer them as links.
export async function fetchFirstReadable(copies, onTry) {
  for (const copy of copies) {
    onTry?.(copy);
    try {
      const res = await fetch(copy.url, { redirect: 'follow' });
      if (!res.ok) continue;
      const buf = await res.arrayBuffer();
      if (buf.byteLength < 1000) continue;
      const head = new TextDecoder('latin1').decode(new Uint8Array(buf.slice(0, 5)));
      // A login wall or a "choose your institution" page is HTML with a .pdf URL.
      if (!head.startsWith(PDF_MAGIC)) continue;
      return { blob: new Blob([buf], { type: 'application/pdf' }), from: copy };
    } catch {
      // Almost always CORS. There is no way to tell that apart from a network failure from
      // inside the page — the browser deliberately does not say which.
    }
  }
  return null;
}

/// The whole attempt, as one call: find the copies, try them, and report honestly.
export async function retrieve(source, { onProgress } = {}) {
  onProgress?.('Looking for a free copy…');
  const copies = await findCopies(source);
  if (!copies.length) {
    return { ok: false, reason: 'none', copies: [] };
  }
  onProgress?.(`Trying ${copies.length} copy${copies.length === 1 ? '' : 's'}…`);
  const got = await fetchFirstReadable(copies, (c) => onProgress?.(`Trying ${host(c.url)}…`));
  if (got) return { ok: true, blob: got.blob, from: got.from, copies };
  return { ok: false, reason: 'blocked', copies };
}

export function host(url) {
  try { return new URL(url).host.replace(/^www\./, ''); } catch { return url; }
}
