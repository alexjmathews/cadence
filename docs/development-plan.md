# Cadence — Development Plan

How Cadence gets built, in six stages with a shippable milestone at each. The
companion to [Data Model & State Machine](data-model-and-state-machine.md) (what
the data is) and [Visual Specification](visual-specification.md) (what it looks
like); this document covers sequencing, exit criteria, and the decisions that shape
the code.

- [1. Starting point](#1-starting-point)
- [2. Architectural decisions](#2-architectural-decisions)
- [3. Stages](#3-stages)
- [4. Milestones](#4-milestones)
- [5. Risks](#5-risks)
- [6. Testing strategy](#6-testing-strategy)
- [7. Story coverage by stage](#7-story-coverage-by-stage)

---

## 1. Starting point

The repo is a working shell that proves the plumbing, not the product. What exists:

- **XcodeGen project** ([project.yml](../project.yml)) with an app target and an
  embedded `CadenceWidget` app-extension target, both sourcing `Shared/`, both
  entitled to `group.com.alexmathews.cadence`.
- **Menu-bar-only lifecycle** — `LSUIElement`, `.accessory` activation policy,
  `MenuBarExtra` with the ink-mark status images, window launch suppressed,
  accessory demotion on window close.
- **App Group round-trip** — `SharedStore` writes a state record; the widget reads
  it and renders a self-updating countdown with an `endsAt`-driven timeline policy.
- **`cadence://` URL handling**, an App Intent invoked from the widget, an
  `AppShortcutsProvider`, notification authorization, and `SMAppService`
  launch-at-login.
- **Assets** — `AppIcon`, `CadenceStatusIdle` and `CadenceStatusRunning` imagesets
  (template-rendered).

What does not exist: any of the product. The design doc is unimplemented, and the
demo model actively contradicts it — `CadenceSessionState` is a break-phase
Pomodoro (`focus` / `shortBreak` / `longBreak`) where the spec has a plan/run
session with `idle` / `running` / `paused` / `complete`. There is no `Preferences`,
no calendar, no state machine, no transitions, and no guards.

So stage 0 is a **replacement**, not an extension. Everything in the bullet list
above is worth keeping as infrastructure; everything demonstrating it is worth
deleting.

**Explicitly out of scope**, per the data model doc: session history, break
phases, and any persistence beyond the four App Group records.

---

## 2. Architectural decisions

Recorded here because each one has consequences in more than one stage.

**D1 — The menu bar redraws from a 1 s display ticker; the ticker is never
authoritative.**
`Text(timerInterval:)` does not reliably self-update inside a `MenuBarExtra` label,
so the status item's countdown is driven by a 1 s repeating timer in the app. This
does not weaken P1 ("store a deadline, never a counter"): the ticker only asks
`remaining(now)` and redraws. It never decrements stored state, never fires the
`complete` transition, and its cadence has no bearing on accuracy. Completion is a
scheduled event against `endsAt` (D3) plus `effectiveStatus(now)` derivation, so a
dropped, throttled, or asleep ticker can cost a frame but never a minute. The
ticker runs only while `effectiveStatus == .running`.

**D2 — Widget intents write the App Group directly.**
An intent invoked from a widget mutates `sessionState` in the widget extension's
own process rather than round-tripping through the app, so the controls work with
the app quit and never foreground it. The consequence is two writers, which forces
two properties on the code:

- every transition is a **pure function** of the current state, the arguments the
  caller has already resolved, and an injected `now` — `(SessionState, …, Date) →
  SessionState` in `Shared/` — so both processes compute identically. Preferences
  do not appear in the signature: the buffer is materialised into a duration by the
  caller before `start` is invoked (P4), which keeps the transitions ignorant of
  where their numbers came from;
- the app **observes** the container rather than trusting its in-memory copy —
  `UserDefaults.didChangeNotification` on the suite plus a re-read on
  `NSApplication.didBecomeActiveNotification` and on wake.

Writes are read-modify-write on a single small record, and the two processes only
ever contend on deliberate user action, so `cfprefsd` mediation is sufficient — no
lock file, no coordination protocol.

**D3 — Completion is a scheduled notification, never a timer callback. Each writer
owns its own alarm.**
At `start` / `resume` / `extend`, schedule one `UNNotificationRequest` with a
trigger derived from `endsAt`, under a stable identifier. `pause` and `reset`
cancel it. This is what makes the alarm survive sleep, app quit, and a throttled
process. Nothing about completion depends on a process being awake to count.

**Amended after Stage 4 measured it.** This decision originally said scheduling
belonged to the app and intents would only *cancel*, with the app reconciling
pending requests when it next observed the container. That is not implementable on
macOS 26, and the measurements are unambiguous: the app and the widget extension
get **two separate notification stores**. An extension *can* schedule — it inherits
the containing app's authorization without prompting, `add()` succeeds, and the
request fires even after the extension process is gone — but the app cannot
enumerate or cancel what the extension scheduled, and the extension cannot cancel
what the app scheduled. Each side sees only its own bucket.

So the original fallback fails in both directions. A widget `pause` could not cancel
the app's alarm, leaving it armed to fire against a stopped session — worse than the
missing alarm the risk row feared. And "the app reconciles later" does not cover the
case it existed for: with the app quit for the whole session, which D2 makes the
ordinary widget case, nobody is there to schedule and nobody is there to reconcile
before the deadline.

The shape that works: **whichever process performs the transition schedules and
cancels its own alarm**, through a scheduler in `Shared/` that takes the store as an
argument so both processes run identical code. Duplicate alarms — one per bucket for
the same session — are then possible when both processes act on one session, and are
handled at delivery through the existing `UNUserNotificationCenterDelegate` rather
than by trying to keep the two stores in sync.

One trap, recorded because it cost Stage 4 three attempts: `UNUserNotificationCenter`
`.current()` throws `bundleProxyForCurrentProcess is nil` for any process whose
bundle LaunchServices does not know, and `lsregister` on a scratch path is not
enough. That is an artefact of bundle location, not evidence about extensions — a
proxy binary run from a scratch directory cannot answer this question at all.

**D4 — Every surface derives status; none trusts the stored value.**
`effectiveStatus(now)` is the only status a view reads. A session whose deadline
passed while the machine slept reads as complete on the next render without anyone
having transitioned it.

**D5 — Design tokens are declared once, in `Shared/`.**
`Shared/DesignTokens.swift` holds every value in the visual spec; no view body
contains a literal color or metric. Both targets compile it, which is what keeps
the app and the widget visually identical.

**D6 — The dropdown is a window, not a menu.**
The 272 pt sheet requires `.menuBarExtraStyle(.window)`; the current `.menu` style
cannot render it.

**D7 — A clock target means what its label says; the buffer is meeting-only.**
`To 2:30` ends at 2:30, so at 2:13 it reads `17 min`, not the `15 min` drawn in the
dropdown mockup. Every preset row in that mockup is exactly two minutes short —
which happens to equal both the 2 m buffer and a floor-to-nearest-5 — but §4
defines `clockTargets` without a buffer, and a label that promises 2:30 while
ending at 2:28 is a small lie the product doesn't need. The end-early buffer stays
what §2.2 says it is: a rule for *meeting-linked* sessions, where walking in late
is the thing being avoided. Mockup minute counts are therefore not authoritative;
the derivation is.

**D8 — `Quit Cadence` is a row in the sheet; launch-at-login is not.**
The dropdown mockup shows neither, but Cadence is menu-bar-only: a user who never
opens the window would otherwise have no way to quit it, since `⌘Q` needs the app
promoted to regular first. Quit is added as a footer row below `Open Cadence`,
growing the sheet past the mockup's height by one row. Launch-at-login is *not*
surfaced there — it is a set-once preference, not a per-session action, and
`LoginItemManager` stays unreferenced until Stage 5 gives it a home.

**D9 — The editable numerals are two numeric fields, not one text field.**
Minutes and seconds are separate inputs with the colon drawn as immovable chrome
between them, so it cannot be deleted, duplicated, or typed into. Each field
accepts **digits only** — non-numeric keystrokes are refused at input rather than
validated afterwards, so there is no such thing as a malformed entry to reject.
`Tab` and `Shift-Tab` move between the two fields, and `Return` starts the session
from either. This replaces a single free-text field parsed against a grammar: a
grammar has to define what `1:2:3::` means, whereas two numeric fields make most of
those states unreachable. Seconds are still clamped to `0…59`; minutes carry any
larger value.

Refusal has to happen where AppKit asks *before* the field editor adopts text, not
in a SwiftUI `Binding` setter. A setter that declines to write does not revert an
`NSTextField` — it keeps its own live editing text, so the refused keystroke stays
on screen while the committed plan silently diverges from it. The hook that is
actually consulted is a `Formatter`'s `isPartialStringValid`, which covers typing,
paste, and IME input alike; the delegate callbacks that look like the right place
(`control(_:textView:shouldChangeTextIn:replacementString:)`) are not part of
`NSControlTextEditingDelegate` and are never called.

Committing per keystroke is likewise wrong: it walks `plannedDuration` through
every intermediate value, so clearing the minutes field to retype it briefly
commits a 9-second plan to the App Group and reloads every widget timeline.
**Commit on blur or `Return`**, and never commit an empty field.

**D10 — The clock is never compressed, ellipsed, or truncated. Everything else
yields to it.**
A 60-minute meeting-linked session rendered `60:...` in the dropdown: the numerals
and the session title share a row, and the title won. That is backwards — the
clock is the one thing every surface exists to show, and a session named after a
long meeting title is exactly when the remaining time matters.

So: the numerals take layout priority over any label beside them, and the title
truncates instead. Since `ClockFormatter` carries minutes past 59 rather than
rolling over to hours (a deliberate Stage 2 decision — `1:05:00` does not fit the
numeral treatment), the widest legitimate clock is **three minute digits plus two
seconds**: `600:00`.

Surfaces that can widen, do: the dropdown sheet and the menu bar pill are sized to
fit `600:00` outright. The widget families cannot — 170 × 170 and 364 × 170 are
fixed by WidgetKit — so there the numerals scale down to fit, which is acceptable
because the whole clock stays on screen and legible. **What is never acceptable is
an ellipsis, a truncation, or a clock that leaves the surface.** Scaling preserves
the reading; the other three destroy it.

---

## 3. Stages

### Stage 0 — Core model & engine

No UI. Deletes the demo and lands the spec.

**Remove**

| Path | Why |
|---|---|
| `Shared/CadenceSessionState.swift` | Replaced by `SessionState` — wrong model (break phases) |
| `Shared/NotificationService.swift` | Demo notification pipeline; stage 5 rebuilds it around `endsAt` |
| `Shared/SendNotificationIntent.swift` | Demo intent; stage 4 introduces the real intent surface |
| `Cadence/CadenceShortcuts.swift` | Exposes only the demo intent; returns in stage 5 |
| `Cadence/NotificationManager.swift` | Test-notification harness; authorization moves into stage 5's scheduler |
| `Cadence/ContentView.swift` | Placeholder; stage 2 replaces it with the timer window |
| `raycast/cadence/src/send-notification.ts` | Demo command; stage 5 replaces it with real transitions |

The `cadence://notify` branch in `AppDelegate` goes with it; the URL-type
declaration in `Info.plist` and the scheme handler stay. `LoginItemManager` stays.

**Build**

- `Shared/SessionState.swift` — `SessionStatus`, `SessionState` with the plan/run
  split exactly as specified, including `focusedBefore` / `segmentStartedAt`.
- `Shared/Preferences.swift` — `endEarlyBuffer`, `lastUsedDuration`.
- `Shared/SessionTransitions.swift` — the seven transitions as pure functions with
  their guards (`extend` only from `complete`; `start` never from `running` /
  `paused`; duration selection only in `idle`). Guard violations are no-ops, not
  crashes — a stale widget can legitimately ask for an illegal transition.

  Precisely: every transition reconciles against `now` first (D4), then guards. So
  a rejected transition returns the *reconciled* state, which equals the input
  except when the deadline has silently passed — a stale widget's `pause` on an
  elapsed session returns a **completed** state, not a running one. That is
  deliberate: the session already reads as complete on every surface, so persisting
  the completion is more honest than handing back a `running` state that no
  surface would agree with.
- `Shared/DerivedValues.swift` — `effectiveStatus`, `remaining`, `focused`,
  `progress`, `displayName`, `span`, `summaryLine`, `clockTargets`. Calendar-
  dependent derivations (`suggestedEvent`, `canStartMeetingTimer`) land in stage 3.
- `Shared/SharedStore.swift` — rewritten: four typed records, day-scoped validation
  on read for `calendarSnapshot` and `dismissedEvents`, `WidgetCenter` reload on
  write. Stage 0 uses the first two keys; the calendar accessors are written but
  unexercised until stage 3.
- `Shared/DesignTokens.swift` — the whole visual spec as named tokens (D5). No
  views consume it yet.
- A `CadenceTests` unit-test target in `project.yml`.

**Exit criteria**

- Every transition in §5 of the data model doc has a test asserting the full
  post-state, including which fields were *cleared*.
- Every guard has a test asserting the state is unchanged.
- Reconciliation tests: deadline elapsed while quit, machine asleep across the
  deadline, wall-clock moved backwards, `plannedDuration` exhausted by `extend`.
- Focus-accounting test reproducing the doc's worked example — a session started
  1:48, paused 5 min, finishing 2:18 reports a 1:48–2:18 span and 25 min focused.
- Round-trip test: encode → App Group → decode is identity for all four records.
- App still launches with a menu bar item and no product UI.

### Stage 1 — Menu bar status item + dropdown

First vertical slice, and the first daily-drivable build. No calendar.

- Switch to `.menuBarExtraStyle(.window)` (D6) and build the 272 pt sheet:
  numerals + status word, 4 pt progress rule, primary and secondary actions,
  preset rows, `Open Cadence ⌘O`.
- Status item: idle mark only, running mark + countdown pill, complete mark +
  `00:00`. Add the missing mint `CadenceStatusComplete` imageset alongside the two
  existing ones.
- The 1 s ticker (D1), scoped to running.
- Presets: `45 minutes` plus the two derived `clockTargets` with their minute
  counts. The meeting row is stubbed out until stage 3.
- Container observation (D2) so a Raycast- or widget-driven change is reflected
  live.

**Exit criteria** — start / pause / resume / reset / +5 / start-another all work
from the dropdown; the status item shows the right mark and time in all three
states; a session survives quit and relaunch reading correctly; matches
`menu-bar-dropdown--idle`, `--running`, `--complete` mockups modulo the calendar
row.

### Stage 2 — Timer window

- The 520 × 414 pt window on the row grid from the visual spec — reserved
  event-title row, 96 pt numerals, the 62 pt swap slot, buttons, and the 68 pt
  strip holding its height. **Resizable**, with 520 × 414 as the default and
  minimum; per visual spec §3.2 the rows keep their heights and only the space
  around the numerals stretches. Getting the grid right here is what makes stages
  3–4 free of layout jump.
- Editable numerals: two digits-only fields either side of a fixed colon, `idle`
  only, `Tab` / `Shift-Tab` between them, `Return` to start, committing to
  `plannedDuration` (D9).
- Quick durations and buffer chips; the chips write `preferences.endEarlyBuffer`
  and show the active value highlighted.
- Running: progress rule, `started · ends` status line. Complete: mint shell
  recolor including the title bar, `summaryLine`, `Start another` / `+5 min`.
- The calendar strip renders its empty state only; the footer's fixed height is
  real from day one.

**Exit criteria** — every window story except the calendar strip's; presets and
`Timer until…` are absent while running or complete; numerals are not editable
outside `idle`; the buffer round-trips through relaunch; the grid holds its
geometry at the minimum size and when the window is dragged larger; matches
`timer-window--idle-with-event` (minus the strip's event), `--running-no-event`,
`--complete`.

### Stage 3 — Calendar

The riskiest stage: the only place Cadence talks to a system store, and the only
one gated by TCC.

- EventKit access request and the three `CalendarAccess` states, including the
  connect affordance and revocation clearing the snapshot.
- Fetch via `predicateForEvents(withStart:end:calendars:)` for today, excluding
  all-day events, keyed `eventIdentifier|occurrenceStartEpoch`, into a
  `CalendarSnapshot` carrying nothing but title / start / end / key / color.
- `DismissedEvents` as a day-scoped record; `suggestedEvent` and
  `canStartMeetingTimer` derivations.
- Window strip: event row with color bar, `ends N min early` reflecting the saved
  buffer, `Timer until <time>`, `☰` day list expanded over the timer, `✕` dismiss,
  refresh with last-synced time.
- Meeting-linked start: re-resolve the occurrence key against the live store,
  materialise `endsAt = eventStart − buffer`, copy the title, record
  `linkedEventKey` — all at the moment Start is pressed (P4).
- Dropdown gains its `To <event>` row.

**Exit criteria** — dismissing promotes the next event without the layout moving; a
refresh mid-session never retimes the running session; changing the buffer
mid-session never retimes it either; a meeting timer started from the dropdown and
from the window produce identical state; revoking calendar access degrades to the
empty state rather than showing stale events; matches
`timer-window--idle-next-event-suggested`, `--idle-no-events`,
`--idle-day-list-expanded`, `--running-meeting-session`,
`menu-bar-dropdown--no-events`.

### Stage 4 — Widgets

Cheap by construction: the widget is a pure reader plus intent writers over a
model that stopped moving in stage 3.

- Replace the demo widget with small and medium families on the visual spec's
  geometry and radii.
- Small: three states. Medium: the tile plus a context pane — suggestions when
  idle, "In session" when running, summary when complete — each with and without an
  event, falling back to `displayName` when `title == nil`.
- App Intents for start / pause / reset / +5 and the medium suggestion rows,
  including meeting-linked start with the saved buffer. Each is one intent, 30 pt
  minimum target, writing directly (D2) through the shared pure transitions.
- Timeline policy `.after(endsAt)` while running, `.never` otherwise;
  `Text(timerInterval:)` for the countdown.
- Empty-calendar copy instead of a blank suggestion row.

**Exit criteria** — every widget control works with the app quit and never
foregrounds it; the app reflects a widget-driven change within a second of
becoming active; suggestions are absent while running; all five medium mockups and
three small mockups match.

### Stage 5 — Hardening & release candidate

- **Clock legibility on the menu bar surfaces (D10).** The dropdown renders
  `60:...` today for a session named after a long meeting: widen the sheet and the
  pill to fit `600:00`, give the numerals layout priority over the adjoining
  label, and truncate the title instead. Both widget families were verified in
  stage 4 to fit `600:00` by scaling, so they need no change; the window's 92 pt
  numerals still want one check against three digits.
- Completion notifications on the D3 model, with the authorization request moved
  out of launch and into first schedule.
- Sleep / wake, clock-change, and day-rollover reconciliation exercised on real
  hardware, not just in tests.
- **A comment that lies.** `SessionController.tick()` claims to bank the completion
  once, and does not: `SharedStore.loadSessionState` already reconciles on read, so
  the `next != base` guard is always false for a pure reconciliation and the stored
  record keeps `status: running` with an elapsed `endsAt` and no `completedAt`.
  Harmless — reconciliation is a deterministic function of the stored record, so
  every reader derives the identical completed state — but either the code or the
  comment has to change, and a persisted `complete` is the honest one now that D3
  gives each writer an alarm to cancel.
- `cadence://` and the Raycast extension rebuilt against the real transitions —
  start with a duration, pause, reset, extend — replacing the notify demo.
- `CadenceShortcuts` reinstated over the real intents.
- Full visual pass against every mockup; token audit confirming no literal values
  escaped into view bodies.
- Accessibility: VoiceOver labels on every control, Reduce Motion honored on the
  progress rule, contrast check on secondary text over both shells.
- Traceability sweep — every story in the interfaces doc and every row in §6 of
  the data model doc demonstrably satisfied.

**Exit criteria** — a week of daily use with no state corruption, no missed alarms,
and no surface disagreeing with another.

---

## 4. Milestones

| # | Milestone | Lands | Why here |
|---|---|---|---|
| M1 | State machine provably correct, zero UI | Stage 0 | Four surfaces are projections of this; a bug here multiplies by four |
| M2 | Usable timer from the menu bar | Stage 1 | Daily-drivable immediately — the fastest way to surface model mistakes |
| M3 | Feature-complete minus calendar | Stage 2 | Buffer preference exists before anything consumes it |
| M4 | Calendar-aware window and dropdown | Stage 3 | System-store integration isolated to one stage |
| M5 | All four surfaces agree | Stage 4 | Widgets built against a settled model, not a moving one |
| M6 | Release candidate | Stage 5 | |

---

## 5. Risks

| Risk | Stage | Mitigation |
|---|---|---|
| `MenuBarExtra` label won't redraw per second even with a ticker | 1 | Verify empirically in the first hours of stage 1; fall back to an `NSStatusItem` managed by `AppDelegate`, which is fully under our control |
| A widget extension may not be permitted to post local notifications | 4–5 | **Resolved in stage 4: it may.** An extension inherits the app's authorization without prompting, `add()` succeeds, and the alarm fires after the extension is gone. The real problem is the opposite one — app and extension get separate notification stores, so neither can cancel the other's alarm. D3 is amended accordingly: each writer owns its own alarm, and duplicates are handled at delivery |
| Recurring-event identifiers unstable across sync/edits | 3 | Composite occurrence key, day-scoped dismissals, and re-resolution at start time — all three already in the data model doc; a stale key fails as "no suggestion", never as a wrong timer |
| Two writers race on `sessionState` | 1–4 | Pure transitions in `Shared/` plus container observation (D2); contention only on deliberate user action |
| Resizable window against a grid built to hold its geometry | 2 | Rows keep their heights; only the space around the numerals stretches (visual spec §3.2). Truncate event titles rather than reflow, and verify the grid at the minimum size and dragged large |
| IBM Plex Mono licensing / bundling | 2 | Ship on SF Mono per the visual spec's substitution clause; bundle only if it's worth the target size |
| App Group `UserDefaults` writes silently dropped when the container is unavailable | 0 | Store returns a result and logs; a failed write must never leave a live in-memory state that disagrees with disk |

---

## 6. Testing strategy

**Unit (stage 0 onward, `Shared/` only).** Transitions, guards, derived values,
reconciliation, encode/decode round-trips. All pure functions with injected `now` —
no clock, no container, no UI. This is where correctness lives, and it is why stage
0 ships without a single view.

**Store integration (stage 0, extended per stage).** Real App Group container:
write in one process's code path, read in the other's; day-scope invalidation;
missing and corrupt records.

**Calendar (stage 3).** A seam over EventKit so recurrence expansion, all-day
exclusion, and the three access states are testable against fixtures. The live
store is exercised by hand.

**Visual (each stage's exit).** Side-by-side against the stage's mockups at 2×.

**Cross-surface (stages 4–5).** A matrix walk: perform each transition from each
surface, assert the other three agree. This is the only test that catches D2
divergence.

---

## 7. Story coverage by stage

Rows are the interfaces doc's coverage matrix; cells are the stage that lands them.

| Story area | Menu bar | Dropdown | Window | Widget |
|---|---|---|---|---|
| See remaining time | 1 | 1 | 2 | 4 |
| Start a session | — | 1 | 2 | 4 |
| Pause / resume | — | 1 | 2 | 4 |
| Reset | — | 1 | 2 | 4 |
| +5 min after complete | — | 1 | 2 | 4 |
| Quick duration presets | — | 1 | 2 | 4 |
| Custom typed duration | — | — | 2 | — |
| Set end-early buffer | — | — | 2 | — |
| Honour saved buffer | — | 3 | 3 | 4 |
| Pick from calendar events | — | 3 | 3 | 4 |
| Dismiss / expand events | — | — | 3 | — |
| Calendar refresh | — | — | 3 | — |
| Session summary on complete | — | 1 † | 2 | 4 |
| Empty-calendar handling | — | 3 | 2 | 4 |

Completion notification, Raycast / URL parity, launch at login, accessibility, and
the visual pass are cross-cutting and land in stage 5.

† **The dropdown's complete state carries the status word, not the summary line.**
`menu-bar-dropdown--complete.png` shows `00:00 · complete` and no span — a
`1:48–2:13 PM · 25 min focused` line does not fit beside 38 pt numerals in 272 pt,
and the interfaces doc asks the dropdown only for "start a fresh session from the
complete state". The full summary is the timer window's job (stage 2) and the
medium widget's (stage 4). The matrix row stays ticked for the dropdown because
the *complete state* is surfaced there; the span and focused total are not.
