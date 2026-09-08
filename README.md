# Sieve

A provenance-first research workspace for macOS.

Sources, evidence and your own thinking are kept as three separate things, permanently
linked to where they came from. Methodologies — PRISMA, thematic analysis, grounded theory,
or one you build yourself — are a **layer over** that data, not a cage around it.

    SOURCES ── EVIDENCE ── THINKING
                   │
                METHODS
         ┌─────────┼─────────┐
      MATRIX      MAP      PRISMA

A literature-review workbench for macOS. Search every academic database at once,
read and colour-code the PDFs, and let the PRISMA flow diagram count itself.

Everything is local: one folder at `~/Documents/Sieve` holds the database and every PDF.
No account, no server, no subscription.

## The workflow

1. **Overview** — write your review question and your inclusion/exclusion criteria.
2. **Find papers** — one query goes to nine databases *simultaneously*: OpenAlex, Crossref,
   Europe PMC, PubMed, CORE, OpenAIRE, arXiv, DOAJ and PLOS. Five more unlock with a free
   API key: Semantic Scholar, IEEE Xplore, SpringerLink, ScienceDirect and Lens.org.
   Records describing the same paper are merged into one row (DOI first, then normalised
   title), so you screen each paper once, not nine times. Free open-access PDFs are fetched
   automatically where they legally exist. Filter by year, exact date, author, SDG or
   open-access status.

   Google Scholar, BASE, JSTOR, ACM, Wiley, Taylor & Francis and SSRN have no usable API —
   Scholar and BASE actively block automated querying, and scraping Scholar breaks its terms
   of service. Sieve opens your search there in the browser and takes the `.bib`/`.ris` you
   export straight back in.
3. **Library** — everything you've collected, in nested **collections** you make yourself. A
   source is a paper, website, book, chapter, report, thesis, interview, image, video or
   dataset — an interview transcript and a journal article sit in the same corpus.
   Filter by stage, year, author, SDG, PDF status or starred. Drop PDFs anywhere in the
   window — a whole folder of them works too — and Sieve reads the DOI off page one and pulls
   the full record — title, authors, abstract, citations — from OpenAlex. Dropping the same
   paper twice does nothing: records are matched by DOI and files by content, so neither is
   ever stored twice. Import `.bib` / `.ris` from Zotero, Mendeley or
   Google Scholar. Run duplicate detection. **Fill in missing details** backfills abstracts,
   SDGs and citation lists for anything added before those fields existed.
4. **Screening** — a list on the left, the record in the middle, and the decision pinned to
   a rail on the right that never scrolls away. Terms from your inclusion criteria are tinted
   green inside the abstract and exclusion terms red, with a count beside the heading, so a
   record matching nothing you asked for is obvious before you read a line. Every exclusion reason is on screen at once,
   each on its own number key, so a record is judged and filed without touching the mouse. `F` keeps it, `1`–`9` exclude with that
   reason, `J`/`K` move — all under the left hand, so a long screening session never moves it.
   Press `?` for the full list. Record a **conclusion** and what you still need to read,
   right beside the abstract. Full-text
   exclusions require a reason, because PRISMA demands one. A **Decided** tab holds
   everything you've ruled on — any decision can be taken back.
5. **Reader** — the PDF, with your tag palette across the top. Select text, press `1`–`9`,
   and the passage becomes evidence: quoted text, page number, colour category, the paper,
   its authors, year, DOI, which database it came from and the search that found it.
6. **Evidence** — every highlight from every paper, grouped by category or by paper,
   filterable by colour. Delete any highlight and it vanishes from the PDF too.
   Export to Markdown, CSV or Excel with full citations.

6b. **Map** — a citation graph of your corpus, built from the reference lists OpenAlex
   ships with each record. A line means two papers cite the same work; a thick line means
   one cites the other. Colour by stage, folder or year. **Find what I'm missing** surfaces
   the works your own papers cite repeatedly but that aren't in your library yet.
