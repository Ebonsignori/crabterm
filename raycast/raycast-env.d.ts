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
  /** Preferences accessible in the `list-workspaces` command */
  export type ListWorkspaces = ExtensionPreferences & {}
  /** Preferences accessible in the `new-workspace` command */
  export type NewWorkspace = ExtensionPreferences & {}
  /** Preferences accessible in the `switch-project` command */
  export type SwitchProject = ExtensionPreferences & {}
  /** Preferences accessible in the `quick-actions` command */
  export type QuickActions = ExtensionPreferences & {}
}

declare namespace Arguments {
  /** Arguments passed to the `list-workspaces` command */
  export type ListWorkspaces = {}
  /** Arguments passed to the `new-workspace` command */
  export type NewWorkspace = {}
  /** Arguments passed to the `switch-project` command */
  export type SwitchProject = {}
  /** Arguments passed to the `quick-actions` command */
  export type QuickActions = {}
}

