# Sieve: market research notes

Notes from a Gemini chat on literature reviews, AI tools, competitors and target users (15 Nov 2026). They feed the Design Entrepreneurship pitch (17 Nov 2026) and the end-term jury (17 Dec 2026).

> **Read with care:** Gemini wrote the answers, and AI can be wrong. Corrections against the real app are marked **Fact check**. Prices and user numbers are Gemini's estimates. Check them before they go on a slide.

---

## 1. What a literature review is

A literature review summarises and evaluates the existing research on a topic. It groups studies by theme, compares their ideas and shows how they connect to your own project. It is more than a list of articles.

### Why every college student has to do one
- **No repeated work:** it shows what is already proven.
- **Finds the gap:** it shows what is still unknown, which is the reason for your project.
- **Proves you know the subject:** it shows you have read the key texts and debates.
- **Builds your method:** past studies show which research tools worked and which failed.
- **Backs up claims:** expert evidence supports your argument.

## 2. Systematic Literature Review (SLR)

An SLR is a strict, step-by-step way to find, judge and combine **all** the research on one question. You write the plan before the search starts. That reduces bias and lets others repeat the exact process.

**Steps:**
1. Ask a clear question (topic and scope).
2. Set inclusion/exclusion rules (date, language, study type).
3. Search every major database with a fixed list of keywords.
4. Filter by title, then abstract, then full text.
5. Check the quality of what is left.
6. Combine the findings: what is known and what is missing.

**Why it matters:**
- It removes bias.
- It can be repeated.
- Doctors, scientists and policymakers trust it.

**PRISMA 2020** is the standard way to report the steps and counts.

### SLR vs standard literature review

| | Standard (narrative) review | Systematic review |
|---|---|---|
| Plan | Flexible, no fixed protocol | Protocol written before searching |
| Search | Selected sources | Every major database, fixed keywords |
| Selection | Author's judgement | Explicit inclusion/exclusion rules |
| Quality check | Informal | Formal appraisal of each study |
| Reporting | Themes, argument | PRISMA flow + counts |
| Repeatable | No | Yes |

## 3. AI in literature reviews: what is OK

You don't have to use AI. Letting AI **write** the review is not OK. Using AI as a search and reading assistant is fine.

| OK | Not OK |
|---|---|
| Finding papers and mapping connections | Pasting AI-written paragraphs into the review (academic dishonesty, flagged by detectors) |
| Summarising abstracts to screen faster | Trusting AI citations: chatbots invent papers and authors |
| Asking questions about a real PDF | Skipping the reading: critical judgement is yours |

**Rule of thumb:** AI finds and sorts the research; you read the key papers and write the review. Check your professor's rules on disclosing AI use.

## 4. Competitor apps and how much AI they use

| App | Uses AI? | Core function | Best for |
|---|---|---|---|
| Elicit | Yes (heavy) | Question-based search; pulls methods, findings and limits into tables | Fast data extraction, comparing studies |
| SciSpace | Yes (heavy) | Chat with PDFs, summaries, explains terms | Reading hard technical papers |
| Consensus | Yes (heavy) | Evidence-backed yes/no answers from peer-reviewed papers | Checking what the evidence says on a claim |
| ResearchRabbit | Minimal (recommendations) | Citation-network maps, related authors | Visual exploration |
| Litmaps | Mostly no (optional AI) | Citation timelines, tracks new papers | How a topic evolved; staying updated |
| Connected Papers | No (citation similarity) | One seed paper → graph of related work | Quick overview of a niche |
| Zotero | No | Saves PDFs, annotations, citations | Reference management, bibliography |
| Covidence / Rayyan | Little | Team title/abstract and full-text screening, PRISMA | Multi-reviewer systematic reviews |

**Where AI helps:** finding papers without exact keywords, mapping connections, pulling facts out of long PDFs. Gemini claims this is "70–80% faster", but the figure is not verified.

**Where AI fails:** it can't judge flawed methods, it misses new low-citation papers, and it misses subtle contradictions across fields.

**Common workflow today:**
1. Find papers with ResearchRabbit or Connected Papers.
2. Screen and read them in Elicit or SciSpace.
3. Save them in Zotero.
4. Write the review yourself.

That is four tools. **Sieve's pitch is one workspace.**

## 5. Sieve vs other apps

