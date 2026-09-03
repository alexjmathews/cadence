import { runCadenceAction } from "./cadence";

/** No-ops in the app unless a session is actually running. */
export default async function Command() {
  await runCadenceAction("pause", { hud: "Cadence paused" });
}
