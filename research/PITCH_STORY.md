# Sieve: the pitch story

The argument of the deck, from problem to proof. Facts about Sieve come from the README. Market facts come from `MARKET_RESEARCH.md`.

**One line:** *Humans read. Sieve does the paperwork.*

---

## 1. What a literature review is

A literature review means reading what is already known about a question, then writing what it adds up to:
- where researchers agree
- where they disagree
- what nobody has studied yet (the **gap**)

It is not a list of summaries. The value is in **connecting** the papers into an argument.

A **systematic** literature review (SLR) does the same with strict rules:
- a plan written first
- every major database searched
- each paper kept or excluded with a reason
- quality checked
- each step reported in a PRISMA flow diagram, so anyone can repeat it

## 2. Why people do it

- **To understand the topic** before adding to it.
- **To avoid repeating work** someone has already done.
- **To find the gap.** The gap is the reason a thesis, product or policy exists.
- **To back up claims** with evidence, not opinion.
- **To choose a method** by seeing what worked and failed before.

## 3. Who does it

| Who | When they need it |
|---|---|
| UG and master's students | Capstones, dissertations, research papers (every design student, including us) |
| PhD researchers, professors | Theses, grant applications, review papers |
| Doctors and clinical researchers | Deciding which treatment works; regulatory approval |
| UX and product researchers | Evidence before designing a product |
| R&D and engineers | Prior art, so they don't build what already failed |
| Policy analysts, think tanks | Evidence before laws and public programmes |

## 4. The core problem in the market

### Problem 1: the work is scattered across many sites
A review today needs a **database** to search, a **citation map** to chase references, an **AI reader** to understand PDFs, a **reference manager** to store them, a **screening tool** to record decisions, and a spreadsheet for the matrix. That is four to six tools:

> Google Scholar / Scopus → ResearchRabbit / Litmaps → SciSpace / Elicit → Zotero → Covidence → Excel

Every hand-off loses something:
- which search found a paper
- why a paper was excluded
- which page a quote came from

At the end, students rebuild the PRISMA counts by hand from memory.

### Problem 2: AI summaries are fast, but they skip the thinking
Most new review apps are AI summary apps. They are fast, but:
- **AI stands on its own data.** If the paper it reads is misleading, or the data is wrong, the AI repeats it fluently. It has no way to know the truth.
- **AI makes things up.** Chatbots still invent papers, authors and DOIs.
- **AI is weak at gaps.** A gap is what is *missing* from the literature. A model built on what is *present* can't see absence well.
- **AI can't judge quality.** It can't reliably spot flawed methods or a subtle contradiction between two fields.
- **It changes the human.** If the AI reads, the student never learns to read critically. The review gets written, but the understanding never forms. Colleges and journals now treat pasted AI text as misconduct.

Only a human can tell what is wrong:
1. by connecting dots across papers,
2. by noticing when something doesn't fit,
3. by learning from mistakes and finding new things on the way.

**That is the point of a literature review.**

### Problem 3: the same mistakes, every time
Writing guides list the same failures again and again. They are process failures, not writing failures:
1. writing before the search is finished
2. keyword search only, with no citation chasing
3. summarising instead of synthesising
4. organising by author instead of by theme
5. no reference manager, no search log
6. stopping too early
7. vague gaps ("more research is needed")
8. too many direct quotes
9. too many words on background

## 5. Our answer: Sieve

**One workspace for the whole review. The human reads and decides; Sieve keeps the record.**

> Search → Screen → Read → Evidence → Matrix → PRISMA, all in one place, all linked to the source.

AI is inevitable, and Sieve doesn't pretend otherwise. The optional assistant can:
- suggest search strings
- check an abstract against your criteria
- draft a matrix cell **from your own highlights**

But **it never records a decision**, and everything it writes carries an **AI** badge. AI assists; the human is the judge.