7. **Matrix** — papers down the side, your own questions across the top. Fill cells by
   picking the highlights you already made; each cell remembers what it was built from.
   Include or drop a paper from the review without leaving the grid. Export as **.xlsx**,
   PDF table, CSV or Markdown.
8. **PRISMA 2020** — all four official flow diagrams (new or updated review, with or
   without a second column for records found by other methods), following the templates
   published with the statement. **Every number is clickable** — it opens the records behind
   it, with their exclusion reasons. Counts screening can't infer (registers, automation-tool
   removals, citation searching, a previous version's studies, studies vs reports) are typed
   into the boxes themselves. The **27-item reporting checklist** is tracked alongside, with
   a "where it is reported" column, and items Sieve can already answer are pre-answered.
   Export PNG, SVG, text or the checklist as CSV.

   *Page MJ, McKenzie JE, Bossuyt PM, et al. The PRISMA 2020 statement. BMJ 2021;372:n71.*

## Export everything

One action — in the Library, Matrix, Evidence or PRISMA export menu — writes a dated folder
wherever you choose containing: the whole review as one PDF, the matrix as .xlsx/.pdf/.csv,
the PRISMA flow as text and SVG, every highlight as Markdown/CSV/.xlsx, BibTeX of the
included papers, the full library including exclusions and their reasons, your complete
search history, and a README explaining each file.

## The three states

The single most important distinction in the app:

- **Evidence** (blue) — what the source actually says.
- **Interpretation** (purple) — what you think it means.
- **Question** (yellow) — what you don't know yet.

They are never stored the same way and never look the same, so an interpretation cannot
quietly become a finding. Each carries a confidence level and a verification status
(*needs checking / verified against source / conflicting*), which is what lets the app show
you where the review is weak.

## Relations

Evidence can be linked with typed, directed relations — *supports, contradicts, extends,
is an example of, causes, refines, answers*. This is what turns a pile of highlights into
an argument you can inspect: which findings support a claim, which sources disagree, and
what still rests on nothing.

## Method

A method is an ordered list of steps **you** choose, not a workflow the app imposes. Eight
presets ship (systematic review, scoping review, literature review, thematic analysis,
grounded theory, content analysis, comparative analysis, and "just reading" — three steps).
All are templates: adopt one and it copies into your review where you can change it. Build
one from eighteen blocks, and save any method as a reusable recipe for future projects.

Steps are a guide, never a gate. Every part of Sieve stays reachable whichever method you pick.

## What am I missing

Computed, not guessed — every line names real records and clicks through to them:
records not yet screened · exclusions with no recorded reason · included papers with no
highlights or no full text · evidence never checked against its source · conflicting
evidence · contradictions in the graph · interpretations with nothing supporting them ·
categories resting on a single source · open questions · incomplete PRISMA checklist.

## Tags

A tag is a colour, a name, a coding rule and a keyboard shortcut at once — on one of four
independent axes, so a passage can be a **Finding**, about **Trust**, marked **Important**
and **Qualitative** all at the same time:

- **Type** — what the passage *is*. These are the colours you highlight with.
- **Theme** — what it is *about*. Add these as they emerge from the coding, not before.
- **Status** — where it stands in your process.
- **Data type** — what kind of data it came from.

Rename, recolour, delete and add your own; change a colour and every highlight already
made follows it.

## Claude assistant (optional)

If the `claude` CLI is installed, the assistant can suggest a category for a highlight,
check an abstract against your criteria, draft a matrix cell from that paper's own
highlights, answer a question using only your corpus, and propose search strings.

It never records a decision for you, and everything it writes carries an **AI** badge.
Turn it off entirely in Settings — nothing else depends on it.

## Reading a PDF without AI

