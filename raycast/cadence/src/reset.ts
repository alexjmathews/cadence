import { runCadenceAction } from "./cadence";

/** Returns Cadence to idle from any state. */
export default async function Command() {
  await runCadenceAction("reset", { hud: "Cadence reset" });
}
