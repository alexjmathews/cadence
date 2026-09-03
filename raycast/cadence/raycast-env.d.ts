/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `start-session` command */
  export type StartSession = ExtensionPreferences & {}
  /** Preferences accessible in the `start-timer` command */
  export type StartTimer = ExtensionPreferences & {}
  /** Preferences accessible in the `pause` command */
  export type Pause = ExtensionPreferences & {}
  /** Preferences accessible in the `resume` command */
  export type Resume = ExtensionPreferences & {}
  /** Preferences accessible in the `reset` command */
  export type Reset = ExtensionPreferences & {}
  /** Preferences accessible in the `extend` command */
  export type Extend = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `start-session` command */
  export type StartSession = {}
  /** Arguments passed to the `start-timer` command */
  export type StartTimer = {
  /** minutes */
  "minutes": string
}
  /** Arguments passed to the `pause` command */
  export type Pause = {}
  /** Arguments passed to the `resume` command */
  export type Resume = {}
  /** Arguments passed to the `reset` command */
  export type Reset = {}
  /** Arguments passed to the `extend` command */
  export type Extend = {}
}