Drop a PDF and Sieve reads the paper's own **abstract, keywords and conclusion** straight
out of the text layer — no model, no network. It finds section headings the way you do when
skimming, dehyphenates line breaks, ignores running heads, and searches the whole document
for the conclusion (a 50-page review can put it at 50%, with thirty pages of references
after). When there is no conclusion heading it takes the closing paragraphs and *says so*
rather than pretending. Tested on 37 real papers: 34 abstracts, 26 keyword lists, 35
conclusions. A scan with no text layer is reported as such rather than silently returning
nothing.

The extracted conclusion appears in screening beside the abstract, with one click to adopt
it as your own starting point.

## Install

**macOS 14 or later.** Apple Silicon and Intel.

### One command

```sh
brew install --cask saikiran9185/tap/sieve
```

or, without Homebrew:

```sh
curl -fsSL https://raw.githubusercontent.com/saikiran9185/sieve/main/install.sh | bash
```

Either one downloads the latest release, checks it against the SHA-256 published with it,
installs it, and clears the download quarantine flag — so macOS opens it instead of claiming
the app is damaged. There is no `xattr` command to run by hand.

Why that flag needs clearing: the app is signed but **not notarised by Apple**, which requires
a paid Developer ID ($99/year). macOS refuses to open a quarantined app it cannot check with
Apple, and says it *could not verify the app is free of malware* — a statement about the
signature, not a scan result. The checksum published with every release is what protects the
download instead, and it is verified before the app is installed.
[NOTARISING.md](NOTARISING.md) explains the three signing levels and how to reach the one
where nobody sees that dialog.

### If you don't use Terminal

Download `Sieve-x.y.dmg` from the [latest release](../../releases/latest), drag Sieve into
Applications, and open it. macOS will refuse the first time and say it *"could not verify
Sieve is free of malware"* — that is not a malware finding, it is what macOS says about any
app that has not been through Apple's paid notarisation service. Then:

1. Click **Done**. Not *Move to Trash*.
2. Open **System Settings** → **Privacy & Security**.
3. Scroll to **Security**, near the bottom. There is a line saying Sieve was blocked, with an
   **Open Anyway** button beside it. Click it.
4. Confirm with Touch ID or your password.

Sieve opens, and every launch after that is normal. **You do this once.**

The same disk image carries these steps in a `READ ME FIRST` file.

### Dragging it across, from Terminal

If you would rather clear the block with one command than click through System Settings,
click **Done** on the dialog and run

```sh
xattr -dr com.apple.quarantine /Applications/Sieve.app
```

and open it normally. That removes the "downloaded from the internet" flag; it does not
change the app. The two commands above do this for you, which is why they are listed first.

### Or build it

About thirty seconds, no dependencies to fetch, and you get to read what you are running.

```sh
git clone https://github.com/saikiran9185/sieve.git
cd sieve
./build_app.sh
open Sieve.app
```

## Build

```sh
swift build -c release   # binary only
./build_app.sh           # binary wrapped in Sieve.app, ad-hoc signed
```

Requires Swift 6 / Xcode 16+. **No external dependencies** — SwiftUI, PDFKit and the system
SQLite, nothing else. It builds and runs offline; the only network calls are the academic
database searches you ask for.

## Windows and Linux

**There is no Windows or Linux build, and there will not be one without a substantial rewrite.**
This gets asked a lot, so here is the actual measurement rather than an assertion: of 14,261
lines, **1,933 (14%) are plain Swift** that would compile anywhere. The other 86% is SwiftUI,
AppKit, PDFKit or CoreText.

Sieve's reader is built on **PDFKit** and its interface on **SwiftUI** and **AppKit**, all of
which are Apple frameworks that exist only on macOS. The PDF reader is not a thin layer over
the app — the text selection, the per-line highlight geometry, the annotations written back
into the document — that *is* the app. Porting it means rebuilding that layer on something
cross-platform and accepting a worse reading experience, which was the exact trade-off this
project was started to avoid.

