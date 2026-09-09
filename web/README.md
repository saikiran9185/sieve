# Sieve on the web

The same idea as the desktop app, in a browser: read a PDF, mark what matters, and keep every
highlight tied to the page and source it came from.

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

## What works

- Drop PDFs anywhere on the page; they are stored locally and never leave the machine
- The paper's own **abstract, keywords and conclusion** are read out of the file — no model,
  no network, the same text parsing the desktop app does
- Full **pdf.js** reader with real text selection
- Highlight in a tag's colour, by clicking it or pressing its number
- Highlights are stored as fractions of the page, so they land correctly at any zoom
- Every highlight keeps its page, colour, source and the date it was made
- Dropping the same PDF twice does nothing — files are matched by content
- Export highlights as Markdown or CSV
- **Back up** writes your entire library, PDFs included, to one JSON file you keep
- Installable, and works with the network off

## What the desktop app has that this does not

The database search across fourteen sources, PRISMA, the literature matrix, frameworks, the
evidence graph, the AI trail. This is the reading and highlighting core, not a replacement.

## Running it yourself

It is static files. Any web server will do:

```sh
cd web && python3 -m http.server 8099
```

Then open <http://localhost:8099>. A file:// URL will not work — ES modules and service
workers both require a real origin.
