# Sieve web app: design rules (16 Nov 2026)

From the user's notes (Refactoring UI / Steve Schoger, Chase AI, dev.to "10 UI mistakes") + ui-ux-pro-max (Minimalism & Swiss style). Brand colours and fonts stay as in `brand/`.

## Don't
- Box everything. Use whitespace and 1px hairlines to group; a card only when something is a separate object (the paper you're reading).
- UPPERCASE labels, letter-spaced eyebrows.
- Bold everywhere. 600 only for the one thing that matters in a block; headings are Instrument Serif 400.
- Odd sizes (13px, 12.5px). Faded grey text that fails 4.5:1.
- Hard offset shadows and thick outlines on every element (v1 "boxy" preview, kept as 00-old-screening-boxy.html).
- Indigo/purple, blue-tinted greys, gradients.

## Do
- 60-30-10: paper/mist backgrounds 60%, surfaces 30%, sky (primary action) + orange (progress) 10%. Coral only for exclude.
- Type scale: 12 / 14 / 16 / 20 / 28 / 40 px. Body 16 / line-height 1.5. Two families only.
- Spacing on a 4px grid: 4, 8, 12, 16, 24, 32, 48.
- Warm neutral greys from ink: text #302C28, muted #6B6560, hairline #E4E1DE.
- Mobile first: decisions reachable with a thumb, targets ≥ 44px, no horizontal scroll.
- Semantic HTML, visible focus rings, keyboard shortcuts shown quietly.
- Loading, empty and error states for every screen.
- Iterate: wide (several versions) → pick → refine with exact numbers, one change at a time.