What *is* portable is everything underneath: the fourteen database providers, the
deduplication, the BibTeX/RIS parsing, the PDF section extraction, the PRISMA computation and
every exporter are plain Swift with no Apple dependencies. Swift runs on Windows and Linux,
so a cross-platform command-line tool or a web front end over that core is a realistic
project for someone who wants it. Open an issue if that is you.

## Collections, not folders

A collection is a label on a paper, not a place it is kept — the way Zotero works. Filing a
paper never moves a file, the same paper can sit in several collections at once, and deleting
a collection removes the label and nothing else.

Some collections fill themselves from decisions you have already made: **Included**,
**Excluded**, **Still to screen**, **Needs the full text**, **Read but not yet coded**,
**No conclusion recorded**. A paper appears the moment its stage matches and leaves if you
change your mind, so screening does the filing for you.

On disk, each review owns one folder — and Sieve mirrors the structure into real folders
you can open in Finder:

```
~/Documents/Sieve/
├── sieve.sqlite
├── Exports/
└── Reviews/
    └── cosmetic-packaging-3/
        ├── README.txt
        ├── PDFs/                        one file per paper, ever
        └── Browse/
            ├── By screening decision/
            │   ├── Included/
            │   └── Excluded (full text)/
            │       └── Wrong population/
            ├── By collection/
            └── By year/
```

Everything under `Browse/` is a **symbolic link**, so a paper that belongs to three
collections appears in all three and still takes up space once — 356 entries in the review
this was built against occupy **0 bytes**. Delete the whole folder any time; nothing is lost
and Sieve rebuilds it on request. Group by decision, collection, year, first author or
database in Settings, and have it rebuild whenever you open the Library.

Files are named `year-author-title`. Titles are transliterated rather than stripped, so a
Cyrillic, Greek or Chinese paper gets a readable name instead of a row of underscores.

Paths are stored **relative to the library root**, so you can move the whole library to an
external drive or a synced folder — Settings → Library → Move — without breaking a single
record.

## Where the AI gets checked

A model can read faster than you and will not show its working. Sieve does not try to beat it
at that. It is the place the work gets checked, and the checking gets recorded.

Every assistant interaction is written to an append-only trail: what was asked, what it
answered, which model answered, and — the part a flag cannot capture — **what you then decided
about it.** Accepted as given, accepted after editing, rejected, or read and not used. The
**AI trail** screen is a queue of everything nobody has adjudicated yet.

From that trail Sieve writes the **declaration of generative AI use** that Elsevier, Springer
Nature, JAMA and the ICMJE now require. Most people write that paragraph from memory at
submission. This one is written from a record made at the time, and it will say so plainly
when suggestions were never checked:

> **1 of 4 AI outputs had not been checked by the author at the time of writing, including 1
> relating to studies included in the review.**

and only claims the clean version when it is true:

> **Every AI suggestion was subsequently checked by the author against the source and
> accepted, edited or rejected.**

It also states what AI was structurally prevented from doing: no screening decision, no
extraction of text from a source, no writing. Those are not promises — they are properties of
how the app is built, and the trail is the evidence.

## Proof, not intention

PRISMA separates reports *sought* from reports *retrieved*, and Sieve treats that as a fact
about the disk rather than a state of mind. A record counts as retrieved only when a readable
PDF is actually there — verified by opening it, not by trusting a stored path. Records that
passed screening but were never downloaded are counted under "reports not retrieved", and the
diagram says so rather than quietly inflating the number of papers you assessed. One button
moves them all to the right stage.

The same check catches files that have been deleted, moved, or saved as a publisher's error
page under a `.pdf` name.

## Light and dark

Both, or whatever the system is set to — in Settings, or the View menu. The tag palette is
authored for a dark ground, so the light variant of each colour is derived rather than
maintained separately: measured against white, amber reached only 1.7:1 as authored and 4.65:1
after. All nine tag colours clear WCAG 4.5:1 in both modes.

## Getting your work back out

Nothing here is a dead end. A review exports as:

