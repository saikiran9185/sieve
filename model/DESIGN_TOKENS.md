# Sieve 2.0 web app: tokens and components for the Figma library

These are the exact values the web app uses now (`web/app.css`, direction "A · Paper").
Build Figma variables with the same names so design and code stay one system.

## Colour: brand (same in both modes)
| Token | Hex | Use |
|---|---|---|
| sky | #A9D6FE | Primary action (Keep, Find papers, Add), current step, PRISMA "included" |
| orange | #F58B23 | Progress bars, find-in-page hits, the dot in the wordmark. Never text |
| coral | #FAA09B | Exclude only: dot, hover, exclusion terms |
| ink | #302C28 | Text in light mode; text on sky/coral/orange in both modes |
| mist | #EDECED | Reserved |
| paper | #FFFFFF | Text in dark mode |

## Colour: surfaces
| Token | Light | Dark |
|---|---|---|
| bg (page) | #FFFFFF | #1E1B19 |
| side (sidebar, rails) | #F6F5F4 | #24211F |
| raised (inputs, sheets) | #FFFFFF | #2A2623 |
| sunk (callouts, PDF backdrop, chips) | #F6F5F4 | #191715 |
| hover | #F3F1EF | #2E2A27 |
| current (selected row/nav) | #ECEAE8 | #38332F |
| line (hairline) | #E4E1DE | #3A3532 |
| line-strong | #CFCAC5 | #4D4743 |
| text | #302C28 | #FFFFFF |
| dim (secondary text) | #6B6560 | #B9B2AC |
| faint (hints, counts) | #77716B | #A39C95 |

Status only (dots, never decoration): emerald #2E7D55 / #6FD39C · rose #B23A33 / #F38B83 · amber #8A6A12 / #E6C060 · focus #2F6FB0 / #8CC2F5.

## Type
Instrument Serif 400 for headings, numbers and reading text. Public Sans 400 + 600 for UI.
| Style | Font | Size / line |
|---|---|---|
| Display | Instrument Serif | 40 / 1.1 (paper title, stat numbers) |
| H1 page title | Instrument Serif | 28 / 1.1 |
| H2 section | Instrument Serif | 20 / 1.3 |
| Reading | Instrument Serif | 20 / 1.6 (abstract), 18 / 1.55 (quote) |
| Body | Public Sans 400 | 14 / 1.5 (UI), 16 (inputs on Find, phone) |
| Label strong | Public Sans 600 | 14 |
| Small | Public Sans 400 | 12 / 1.5 |
No uppercase. 600 only for the one thing that matters in a block.

## Spacing, radius, elevation
- Spacing: 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64
- Radius: 6 (small controls) · 8 (buttons, rows, inputs) · 12 (Keep, callouts, PRISMA boxes) · 16 (sheets, empty-state panels) · 99 (pills)
- Elevation: none on the page. Sheets/menus: `0 1px 2px rgba(48,44,40,.06), 0 12px 32px rgba(48,44,40,.10)`. Dark mode swaps shadow for a 1px #3A3532 ring.
- Hairline: 1px `line`. No outlines around cards; rows are separated by hairlines.

## Layout
- Sidebar 232 · screening queue 288 · decision rail 304 · reader rail 256 · inspector 344
- Page head: 64 high, padding 20/32/12. Toolbars: padding 8/32/12, hairline under
- Breakpoints: 1180 (queue/rails narrow), 860 (phone: drawer + bottom tab bar)
- Phone: tab bar 52 + safe area (Home, Find, Screen, Read, More); targets ≥ 44

## Components to build
1. Button: primary (sky), default (raised + hairline), quiet (text only), icon, danger
2. Input / search / select / textarea (hairline, focus = 2px focus colour)
3. Nav item (default / hover / current) + count badge
4. Segmented control (sunk track, raised selected thumb)
5. Chip = 6px colour dot + 12px dim label (no filled pills)
6. Row (list item with hairline) and queue item (current = `current` fill)
7. Stat (serif 40 number + 12 label, divided by hairlines)
8. Progress: thin 4px orange bar; funnel bar 8px with sky/orange/coral/grey parts
9. Keep button (sky, 56 high, label + sub + key hint) and exclude reason row (key hint on the right, coral hover; pill on phone)
10. Callout (sunk / orange-tint) · Toast (ink, white text) · Sheet (16 radius)
11. Empty state: 160 sky circle with line-art cat + serif 28 title + one sentence + one action
12. PRISMA box (hairline-strong, 12 radius; included = sky fill)
13. Tab bar (phone) and drawer
14. Sync status line (6px dot: green synced, orange syncing, red paused, amber offline)

## Illustrations used
`web/img/cat-find.png` (magnifier cat: Find, home empty state), `web/img/cat-wave.png` (peek-wave cat: Screening/Library empty), `web/img/cat-clipboard.svg`. Shown in a sky circle with multiply blend so the white drops out.
