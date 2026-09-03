import { showHUD, closeMainWindow } from "@raycast/api";
import { execFile } from "child_process";
import { promisify } from "util";

const execFileAsync = promisify(execFile);

/**
 * The complete `cadence://` grammar. Cadence's URL handler guards every
 * transition and silently no-ops on illegal ones (pausing an idle timer,
 * extending a running one), so the extension never needs to know the app's
 * current state — it just asks, and the app decides. That is why these
 * commands are fire-and-forget `no-view` transports rather than list or
 * detail views: there is no state to render and nothing to fail on.
 */
export type CadenceAction = "start" | "pause" | "resume" | "reset" | "extend";

/** Cadence caps a session at 999 minutes; reject out-of-range input up front
 * rather than sending a URL the app will discard. */
export const MIN_MINUTES = 1;
export const MAX_MINUTES = 999;

/**
 * Builds a `cadence://` URL. Query values go through `encodeURIComponent` so
 * that anything typed into a Raycast argument stays inert data — it can never
 * grow the URL an extra parameter or a second component.
 */
export function buildCadenceURL(
  action: CadenceAction,
  params?: Record<string, string | number>,
): string {
  const base = `cadence://${action}`;
  if (!params) {
    return base;
  }
  const query = Object.entries(params)
    .map(
      ([key, value]) =>
        `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`,
    )
    .join("&");
  return query.length > 0 ? `${base}?${query}` : base;
}

/**
 * Parses the optional minutes argument of the Start Timer command.
 *
 * Raycast hands back `""` when the user leaves an optional argument blank, and
 * that case is meaningful: it means "use the stored plan", i.e. plain
 * `cadence://start`. Anything else must be a whole number in range — `Number`
 * plus an explicit integer test rejects `"12.5"`, `"1e3"`, `"abc"` and `" "`,
 * which `parseInt` would happily coerce or truncate.
 */
export type MinutesParse =
  | { kind: "storedPlan" }
  | { kind: "minutes"; minutes: number }
  | { kind: "invalid" };

export function parseMinutesArgument(raw: string | undefined): MinutesParse {
  const trimmed = (raw ?? "").trim();
  if (trimmed.length === 0) {
    return { kind: "storedPlan" };
  }
  if (!/^\d+$/.test(trimmed)) {
    return { kind: "invalid" };
  }
  const minutes = Number(trimmed);
  if (
    !Number.isInteger(minutes) ||
    minutes < MIN_MINUTES ||
    minutes > MAX_MINUTES
  ) {
    return { kind: "invalid" };
  }
  return { kind: "minutes", minutes };
}

/**
 * Opens a `cadence://` URL without stealing focus.
 *
 * `open -g` is the entire reason this goes through `child_process` instead of
 * Raycast's `open()` helper: the helper has no way to pass `-g`, so it would
 * pull Cadence to the front every time you paused a timer. `open` also
 * launches Cadence if it is not running, so the commands work from a cold
 * start.
 *
 * `execFile` (not `exec`) means there is no shell in the middle: the URL is
 * handed to `open` as a single argv element, so quoting and metacharacters are
 * a non-issue regardless of what the user typed.
 */
export async function openCadenceURL(url: string): Promise<void> {
  await execFileAsync("open", ["-g", url]);
}

/**
 * The whole body of a transport command: fire the URL, tell the user, get out
 * of the way. The main window is closed first so the HUD is the only thing
 * left on screen.
 */
export async function runCadenceAction(
  action: CadenceAction,
  options: { hud: string; params?: Record<string, string | number> } = {
    hud: "Cadence",
  },
): Promise<void> {
  await closeMainWindow();
  try {
    await openCadenceURL(buildCadenceURL(action, options.params));
    await showHUD(options.hud);
  } catch {
    // The only realistic failure is `open` not finding a handler, which means
    // Cadence is not installed. Everything else — wrong state, unknown
    // action — is absorbed silently by the app itself.
    await showHUD("Cadence is not installed");
  }
}