| Format | For |
| --- | --- |
| **RIS** | Zotero, Mendeley, EndNote — with your conclusions, notes, exclusion reasons and highlights in the note field |
| **BibTeX** | LaTeX, Word, Zotero |
| **XLSX / CSV** | the matrix, as a spreadsheet |
| **PDF** | the whole review as one document, or the matrix as a table |
| **Markdown** | every highlight, grouped by category, with citations |
| **SVG / PNG** | the PRISMA flow diagram, at any size |

One action — Export → *Everything in one folder* — writes all of it plus the PRISMA checklist
and your full search history into a dated folder.

## Privacy and security

Everything lives in `~/Documents/Sieve` — one SQLite file and your PDFs. Nothing is sent
anywhere except:

- the academic databases you search, when you search them;
- Unpaywall and OpenAlex, when you ask Sieve to find a free PDF;
- your contact email, **only** to OpenAlex, Crossref, PubMed and Unpaywall, and **only** if
  you enter one in Settings (it is blank by default and buys you faster, more complete
  results from those four services);
- the `claude` CLI on your own machine, if you turn the assistant on.

There is no account, no telemetry, no sync server. Delete the folder and nothing remains.

API keys are kept in the **Keychain**, not in a preferences file. Every link the app opens or
fetches must be `http`/`https` with a real host, because those links arrive from external
sources; `file://`, `javascript:` and custom app schemes are refused. Responses are
size-capped, downloads are verified as real PDFs before being written, SQL is parameterised,
and the app is built with the hardened runtime. Details, including what is deliberately *not*
hardened, are in [SECURITY.md](SECURITY.md).

## Feedback

This has been used on exactly one real review — mine. If you use it on yours, the
[feedback template](../../issues/new?template=feedback.yml) asks what got in your way, and
that is the most useful thing you can send. Bugs, missing databases and layout problems all
have templates too.

Security issues go to a [private advisory](../../security/advisories/new), not a public
issue. See [SECURITY.md](SECURITY.md).

## Contributing

Issues and pull requests are welcome. The code has no dependencies and no build system
beyond SwiftPM, so it should be easy to get into:

| Where | What |
| --- | --- |
| `Sources/Sieve/Core` | Models, SQLite wrapper, schema, the store every view reads from |
| `Sources/Sieve/Search` | The fourteen database providers and the merge/dedupe logic |
| `Sources/Sieve/Import` | PDF section extraction, BibTeX/RIS parsing, record enrichment |
| `Sources/Sieve/Export` | CSV, Markdown, BibTeX, XLSX and PDF writers (all hand-rolled) |
| `Sources/Sieve/UI` | One file per screen |

Adding a database is one `struct` conforming to `SearchProvider` plus one line in
`SearchEngine.allProviders`.

## Credits

PRISMA 2020 flow diagrams and reporting checklist:
Page MJ, McKenzie JE, Bossuyt PM, Boutron I, Hoffmann TC, Mulrow CD, et al.
*The PRISMA 2020 statement: an updated guideline for reporting systematic reviews.*
BMJ 2021;372:n71. doi:10.1136/bmj.n71 — licensed CC BY 4.0.

Metadata comes from OpenAlex, Crossref, Europe PMC, PubMed, CORE, OpenAIRE, arXiv, DOAJ,
PLOS and Unpaywall, all of which provide open APIs. Thank you to all of them.

## Notes

- Sieve only downloads PDFs that are legally free (OpenAlex / Unpaywall open-access
  locations, arXiv, PMC). Paywalled papers get flagged so you can fetch them through
  your library and drop them in.
- Semantic Scholar's keyless pool is shared and often answers `429`. Sieve retries once
  and carries on with the other five databases. A free API key in Settings removes it.
- OpenAlex, Crossref and Unpaywall return faster, more complete results to requests that
  carry a contact email. That field in Settings is blank by default and is sent only to
  those three services.
