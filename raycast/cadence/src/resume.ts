import { runCadenceAction } from "./cadence";

/** No-ops in the app unless a session is actually paused. */
export default async function Command() {
  await runCadenceAction("resume", { hud: "Cadence resumed" });
}
