# Sieve on the web

The same idea as the desktop app, in a browser: read a PDF, mark what matters, and keep every
highlight tied to the page and source it came from.

**There is no account and no server.** Sources, highlights and the PDF files themselves live in
this browser's own storage. Nothing is uploaded, which is also why there is nothing to log in
to — a sign-in screen would mean a server holding your reading, and at that point the tool is
renting your research back to you.

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
