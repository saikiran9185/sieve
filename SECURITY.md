# Security

## Reporting a vulnerability

Open a [security advisory](https://github.com/saikiran9185/sieve/security/advisories/new).
That keeps the report private until there is a fix. Please do not open a public issue for
something exploitable.

I am one person maintaining this alongside a degree, so expect a first reply within a week
rather than a day.

## What Sieve does with your data

Everything is stored locally in `~/Documents/Sieve` — one SQLite file and your PDFs.
There is no account, no server, no telemetry, and no crash reporting.

Network requests are made only to:

| Where | When | What is sent |
| --- | --- | --- |
| The academic databases you enable | When you run a search | Your search terms |
| Unpaywall, OpenAlex | When you ask for a free PDF | The paper's DOI |
| The host serving an open-access PDF | When you download one | Nothing but the request |
| The `claude` CLI **on your own machine** | Only if the assistant is on | The text you are working with |

Your contact email is optional, blank by default, and sent only to OpenAlex, Crossref,
PubMed and Unpaywall — the services whose rate limits improve when a request identifies a
contact. It is never sent anywhere else.

## Design decisions that affect security

**Only web URLs are ever opened.** Every link in the app arrives from an external source —
a search API's JSON, a DOI record, a `.bib` file someone else exported. All of them pass
through a scheme allowlist (`http`, `https`, and a real host) before the app will open them
or fetch them. `file://`, `javascript:`, `data:` and custom application schemes are refused.
See `Sources/Sieve/Core/Security.swift`.

**API keys go in the Keychain**, not the preferences plist, and are marked
`WhenUnlockedThisDeviceOnly` so they are never synced or included in a backup. Keys written
by earlier builds are migrated out of `UserDefaults` on first read.

**Responses are size-capped** at 8 MB for metadata and 200 MB for a PDF, so a hostile or
broken endpoint cannot exhaust memory.

**Downloads are verified** as real PDFs by their magic bytes before being written to the
library. A publisher page served with a `.pdf` URL opens in your browser instead.

**SQL is always parameterised.** The only interpolated statements are `ALTER TABLE`
migrations built from string literals in the source; no user or network data reaches them.

**XML external entities are disabled** when parsing arXiv's Atom responses.

**The AI assistant is optional and advisory.** It runs the `claude` CLI as a child process
with arguments passed as an array — never through a shell — so no text can be interpreted as
a command. It cannot record a screening decision; everything it writes is badged as
AI-generated and must be accepted by you.

**The app is built with the hardened runtime**, which enables library validation and blocks
code injection and unsigned executable memory.

## What is *not* hardened

**The app is not sandboxed.** Sandboxing would move your library into an opaque container
and break existing installs. As a consequence Sieve has the same file access as any other
app you run.

**The app is not notarised by Apple.** Notarisation requires a paid Developer ID. macOS will
quarantine the download until you clear the flag, and you are trusting a binary that Apple
has not scanned. If that matters to you, build from source — it takes about thirty seconds
and there are no dependencies to audit beyond this repository.

**PDFs are rendered by Apple's PDFKit.** A malicious PDF is a risk in any reader; keep macOS
updated.
