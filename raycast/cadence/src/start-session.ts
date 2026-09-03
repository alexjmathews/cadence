import { runCadenceAction } from "./cadence";

/** Bare `cadence://start` — Cadence uses whatever duration the user last chose. */
export default async function Command() {
  await runCadenceAction("start", { hud: "Cadence started" });
}
