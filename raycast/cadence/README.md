# Cadence (Raycast extension)

A local Raycast extension that controls the [Cadence](../../) macOS app.

## Commands

- **Send Cadence Notification** — fires a local notification via Cadence's
  `cadence://notify` URL scheme. Optional `message` argument overrides the body.
  Runs silently: no Cadence window appears and focus stays where it is.

## Run it locally

Cadence must be built and installed (it registers the `cadence://` URL scheme):

```bash
cd raycast/cadence
npm install
npm run dev
```

`npm run dev` starts Raycast in development mode and imports the extension.
Open Raycast and search for **Send Cadence Notification**. Stop with `Ctrl+C`;
the command stays available until you remove it from Raycast's dev extensions.

## How it works

The command calls `open("cadence://notify?message=…")`. Cadence's AppDelegate
handles the URL and calls the same `NotificationService.send(…)` used by the
menu, the widget button (`SendNotificationIntent`), and Shortcuts/Siri.

> The `command-icon.png` here is a 1×1 placeholder. Replace it with a 512×512
> PNG before publishing to the Raycast Store.
