import { showHUD, LaunchProps } from "@raycast/api";
import { execFile } from "child_process";
import { promisify } from "util";

const execFileAsync = promisify(execFile);

/**
 * No-view command: triggers a Cadence notification via the `cadence://notify`
 * URL scheme. Uses `open -g` (background) so Launch Services delivers the URL to
 * Cadence WITHOUT activating it — focus never leaves your current app and no
 * Cadence window appears. If Cadence isn't running, macOS launches it hidden.
 */
export default async function Command(
  props: LaunchProps<{ arguments: { message?: string } }>,
) {
  const message = props.arguments.message?.trim();
  const url = message
    ? `cadence://notify?message=${encodeURIComponent(message)}`
    : "cadence://notify";

  await execFileAsync("open", ["-g", url]);
  await showHUD("🔔 Sent Cadence notification");
}
