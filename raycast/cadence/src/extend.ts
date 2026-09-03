import { runCadenceAction } from "./cadence";

/** The "+5 min" action. Legal only from the complete state; the app ignores it
 * otherwise, so the HUD is phrased as a request rather than a result. */
export default async function Command() {
  await runCadenceAction("extend", { hud: "Cadence extended by 5 min" });
}