### Unique selling points
1. **Every claim traces back to the exact line.** A highlight stores the quote, page, paper, DOI, database and the search that found it.
2. **Evidence ≠ interpretation.** What the source says (blue), what you think it means (purple) and what you don't know yet (yellow) are stored separately. An opinion can never quietly become a finding.
3. **PRISMA counts itself.** All four PRISMA 2020 diagrams are included. Every number is clickable down to the records and their exclusion reasons. The 27-item checklist is tracked alongside.
4. **"What am I missing", computed, not guessed.** It lists:
   - unscreened records
   - exclusions with no reason
   - evidence never checked
   - contradictions
   - claims resting on one source
   - papers your corpus cites that you haven't read
5. **One search, many databases.** Nine free databases at once, five more with a free key. Duplicates are merged so each paper is screened once.
6. **Local-first and private.** PDFs stay on your device. It works offline, needs no AI credits, and has no paywall on the core.

### Does Sieve stop the common mistakes?

| Mistake | How Sieve helps | Strength |
|---|---|---|
| Writing before the search is finished | "What am I missing" shows unscreened records and gaps in coverage; the method steps show where you are | Partly |
| Keyword search only | **Map → Find what I'm missing** surfaces works your papers keep citing that you don't have yet (citation chasing, built in) | Yes |
| Summarising, not synthesising | **Matrix** (papers × your questions) built from highlights, plus **relations** (*supports, contradicts, extends…*) that turn notes into an argument | Yes |
| Organising by author | **Theme tags** and evidence grouped by category or question, not by paper | Yes |
| No reference manager / search log | Library and **full search history** are built in; every highlight remembers its search; BibTeX/RIS in and out | Yes |
| Stopping too early | Citation map shows the papers you keep meeting; "missing" list shrinks as coverage saturates | Partly |
| Vague gap statement | **Open questions** (yellow), "categories resting on a single source" and "interpretations with nothing supporting them" give a gap you can point to | Partly; the human still writes it |
| Too many direct quotes | Quotes live as evidence; your own words live as interpretation, kept apart | Partly |
| Too much background | Writing balance is the author's job | No, and we don't claim it |

## 6. Sieve vs other apps

**AI summary apps** (Elicit, SciSpace, Consensus) read *for* you. **Map apps** (ResearchRabbit, Litmaps, Connected Papers) *find* papers but don't help you read or decide. **Zotero** *stores* papers. **Covidence/Rayyan** *screen* papers, for paying teams. **Sieve** covers the whole review, with the human deciding.

| | Elicit / SciSpace | ResearchRabbit / Litmaps / Connected Papers | Zotero | Covidence / Rayyan | **Sieve** |
|---|---|---|---|---|---|
| Main job | AI summary + extraction | Citation maps | Store + cite | Team screening | **Whole review** |
| Search many databases | Own index | Own index | Import | Import | **✓ 9 free + 5 with key** |
| Citation chasing | Partly | ✓ | ✗ | ✗ | **✓ Map** |
| Screening with reasons | Partly | ✗ | ✗ | ✓ | **✓ one key per reason** |
| Read + highlight PDFs | ✓ (AI chat) | ✗ | ✓ | Partly | **✓ highlight = evidence** |
| Evidence vs your opinion kept apart | ✗ | ✗ | ✗ | ✗ | **✓** |
| Synthesis matrix | AI-filled table | ✗ | ✗ | Extraction forms | **✓ from your highlights** |
| PRISMA 2020 | ✗ / manual | ✗ | ✗ | ✓ | **✓ counts itself** |
| Who decides | AI drafts | You | You | You | **You (AI only suggests, badged)** |
| Risk of invented content | Yes | No | No | No | **No** |
| Price | Freemium / paid | Free / freemium | Free | Paid | **Free core** |
| Data stays private | Cloud | Cloud | Local + cloud | Cloud | **Local-first** |

*Competitor cells are a summary as of Nov 2026. Check each one on the live site before it goes on a slide.*

## 7. Target audience

