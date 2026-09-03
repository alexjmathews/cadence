import { LaunchProps, showHUD, closeMainWindow } from "@raycast/api";
import {
  MAX_MINUTES,
  MIN_MINUTES,
  parseMinutesArgument,
  runCadenceAction,
} from "./cadence";

/**
 * `Start Session` with an explicit duration.
 *
 * The minutes argument is optional on purpose: leaving it blank falls through
 * to plain `cadence://start`, which reuses the stored plan, so this single
 * command covers both "45 minutes" and "same as last time". Out-of-range or
 * non-integer input is rejected here rather than sent to the app, because the
 * app's guard would discard it silently and the user would see a success HUD
 * for a timer that never started.
 */
export default async function Command(
  props: LaunchProps<{ arguments: { minutes: string } }>,
) {
  const parsed = parseMinutesArgument(props.arguments?.minutes);

  if (parsed.kind === "invalid") {
    await closeMainWindow();
    await showHUD(
      `Enter a whole number of minutes (${MIN_MINUTES}–${MAX_MINUTES})`,
    );
    return;
  }

  if (parsed.kind === "storedPlan") {
    await runCadenceAction("start", { hud: "Cadence started" });
    return;
  }

  await runCadenceAction("start", {
    hud: `Cadence started for ${parsed.minutes} min`,
    params: { minutes: parsed.minutes },
  });
}
