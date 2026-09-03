# Cadence — Visual Specification

Design reference for the appearance of all four surfaces (menu bar status item,
dropdown, timer window, widgets). The companion to
[Data Model & State Machine](data-model-and-state-machine.md), which covers what
the surfaces *read*; this covers how they *look*.

Scope: color, type, sizing, and component geometry. Layout behaviour is specified
only where it exists to keep something from moving between states.

- [1. Color](#1-color)
- [2. Type](#2-type)
- [3. Sizing](#3-sizing)
- [4. Components](#4-components)
- [5. Implementation notes](#5-implementation-notes)
- [6. Mockups](#6-mockups)

---

## 1. Color

### 1.1 Surfaces

| Token | Value | Use |
|---|---|---|
| Surface | `#0b1024` | Window, dropdown sheet, widget background |
| Surface / complete | `#04211c` | Same surfaces once a session finishes — the whole shell recolors, title bar included |
| Sheet | `rgba(32,32,35,0.94)` | Dropdown material, with vibrancy behind it |
| Fill / subtle | `rgba(255,255,255,0.07)` | Chips, secondary buttons, list rows |
| Fill / hover | `rgba(47,107,255,0.13)` | Row and preset hover |
| Hairline | `rgba(255,255,255,0.12)` | Dividers, 0.5px borders |
| Track | `rgba(255,255,255,0.10)` | Progress rule track |

### 1.2 Accents

| Token | Value | Use |
|---|---|---|
| Accent | `#2F6BFF` | Primary button, progress fill, running glyph, start actions |
| Accent / text | `#8FB4FF` | Accent-colored labels on dark ("Timer until 3:30") |
| Complete | `#2FE0A6` | Progress fill, glyph and primary button in the complete state |
| Complete / text | `#6FEFC6` | "Session complete" heading, complete numerals |
| Event | `#FF8A3D` | Calendar event color bar, event-named sessions |

Calendar rows inherit the source calendar's own color — `#2F6BFF`, `#2FE0A6`,
`#A184C8` all appear in the day list. Dismissed rows drop their bar to 40% and the
title to `rgba(235,235,245,0.42)`.

### 1.3 Text on dark

| Level | Value | Contrast on both shells |
|---|---|---|
| Primary | `#f2f2f5` | 15.9 : 1 |
| Secondary | `rgba(235,235,245,0.58)` | 5.4 : 1 |
| Tertiary | `rgba(235,235,245,0.50)` | 4.65 / 4.49 : 1 |
| Quaternary | `rgba(235,235,245,0.34)` | **2.78 : 1 — below AA, deliberate** |
| On accent | `#fff` on `#2F6BFF` · `#04211c` on `#2FE0A6` | |

Ratios are measured against `#0b1024` and `#04211c` with translucent levels
composited over the shell first, and are pinned by `CadenceTests/ContrastTests`.

**Quaternary is deliberately below AA and stays that way.** It is the recessive
fourth level — `end early by`, the day list's sync time, and the empty-calendar
lines — and lifting it to pass would collapse it into Tertiary, flattening four
levels into three. The constraint that makes this safe: **quaternary is never the
sole carrier of meaning a user must act on.** Every string it carries is either a
label beside brighter content or a statement that nothing is available, and in the
latter case the absence is itself the information. Any new copy that fails that
test belongs at Tertiary or above.

---

## 2. Type

Two families only. UI text is the system face; anything that counts is monospaced
with tabular figures so digits never shift width.

| Role | Family | Size / weight | Notes |
|---|---|---|---|
| Window numerals | IBM Plex Mono | 92px / 500, `-6px` tracking | tabular-nums; editable in place when stopped |
| Dropdown numerals | IBM Plex Mono | 38px / 500, `-1.5px` | |
| Widget numerals | IBM Plex Mono | 44px / 500, `-2.5px` | SwiftUI `.timer` text style in the real build |
| Section label | System | 11px / 600, `0.5px`, uppercase | "TODAY · WEDNESDAY" |
| Widget pane label | System | 10.5px / 600, `0.8px`, uppercase | "IN SESSION", "SESSION COMPLETE" |
| Button | System | 14px / 600 window · 12.5px / 600 dropdown + widget | |
| Event title | System | 13.5px / 400 window header · 13px / 600 strip + widget pane | |
| Body / row | System | 13px / 400 | Menu rows, day list titles |
| Status line | System | 12.5px / 400 | "running · ends 2:27 PM" |
| Caption | System | 12px / 400 | Event meta, session summary |
| Micro | System | 11.5px / 400 | "end early by", sync time |
| Monospaced meta | IBM Plex Mono | 12px list times · 11.5px preset lengths, buffer chips | tabular |

System face is `-apple-system` / SF Pro Text. Ship on SF and reserve IBM Plex Mono
for numerals; `ui-monospace` (SF Mono) is an acceptable substitute if Plex can't be
bundled.

---

## 3. Sizing

| Surface | Size | Radius |
|---|---|---|
| Timer window | 520 × 414 pt default, resizable | 12 |
| Dropdown sheet | 272 pt wide | 12 |
| Menu bar status item | 28 pt tall (system) | 5 on the countdown pill |
| Widget · small | 170 × 170 pt | 22 |
| Widget · medium | 364 × 170 pt | 22 |

### 3.1 Window row grid

Why the clock and buttons never move between states:

| Row | Height | Contents |
|---|---|---|
| Event title | 20 | Occupied whenever the session has a stored title; reserved otherwise |
| Numerals | 96 (+10 above) | |
| Swap slot | 62 (+10 above) | Idle: presets + buffer. Running / complete: 5px rule + status line |
| Buttons | 40 (+6 above) | |
| Calendar strip | 68, fixed | Footer; holds its height when empty |

The reserved event-title row and the fixed-height swap slot and strip are the whole
mechanism behind "without the layout jumping" and "the quick durations disappear
once a session starts" — the rows are always allocated, only their contents change.

The title row follows the *stored* title, not the running state: a meeting session
that has been reset is idle but still named, because `reset` keeps the plan
(data model §5). The row therefore stays occupied until a different session
replaces the title.

**Any row list inside the window scrolls rather than overflowing.** The grid
allocates a fixed height to the day list's rows, and a busy calendar has more
events than fit — the header and the 68 pt footer stay pinned, and only the rows
scroll. A list that grows the layout instead would push its own footer off the
bottom of a window whose minimum size is 520 × 414.

### 3.2 Resizing

520 × 414 pt is the window's **default and minimum**, not its only size. The grid
above survives resizing because it stretches in exactly one place:

- Every row keeps its stated height. The event-title row stays reserved, the swap
  slot stays 62 pt, the strip stays pinned to the bottom edge at 68 pt.
- **Extra height goes to flexible space above and below the numerals block**, which
  stays optically centred. Nothing in the grid grows.
- Extra width widens the rows' content — the progress rule, the strip, the button
  row — while the numerals stay centred at their specified size.

The numerals do **not** scale with the window. They are 92 pt because that is the
size the design asks to be readable across a room; making them track the frame
would turn a deliberate value into an accident of how the user last dragged a
corner.

**The colon sits on the window's centre line**, not the numerals block. The two
halves are symmetric columns of equal width — minutes trailing-aligned, seconds
leading-aligned — so typing a third minute digit widens the left column without
sliding the clock sideways. Centring the *block* instead would shift the colon
28 pt right at `295:00`, which is the same class of jump §3.1 exists to prevent.

### 3.3 Empty-calendar copy

The two surfaces say different things, deliberately:

| Surface | Copy |
|---|---|
| Dropdown | `Nothing on your calendar today` |
| Window strip | `Nothing else on your calendar today` |

The dropdown states a fact about the day. The window strip describes *what is
next* — and reaches its empty state both when the day is genuinely empty and when
every remaining event has been dismissed, so "nothing else" is the wording that is
true in both cases.

---

## 4. Components

| Element | Spec |
|---|---|
| Progress rule | 5px tall, 3px radius (4px / 2px in dropdown and widget) |
| Primary button | 10 × 32px padding, 9px radius |
| Secondary button | 10 × 18px padding, 9px radius, 0.5px hairline |
| Preset chip | 7 × 13px padding, 8px radius |
| Buffer chip | 2 × 6px padding, 4px radius |
| Icon button | 28 × 28 strip · 24 × 24 refresh, 6–7px radius |
| Event color bar | 3px wide, 2px radius |
| List row | 9 × 8px padding, 8px radius, 6px gap |
| Shadow · window | `0 24px 60px rgba(0,0,0,0.4)` + `0 0 0 0.5px rgba(0,0,0,0.3)` |
| Shadow · sheet | `0 12px 34px rgba(0,0,0,0.44)` |
| Shadow · widget | `0 10px 30px rgba(0,0,0,0.42)` |

Widget tap targets are 30pt minimum, and every widget control is a single App
Intent.

---

## 5. Implementation notes

**Tokens live in one place.** All values above are declared once in
`Shared/DesignTokens.swift` and referenced by name from every surface. No literal
hex or px in a view body — the app and widget extension both compile the token
file, which is what keeps the two processes visually identical.

**The px values are pt values.** The spec was authored against an HTML design
export; on macOS every number here is read as points. No conversion.

**State drives surface color, not a modifier per view.** `Surface` and
`Surface / complete` swap at the shell level so the window's title bar recolors
with its content. Derive from `effectiveStatus(now)`, never the stored `status`.

**Countdown text.** The window and widget use monospaced tabular digits so the
numerals don't reflow as they count. The menu-bar item redraws from a 1 s display
ticker (see the development plan, D1); the widget uses `Text(timerInterval:)`.
Neither is authoritative for completion.

---

## 6. Mockups

Nineteen 2× PNG mockups — one per surface × state — live in
[docs/design/mockups](design/mockups), indexed by
[their README](design/mockups/README.md). They are the composition reference for
every build stage.

| Surface | Mockups |
|---|---|
| Timer window | `timer-window--idle-with-event`, `--idle-next-event-suggested`, `--idle-no-events`, `--idle-day-list-expanded`, `--running-meeting-session`, `--running-no-event`, `--complete` |
| Dropdown | `menu-bar-dropdown--idle`, `--running`, `--complete`, `--no-events` |
| Widget small | `widget-small--idle`, `--running`, `--complete` |
| Widget medium | `widget-medium--idle-suggestions`, `--running`, `--running-no-event`, `--complete`, `--complete-no-event` |

The menu bar status item has no standalone mockup; its three states appear in the
menu bar chrome above each dropdown mockup.

Each stage's exit criteria include a side-by-side against the matching mockups.
Where a mockup and this document disagree, this document wins for measurements and
the mockup wins for composition — and the discrepancy gets fixed here.
