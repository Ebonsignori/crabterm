import { readFileSync, existsSync, readdirSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import * as yaml from "js-yaml";
import type { CrabtermProject, GlobalConfig, WorkspaceMeta, WorkspaceState } from "./types";

const CRABTERM_DIR = join(homedir(), ".crabterm");
const PROJECTS_DIR = join(CRABTERM_DIR, "projects");
const STATE_DIR = join(CRABTERM_DIR, "state");
const GLOBAL_CONFIG = join(CRABTERM_DIR, "config.yaml");

export function getCrabtermDir(): string {
  return CRABTERM_DIR;
}

export function crabtermExists(): boolean {
  return existsSync(CRABTERM_DIR);
}

function expandPath(p: string): string {
  if (p.startsWith("~/") || p === "~") {
    return join(homedir(), p.slice(2));
  }
  return p;
}

export function loadGlobalConfig(): GlobalConfig {
  if (!existsSync(GLOBAL_CONFIG)) return {};
  try {
    const raw = readFileSync(GLOBAL_CONFIG, "utf-8");
    return (yaml.load(raw) as GlobalConfig) || {};
  } catch {
    return {};
  }
}

export function loadProject(alias: string, filePath: string): CrabtermProject {
  const raw = readFileSync(filePath, "utf-8");
  const doc = yaml.load(raw) as Record<string, unknown>;

  const workspaces = (doc.workspaces as Record<string, unknown>) || {};
  const ports = (doc.ports as Record<string, unknown>) || {};

  return {
    alias,
    session_name: (doc.session_name as string) || alias,
    workspace_base: expandPath((doc.workspace_base as string) || ""),
    main_repo: expandPath((doc.main_repo as string) || ""),
    workspaces: {
      count: (workspaces.count as number) || 5,
      prefix: (workspaces.prefix as string) || "workspace",
      branch_pattern: (workspaces.branch_pattern as string) || "workspace-{N}",
    },
    ports: ports
      ? {
          api_base: ports.api_base as number | undefined,
          app_base: ports.app_base as number | undefined,
        }
      : undefined,
    layout: doc.layout as CrabtermProject["layout"],
  };
}

export function discoverProjects(): CrabtermProject[] {
  if (!existsSync(PROJECTS_DIR)) return [];
  const files = readdirSync(PROJECTS_DIR).filter((f) => f.endsWith(".yaml") || f.endsWith(".yml"));
  const projects: CrabtermProject[] = [];
  for (const file of files) {
    const alias = file.replace(/\.ya?ml$/, "");
    try {
      projects.push(loadProject(alias, join(PROJECTS_DIR, file)));
    } catch {
      // skip invalid configs
    }
  }
  return projects;
}

export function loadWorkspaceState(sessionName: string, num: number): WorkspaceState | undefined {
  const stateFile = join(STATE_DIR, sessionName, `ws${num}.json`);
  if (!existsSync(stateFile)) return undefined;
  try {
    return JSON.parse(readFileSync(stateFile, "utf-8")) as WorkspaceState;
  } catch {
    return undefined;
  }
}

export function loadWorkspaceMeta(workspaceDir: string): WorkspaceMeta | undefined {
  const metaFile = join(workspaceDir, ".crabterm-meta");
  if (!existsSync(metaFile)) return undefined;
  try {
    return JSON.parse(readFileSync(metaFile, "utf-8")) as WorkspaceMeta;
  } catch {
    return undefined;
  }
}

export function isWorkspaceLocked(workspaceDir: string): boolean {
  return existsSync(join(workspaceDir, ".crabterm-lock"));
}

export function getCustomName(workspaceDir: string): string | undefined {
  const nameFile = join(workspaceDir, ".crabterm-name");
  if (!existsSync(nameFile)) return undefined;
  try {
    return readFileSync(nameFile, "utf-8").trim() || undefined;
  } catch {
    return undefined;
  }
}