| | Sieve | Elicit | Covidence / Rayyan | Zotero | SciSpace / ResearchRabbit |
|---|---|---|---|---|---|
| Approach | Provenance-first, human-led, local-first | AI search and extraction | Team screening | Library and PDF management | AI reading / citation maps |
| Platform | Mac app + web app | Web | Web | Desktop + web | Web |
| Search | Many databases at once | Own corpus (Semantic Scholar / OpenAlex) | Manual RIS/CSV import | Browser connector, import | Own index |
| Evidence | Colour-coded PDF highlights linked to synthesis grids (e.g. SWOT) | AI fills table columns | Voting | Notes, tags | AI chat, graphs |
| PRISMA 2020 | Built in, counts itself | Manual | Built in | None | None |
| Price / privacy | Free, open source, data stays on the device | Freemium / paid | Paid per review or institution | Free (paid storage) | Freemium / paid |

> **Fact check (against README):**
> - The Mac app searches **nine** databases at once and the web app **seven**. Gemini's "14" is wrong.
> - Sieve ships as a **notarised DMG** and a **zero-install web app**. Gemini's "manual build only" is outdated.

### Advantages
- **Provenance:** every quote and data point stays tied to its exact passage in the PDF, and evidence is kept separate from interpretation. There is no AI to hallucinate.
- **One app for the whole review:** search, screening, reading, synthesis and PRISMA, with no stack of subscriptions.
- **Local-first and free:** no paywall, no credit limits, no forced cloud upload.
- **Built for critical thinking:** structured, colour-coded reading instead of black-box summaries.

### Disadvantages / risks
- Screening hundreds of papers takes more manual effort than with an AI auto-fill tool.
- It is built for one person. There is no blind multi-reviewer voting or conflict resolution like Covidence or Rayyan.
- The Mac app is Mac-only. The web app closes this gap.

## 6. Can it survive? (the Shark Tank question)

**Gemini's verdict:** as a free GitHub repo, it is not ready for investors. The core idea can survive if it is positioned well.

**Why investors would say no today:**
- no revenue model
- the Mac-only version reaches too small a market
- install friction
- a niche audience

**How it competes with the AI giants.** It can't win on "fast AI summaries", so it sells what they lack:
- **Trust, not AI:** audit-ready, anti-hallucination, every claim linked to the exact PDF line. This matters as universities and journals crack down on AI.
- **High-stakes fields:** medical, UX and policy work, where fake quotes are unacceptable and PRISMA compliance is required.
- **Privacy:** R&D, pharma and legal teams can't upload confidential PDFs to cloud AI.

**What is needed before pitching investors:**
1. **Business model:**
   - a free tier for students
   - Pro at about $10–20 a month
   - campus licences for libraries and UX agencies
2. **One-click access:** the installer and the web app (in progress, Sieve Cloud).
3. **Traction:** 1,000+ active users or a few paying labs.

## 7. Target users (web app, privacy-first, log in anywhere)

A zero-install web app that keeps PDFs on the device (IndexedDB) and syncs only light project data across logins gives two things together: access from any computer, and privacy.

### Primary: paying users (focus first)
1. **Product and UX research teams.**
   - They synthesise interviews, competitor reports and studies into SWOT grids and design decisions.
   - They use mixed Windows and Mac machines and dislike installing software.
   - They have budgets of about $15–30 per seat per month.
2. **Healthcare, pharma and clinical researchers.**
   - They must follow PRISMA 2020 and can't risk hallucinations.
   - Covidence costs about $300+ per review, which leaves room for a simpler, private tool.
3. **Corporate strategy, legal and policy analysts.**
   - They read confidential PDFs.
   - Browser-local data passes IT security review more easily.

### Growth: volume users (traction and university sales)
4. **Master's and PhD students worldwide.**
   - They use Windows laptops, Chromebooks and library computers.
   - Auto PRISMA plus zero invented citations spreads by word of mouth.
5. **University libraries and research labs.**
   - Once about 50 students on a campus use the free tier, pitch the library a campus licence.

### Everyone who does literature reviews
| Group | Who | Why |
|---|---|---|
| University | UG, master's, PhD, professors | Capstones, theses, dissertations, grants, review papers |
| Healthcare | Doctors, clinical research assistants | Which treatments work; trial safety for regulatory approval |
| Business / tech / design | UX and product researchers, R&D, strategy analysts | Evidence before designing; patent and prior-art checks; investment decisions |
| Government / policy | Policy analysts, think tanks | Evidence before laws and public programmes |

---

## Pitch takeaways
- **Positioning:** "Humans read, Sieve does the paperwork." It is the trusted, audit-ready workspace, not another AI reader.
- **Beachhead:**
  - students (free) for traction
  - UX teams and clinical reviewers (paid) for revenue
  - libraries (campus licence) for scale
- **Moat:**
  - provenance to the exact PDF line
  - PRISMA that counts itself
  - local-first privacy
  - one tool instead of four