**Beachhead (now):** master's and PhD students, plus design and UX students like us.
- They must do the review.
- They're told not to paste AI text.
- They need a PRISMA diagram and can't pay for Covidence.
- It is free for them, and they spread it by word of mouth on every campus.

**Paying users (next):**
1. **UX and product research teams:** evidence → SWOT → decisions. Cross-platform, no install (the web app), seat budgets.
2. **Clinical and health reviewers:** PRISMA is mandatory and a hallucinated quote is unacceptable.
3. **Policy, legal and strategy analysts:** confidential PDFs that can't go into cloud AI.

**Scale:** university libraries buy a campus licence once enough students on a campus already use it.

## 8. Why it is sustainable

- **Low cost to run.** Local-first means PDFs live on the user's device and the server syncs only small project data. There is **no AI cost per summary**, unlike AI-first apps that pay a model provider for every answer. More users does not mean a bigger AI bill.
- **Freemium model** (prices to test):
  - **Free:** the full review on one device. This is the student beachhead.
  - **Pro:** account sync across devices, cloud backup, log in anywhere.
  - **Team / Lab:** shared projects, two-reviewer screening (on the roadmap).
  - **Campus licence:** libraries, once usage exists.
- **A moat that AI apps can't copy easily.** Their product *is* the AI summary. Sieve's product is the trusted record. As journals and universities tighten AI rules, trust becomes the thing people pay for.
- **Open source** builds credibility with academics and lowers the cost of getting users.

**Honest risks:**
- Manual screening is slower than AI auto-fill for very large reviews.
- It is built for one person today (no blind second reviewer yet).
- There is no revenue yet. Traction comes first.

---

## Slide map (draft, for approval)
| # | Slide | Content |
|---|---|---|
| 02 | What and why | Lit review in one line, why we do it, who does it |
| 03 | The problem | 4–6 tools, lost provenance, PRISMA rebuilt by hand |
| 04 | The AI trap | Fast but invents, misses gaps, deskills; only humans connect dots |
| 05 | Solution | Sieve: one workspace, cat holds the screenshot |
| 06 | USPs | Six points above |
| 07 | Mistakes solved | The table from section 5 |
| 08 | Comparison | The table from section 6 |
| 09 | Target audience | Beachhead → paying → campus |
| 10 | Sustainability | Low cost, freemium, moat, risks |

---

## Real case: how a review is actually done (slide 03)

Source: DRT (DI IX-703) Session 3, B.Design 7th sem, GGSIPU, 3 Sep 2026. The session was led by a full-time PhD research scholar; course faculty Dr. Nanki Nath.

**The assignment:**
- find 10 papers from the last 5 years on cosmetic box packaging and the SDGs
- use good journals only (Scopus, Web of Science, Elsevier, ScienceDirect)
- build a literature matrix
- apply PRISMA
- hand everything in as one Word file

**The workflow the session taught:**
1. **Search** Google Scholar with Boolean operators (AND, OR, NOT/-, " ", (), +, intitle, author, source).
2. **Filter** by year and by journal quality.
3. **Read.** AI tools (NotebookLM, ResearchRabbit, Consensus) are allowed "to read paper (only)", and the matrix must be "in your own words".
4. **Literature matrix:** a table in Word.
5. **PRISMA,** taught as three stages:
   - Identification: all records from the databases, found with a Boolean string
   - Screening: title and abstract checked against the criteria
   - Analysis: synthesis and interpretation
   
   The diagram is drawn by hand.
6. **Gap:** the session named seven gap types (evidence, knowledge, practical-knowledge, methodological, empirical, theoretical, population).

**What this proves for the pitch:**
- Even a 10-paper student review spans five or more tools and ends in a hand-drawn PRISMA diagram.
- The faculty rule is "AI to read only, your own words", which is exactly Sieve's stance: AI assists, the human decides.
- Sieve covers every step:
  - search across many databases
  - screening with reasons
  - a reader whose highlights become evidence
  - a matrix built from those highlights
  - PRISMA that counts itself
  - "What am I missing" for the gaps
