# Cadence — state screenshots

Exported from `Handoff Screenshots.dc.html` (capture harness; each state isolated on a neutral field). 2× PNG.

## Timer window — 520×414pt

| File | State |
|---|---|
| `timer-window--idle-with-event.png` | Idle. Quick durations + end-early buffer chips visible; calendar footer shows next event with "Timer until…" action. |
| `timer-window--running-meeting-session.png` | Running, session named from the calendar event. Duration presets and "Timer until…" hidden. |
| `timer-window--running-no-event.png` | Running, no event attached — no stored session name. |
| `timer-window--complete.png` | Complete. Mint wash, `1:48–2:13 PM · 25 min focused`, Start another / +5 min. |
| `timer-window--idle-next-event-suggested.png` | Idle, next event suggested after the first was dismissed. |
| `timer-window--idle-no-events.png` | Idle, empty calendar — strip holds its height, offers refresh. |
| `timer-window--idle-day-list-expanded.png` | Idle, full day list expanded over the timer (`☰`). |

## Menu bar dropdown — 272pt sheet

| File | State |
|---|---|
| `menu-bar-dropdown--idle.png` | Idle. Status item shows icon only. Presets incl. meeting-linked option. |
| `menu-bar-dropdown--running.png` | Running. Blue status icon + countdown; Pause / Reset. |
| `menu-bar-dropdown--complete.png` | Complete. Mint status icon + `00:00`; Start another / +5 min. |
| `menu-bar-dropdown--no-events.png` | Idle, empty calendar — durations only, "Nothing on your calendar today". |

## Widgets — WidgetKit small (170pt) and medium (364×170pt)

| File | State |
|---|---|
| `widget-small--idle.png` | Small, ready. |
| `widget-small--running.png` | Small, running. |
| `widget-small--complete.png` | Small, complete. |
| `widget-medium--idle-suggestions.png` | Medium, ready — suggestion rows as App Intent buttons. |
| `widget-medium--running.png` | Medium, running — suggestions hidden, "In session" pane. |
| `widget-medium--complete.png` | Medium, complete — session summary. |
| `widget-medium--running-no-event.png` | Medium, running, no event — falls back to "25 minute session". |
| `widget-medium--complete-no-event.png` | Medium, complete, no event. |

Behavior and acceptance criteria: `../Interfaces & User Stories.md`.
Assets for Xcode: `../handoff/assets/` (AppIcon.appiconset, CadenceStatusIdle/Running imagesets).
