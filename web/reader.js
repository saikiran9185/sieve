// The reader: pdf.js for rendering, a text layer for selection, and highlights drawn back
// over the page.
//
// The desktop app gets highlighting free from PDFKit — it hands you per-line rectangles for
// a selection and writes annotations into the document. In a browser none of that exists, so
// this does the same job by hand: take the selection's client rectangles, express them as
// fractions of the page box so they survive zooming and re-rendering, and paint them back as
// positioned elements. Storing fractions rather than pixels is the part that matters; a
// highlight recorded at one zoom level has to land in the same place at another.

import * as pdfjs from './vendor/pdf.min.mjs';
pdfjs.GlobalWorkerOptions.workerSrc = new URL('./vendor/pdf.worker.min.mjs', import.meta.url).href;

export class Reader {
  constructor(container) {
    this.container = container;
    this.doc = null;
    this.scale = 1.35;
    this.pages = [];           // { pageNumber, wrapper, layer, viewport }
    this.onHighlight = null;   // called with { page, rects, quote }
    this.evidence = [];
    this.tagFor = () => null;
    this.matches = [];         // { page, index } for the find bar
    this.matchIndex = 0;
    this.currentPage = 0;
    this.onPageChange = null;
    this.observer = null;
  }

  async load(blob) {
    const data = new Uint8Array(await blob.arrayBuffer());
    this.doc = await pdfjs.getDocument({ data }).promise;
    await this.render();
    return this.doc.numPages;
  }

  async render() {
    this.container.innerHTML = '';
    this.pages = [];
    for (let n = 1; n <= this.doc.numPages; n++) {
      const page = await this.doc.getPage(n);
      const viewport = page.getViewport({ scale: this.scale });

      const wrapper = document.createElement('div');
      wrapper.className = 'page';
      wrapper.style.width = `${viewport.width}px`;
      wrapper.style.height = `${viewport.height}px`;
      wrapper.dataset.page = n;

      const canvas = document.createElement('canvas');
      const ratio = window.devicePixelRatio || 1;
      canvas.width = Math.floor(viewport.width * ratio);
      canvas.height = Math.floor(viewport.height * ratio);
      canvas.style.width = `${viewport.width}px`;
      canvas.style.height = `${viewport.height}px`;
      wrapper.appendChild(canvas);

      // Highlights sit under the text layer so selection still works over them.
      const marks = document.createElement('div');
      marks.className = 'marks';
      wrapper.appendChild(marks);

      const layer = document.createElement('div');
      layer.className = 'textLayer';
      layer.style.width = `${viewport.width}px`;
      layer.style.height = `${viewport.height}px`;
      wrapper.appendChild(layer);

      this.container.appendChild(wrapper);

      const ctx = canvas.getContext('2d');
      ctx.scale(ratio, ratio);
      await page.render({ canvasContext: ctx, viewport }).promise;

      // pdf.js 4 replaced the renderTextLayer() function with a TextLayer class, and the
      // layer positions its spans from a --scale-factor custom property rather than from the
      // viewport argument. Getting either wrong yields a layer with no spans in it, and
      // therefore a document you cannot select a word of.
      wrapper.style.setProperty('--scale-factor', String(this.scale));
      const text = await page.getTextContent();
      const textLayer = new pdfjs.TextLayer({ textContentSource: text, container: layer, viewport });
      await textLayer.render();

      const finds = document.createElement('div');
      finds.className = 'finds';
      wrapper.appendChild(finds);

      this.pages.push({ pageNumber: n, wrapper, marks, finds, layer, viewport });
    }
    this.drawAll();
    this.watchSelection();
    this.watchScroll();
  }

