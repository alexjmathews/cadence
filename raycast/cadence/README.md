# Cadence (Raycast extension)

A local Raycast extension that drives the [Cadence](../../) macOS app over its
`cadence://` URL scheme. Every command is a fire-and-forget `no-view` command:
it opens a URL, shows a HUD, and closes. There are no list or detail views
because there is no state to render — Cadence itself owns the session.

## Commands

| Command | URL | Notes |
| --- | --- | --- |
| **Start Session** | `cadence://start` | Starts with the stored plan — the duration you last chose. |
| **Start Timer** | `cadence://start?minutes=45` | Takes a `minutes` argument (whole number, 1–999). Leave it blank to fall back to the stored plan. |
| **Pause Session** | `cadence://pause` | |
| **Resume Session** | `cadence://resume` | |
| **Reset Session** | `cadence://reset` | Back to idle from any state. |
| **Extend Session** | `cadence://extend` | The "+5 min" action. Legal only from the complete state. |

## URL grammar

The scheme is closed — these six hosts are all of it.

```
cadence://start
cadence://start?minutes=<1…999>
cadence://start?seconds=<1…59999>
cadence://pause
cadence://resume
cadence://reset
cadence://extend
```

`minutes` and `seconds` are positive integers; `minutes` wins if both are
present. This extension only ever sends `minutes`.

Illegal transitions — pausing an idle timer, extending a running one — are
**silent no-ops**. Cadence guards each transition and the URL handler never
returns an error, so the extension does not need to track app state and never
reports a failure that came from the app. The one error a command can show is
"Cadence is not installed", which is `open` failing to find a handler for the
scheme.

Duration input is validated in the extension rather than deferred to the app:
a bad value would be discarded silently, and the user would otherwise see a
success HUD for a timer that never started.

## How it works

Commands shell out to `open -g "<url>"` via `child_process.execFile`, not
Raycast's `open()` helper. Two reasons:

- **`-g` (background)** keeps focus where it is. Raycast's helper cannot pass
  the flag, so it would yank Cadence to the front every time you paused a
  timer. `open` still launches Cadence if it is quit, so the commands work
  from cold.
- **`execFile`, not `exec`** means no shell sits in the middle. The URL is one
  argv element, so quoting and metacharacters cannot matter. Argument values
  additionally go through `encodeURIComponent` on the way into the URL.

The shared logic lives in [`src/cadence.ts`](src/cadence.ts) (URL building,
argument parsing, background open, HUD); the six command files are a few lines
each.

## Run it locally

Cadence must be built and installed — that is what registers the `cadence://`
scheme with LaunchServices.

```bash
cd raycast/cadence
npm install
npm run dev
```

`npm run dev` starts Raycast in development mode and imports the extension.
Stop with `Ctrl+C`; the commands stay available until you remove the extension
from Raycast's dev extensions.

> The `command-icon.png` here is a 1×1 placeholder. Replace it with a 512×512
> PNG before publishing to the Raycast Store.
