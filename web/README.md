# Sieve on the web

The same workspace as the desktop app, in a browser: find papers, screen them with recorded
reasons, read and highlight them, and keep every highlight tied to the page and source it came
from.

**There is no account and no server.** Sources, highlights and the PDF files themselves live on
your own computer. Nothing is uploaded, which is also why there is nothing to log in to — a
sign-in screen would mean a server holding your reading, and at that point the tool is renting
your research back to you.

## Coming back to your work

This is the question that matters, so here is the honest answer.

Your library is kept in this browser's own storage, and it survives closing the tab, quitting
the browser and restarting the computer. But by default a browser is allowed to **delete that
storage when the disk gets full**, without asking. Sieve therefore does two things.

**It asks the browser not to.** The first time you add a PDF, Sieve requests persistent
storage. Browsers grant this to sites you actually use and refuse it to ones you glanced at,
so it usually becomes permanent within a visit or two — and it is not guaranteed.

**It can keep a copy in a real folder.** Click **Keep a copy in a folder** in the sidebar and
choose somewhere on your disk. Sieve writes:

```
YourFolder/
├── PDFs/                    every source, an ordinary PDF you can open in anything
├── sieve-library.json       your highlights, their pages, tags and sources
└── README.txt               what this folder is, for future you
```

It re-syncs whenever you add a paper or make a highlight. Nothing about that folder is a
Sieve format you would be stuck inside: the PDFs are PDFs, and the index is readable JSON.

The sidebar always says which of three states you are in:

| | Meaning |
| --- | --- |
| **Saved on this computer** | The browser has promised not to evict it. |
| **Copied to *folder*** | Also mirrored to a folder you chose. The safest state. |
| **Could be cleared by the browser** | Not yet persistent. Add a folder, or use **Back up**. |

**To come back after clearing browser data, or on another machine:** open Sieve, click
**Restore**, and point it at the folder — or at a `Back up` file. Tested by deleting the entire
browser store and restoring: the source, the highlight and the full PDF all came back.

Choosing a folder needs the File System Access API, which today means **Chrome or Edge**. In
Safari and Firefox the button becomes **Back up to a file**, which does the same job in one
file, manually.

## What is here

**Finding papers.** Seven databases queried at once — OpenAlex, Crossref, Europe PMC, PubMed,
DOAJ, PLOS and OpenAIRE — with records describing the same paper folded into one row, so you
screen each paper once. Every result carries where it came from and the search that found it.

**Screening.** A queue with your inclusion and exclusion terms tinted into each abstract, so
the words a decision turns on are visible before you read a line. Keyboard-driven, and an
exclusion asks for its reason because PRISMA needs one.

**The reader.** Three panes, as on the desktop: the papers you can read, the page itself, and
what you have taken out of it.

- Full **pdf.js** reader with real text selection and find-in-document
- Highlight in a category's colour by clicking it or pressing its number
- **Evidence, interpretation or question** — the same passage marked as interpretation is your
  thinking, not the source's words, and the app never lets those blur together
- **Add a thought** records an interpretation that is not tied to any passage
- Highlights are stored as fractions of the page, so they land correctly at any zoom, and a
  selection dragged past the bottom of a page keeps the page it started on
- The inspector's three tabs: the highlights, the paper and where it came from, and the
  include/exclude decision — without leaving the page you are reading

**Beyond the reader.** The evidence board, the extraction matrix, design-research frameworks
(SWOT, journey and empathy maps, 2×2s), the PRISMA flow diagram with its counts, and methods
you adopt as a recipe and then edit.

**The citation map.** Papers as nodes, a line where two cite the same works, drawn from the
reference lists OpenAlex ships with every record — force-directed, pan and zoom. It also finds
the works your own papers keep citing that are not in your library yet, which is the reading
you are missing.

**The AI trail.** There is no assistant here — running one would mean sending your library to
somebody else's computer. But Sieve still writes into your review without you: it reads an
abstract and a conclusion out of a PDF by pattern, guesses a title when a file has no metadata,
carries OpenAlex's subject labels across, and folds two database records into one paper. Each
is logged as a claim to check, you record a verdict, and the disclosure export states exactly
which were checked and which were not.

**Everywhere.**

- Drop PDFs anywhere on the page; they are stored locally and never leave the machine
- A dropped PDF attaches to the record a search already found, rather than becoming a second
  copy of the same paper; dropping the same file twice does nothing
- Export highlights as Markdown or CSV, the matrix as CSV, PRISMA as text, the trail as CSV
- **Back up** writes your entire library — PDFs, matrix, frameworks, method and trail included
  — to one JSON file you keep
- Installable, and works with the network off

## What the desktop app has that this does not

Two things the browser genuinely cannot do. It cannot search **CORE or arXiv**, which send no
CORS header, or the four databases behind **paid API keys** — the search screen names them
rather than hiding them. And it has **no assistant**, for the reason above.

Beyond that, the desktop app adds folders and collections, and XLSX and Word export.

## Running it yourself

It is static files. Any web server will do:

```sh
cd web && python3 -m http.server 8099
```

Then open <http://localhost:8099>. A file:// URL will not work — ES modules and service
workers both require a real origin.