  /// Which page is in view, so the toolbar can say "3 / 21" the way the desktop app does.
  watchScroll() {
    this.observer?.disconnect();
    this.observer = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        const n = Number(e.target.dataset.page) - 1;
        if (n !== this.currentPage) { this.currentPage = n; this.onPageChange?.(n); }
      }
    }, { root: this.container, threshold: 0.5 });
    for (const p of this.pages) this.observer.observe(p.wrapper);
  }

  get pageCount() { return this.doc ? this.doc.numPages : 0; }

  /// Turns whatever is selected into page-relative fractions.
  ///
  /// A highlight belongs to one page, so a selection dragged past the bottom of one takes the
  /// page it started on and keeps only the rectangles that land there — the same rule PDFKit
  /// gives the desktop app for free. Returning nothing in that case is worse than useless: it
  /// is a drag that silently did not work.
  selectionGeometry() {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.rangeCount) return null;
    const quote = sel.toString().replace(/\s+/g, ' ').trim();
    if (quote.length < 2) return null;

    const range = sel.getRangeAt(0);
    const pageOf = (node) => {
      const start = node?.nodeType === Node.TEXT_NODE ? node.parentElement : node;
      return start?.closest?.('.page') || null;
    };
    const wrapper = pageOf(range.startContainer) || pageOf(range.commonAncestorContainer);
    if (!wrapper) return null;

    const box = wrapper.getBoundingClientRect();
    const rects = [];
    for (const r of range.getClientRects()) {
      if (r.width < 1 || r.height < 1) continue;
      // Only what falls on the page the selection started on.
      const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      if (cx < box.left || cx > box.right || cy < box.top || cy > box.bottom) continue;
      // A rectangle covering most of the page is the container itself, not a line of text.
      if (r.width > box.width * 0.98 && r.height > box.height * 0.5) continue;
      rects.push({
        x: (r.left - box.left) / box.width,
        y: (r.top - box.top) / box.height,
        w: r.width / box.width,
        h: r.height / box.height,
      });
    }
    if (!rects.length) return null;
    return { page: Number(wrapper.dataset.page) - 1, rects, quote };
  }

  watchSelection() {
    this.container.onmouseup = () => {
      const geo = this.selectionGeometry();
      if (this.onSelectionChange) this.onSelectionChange(geo);
    };
  }

  setEvidence(list, tagFor) {
    this.evidence = list;
    if (tagFor) this.tagFor = tagFor;
    this.drawAll();
  }

  drawAll() {
    for (const p of this.pages) {
      p.marks.innerHTML = '';
      const here = this.evidence.filter(e => e.page === p.pageNumber - 1);
      for (const e of here) {
        for (const r of e.rects || []) {
          const div = document.createElement('div');
          div.className = 'mark';
          div.style.left = `${r.x * 100}%`;
          div.style.top = `${r.y * 100}%`;
          div.style.width = `${r.w * 100}%`;
          div.style.height = `${r.h * 100}%`;
          div.style.background = (e.color || '#F2C14E') + '55';
          div.title = e.note ? `${e.quote}\n\n${e.note}` : e.quote;
          div.dataset.evidence = e.id;
          p.marks.appendChild(div);
        }
      }
    }
  }

  /// Finds every occurrence of a phrase and boxes them in the text layer.
  ///
  /// pdf.js gives no search of its own, so this walks the spans the text layer already laid
  /// over the glyphs. Matching per span misses a phrase broken across two of them, so the
  /// page's spans are joined into one string, matched there, and each hit mapped back to the
  /// span it starts in — which is enough to put a box on it.
  find(query) {
    this.clearFind();
    const q = (query || '').trim().toLowerCase();
    if (q.length < 2) return 0;
    for (const p of this.pages) {
      const spans = [...p.layer.querySelectorAll('span')];
      let joined = '', offsets = [];
      for (const sp of spans) {
        offsets.push({ at: joined.length, span: sp });
        joined += (sp.textContent || '').toLowerCase();
      }
      let from = 0, at;
      while ((at = joined.indexOf(q, from)) !== -1) {
        from = at + q.length;
        let host = offsets[0]?.span;
        for (const o of offsets) { if (o.at <= at) host = o.span; else break; }
        if (!host) continue;
        const box = p.wrapper.getBoundingClientRect();
        const r = host.getBoundingClientRect();
        const div = document.createElement('div');
        div.className = 'find';
        div.style.left = `${((r.left - box.left) / box.width) * 100}%`;
        div.style.top = `${((r.top - box.top) / box.height) * 100}%`;
        div.style.width = `${(r.width / box.width) * 100}%`;
        div.style.height = `${(r.height / box.height) * 100}%`;
        p.finds.appendChild(div);
        this.matches.push(div);
      }
    }
    this.matchIndex = 0;
    if (this.matches.length) this.showMatch();
    return this.matches.length;
  }

  clearFind() {
    for (const p of this.pages) if (p.finds) p.finds.innerHTML = '';
    this.matches = [];
    this.matchIndex = 0;
  }

  stepMatch(delta) {
    if (!this.matches.length) return;
    this.matchIndex = (this.matchIndex + delta + this.matches.length) % this.matches.length;
    this.showMatch();
  }

  showMatch() {
    this.matches.forEach((m, i) => m.classList.toggle('on', i === this.matchIndex));
    const hit = this.matches[this.matchIndex];
    if (hit) this.scrollTo(hit, 'center');
  }

  goToPage(index) {
    const p = this.pages[index];
    if (p) this.scrollTo(p.wrapper, 'start');
  }

  /// Scrolls the page column, not the window. `scrollIntoView` walks every scrollable
  /// ancestor, which in a three-pane layout drags the whole app out of position.
  scrollTo(node, align = 'center') {
    const box = node.getBoundingClientRect();
    const view = this.container.getBoundingClientRect();
    const offset = align === 'start'
      ? box.top - view.top - 12
      : box.top - view.top - (view.height - box.height) / 2;
    this.container.scrollBy({ top: offset, behavior: 'smooth' });
  }

  /// Scrolls to a highlight and flashes it, so clicking one in the list finds it.
  reveal(ev) {
    const p = this.pages[ev.page];
    if (!p) return;
    const mark = p.marks.querySelector(`[data-evidence="${ev.id}"]`);
    this.scrollTo(mark || p.wrapper, mark ? 'center' : 'start');
    if (mark) {
      mark.classList.add('flash');
      setTimeout(() => mark.classList.remove('flash'), 1400);
    }
  }

  async setScale(scale) {
    this.scale = Math.max(0.5, Math.min(3, scale));
    if (this.doc) { this.matches = []; await this.render(); }
  }

  /// Pulls the abstract and conclusion out of a PDF, the same way the desktop app does —
  /// no model, no network, just section headings and the text between them. Static, because
  /// reading a document's text has nothing to do with putting it on screen; the earlier
  /// version rendered every page first and fell over on a detached container.
  static async readSections(blob) {
    const data = new Uint8Array(await blob.arrayBuffer());
    const doc = await pdfjs.getDocument({ data }).promise;
    const meta = await doc.getMetadata().catch(() => null);
    const pages = [];
    for (let n = 1; n <= doc.numPages; n++) {
      const page = await doc.getPage(n);
      const text = await page.getTextContent();
      // Item-level newlines matter: a heading is a line, and joining everything with spaces
      // makes "Conclusions" indistinguishable from the word in a sentence.
      let line = '', buf = [];
      for (const item of text.items) {
        line += item.str;
        if (item.hasEOL) { buf.push(line); line = ''; }
      }
      if (line) buf.push(line);
      pages.push(buf.join('\n'));
    }
    const result = Reader.parseSections(pages);
    result.pageCount = doc.numPages;
    result.title = Reader.guessTitle(meta, pages[0] || '');
    return result;
  }

  static guessTitle(meta, firstPage) {
    const fromMeta = meta?.info?.Title?.trim();
    if (fromMeta && fromMeta.length > 6 && !/\.(dvi|pdf|indd)$/i.test(fromMeta)) return fromMeta;
    // Otherwise the first substantial line that is not a masthead, an email or a page number.
    for (const raw of firstPage.split('\n').slice(0, 14)) {
      const l = raw.trim();
      if (l.length < 20 || l.length > 220) continue;
      if (/^\d+$/.test(l) || /@|downloaded from|^vol\.?\s|^doi/i.test(l)) continue;
      if (l.split(/\s+/).length < 4) continue;
      return l;
    }
    return '';
  }

  static parseSections(pages) {
    const clean = s => s.replace(/([a-z])-\s+([a-z])/g, '$1$2').replace(/\s+/g, ' ').trim();
    const front = pages.slice(0, 3).join('\n');
    const whole = pages.join('\n');

    let abstract = '';
    const aMatch = front.match(/\bAbstract\b[:.—–-]?\s*([\s\S]{80,3000}?)(?=\b(Keywords|Key words|Index Terms|1\s*[.\s]+Introduction|I\.\s+Introduction|Introduction)\b)/i);
    if (aMatch) abstract = clean(aMatch[1]);

    let keywords = [];
    const kMatch = front.match(/\b(?:Keywords|Key words|Index Terms)\b\s*[:.—–-]?\s*([^\n]{3,300})/i);
    if (kMatch) {
      keywords = kMatch[1].split(/[,;·•]/).map(s => clean(s)).filter(s => s.length > 1 && s.length < 60).slice(0, 12);
    }

    // Search the whole document, newest heading first: a long review can put its conclusion
    // at 50% with thirty pages of references after it.
    let conclusion = '', heading = '';
    const re = /\n\s*(?:\d{1,2}[.)]?\s*)?(Conclusions?|Concluding remarks|Discussion and Conclusions?|Summary and Conclusions?)\s*\n/gi;
    const hits = [...whole.matchAll(re)];
    for (const m of hits.reverse()) {
      const after = whole.slice(m.index + m[0].length);
      const stop = after.search(/\n\s*(References|Bibliography|Acknowledge?ments?|Appendix|Funding|Declaration)\b/i);
      const body = clean(stop > 0 ? after.slice(0, stop) : after.slice(0, 6000));
      if (body.length >= 200) { conclusion = body; heading = m[1]; break; }
    }
    return { abstract, keywords, conclusion, conclusionHeading: heading, hasText: whole.length > 200 };
  }
}
