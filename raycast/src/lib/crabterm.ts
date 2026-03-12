import { existsSync } from "fs";
import { join } from "path";
import type { CrabtermProject, CrabtermWorkspace } from "./types";
import {
  discoverProjects,
  loadWorkspaceState,
  loadWorkspaceMeta,
  isWorkspaceLocked,
  getCustomName,
} from "./config";
import { getGitBranch } from "./exec";
import { getActiveSessions } from "./iterm";

export function getWorkspaceDir(project: CrabtermProject, num: number): string {
  return join(project.workspace_base, `${project.workspaces.prefix}-${num}`);
}

export function discoverWorkspaces(project: CrabtermProject, activeSessions?: Set<string>): CrabtermWorkspace[] {
  const workspaces: CrabtermWorkspace[] = [];

  for (let i = 1; i <= project.workspaces.count; i++) {
    const dir = getWorkspaceDir(project, i);
    if (!existsSync(dir)) continue;

    const state = loadWorkspaceState(project.session_name, i);
    const meta = loadWorkspaceMeta(dir);
    const locked = isWorkspaceLocked(dir);
    const customName = getCustomName(dir);
    const branch = getGitBranch(dir);

    let active = false;
    if (state && activeSessions) {
      const mainSid = state.panes.main;
      active = mainSid ? activeSessions.has(mainSid) : false;
    }

    workspaces.push({
      project,
      number: i,
      directory: dir,
      branch,
      locked,
      active,
      meta,
      state,
      customName,
    });
  }

  return workspaces;
}

export function getAllWorkspaces(): { projects: CrabtermProject[]; workspaces: CrabtermWorkspace[] } {
  const projects = discoverProjects();
  const activeSessions = getActiveSessions();
  const workspaces: CrabtermWorkspace[] = [];

  for (const project of projects) {
    workspaces.push(...discoverWorkspaces(project, activeSessions));
  }

  return { projects, workspaces };
}

export function getWorkspaceTitle(ws: CrabtermWorkspace): string {
  if (ws.meta?.pr_title) {
    const name = ws.customName || `ws${ws.number}`;
    return `${name}: ${ws.meta.pr_title}`;
  }
  if (ws.meta?.ticket) {
    const name = ws.customName || `ws${ws.number}`;
    return `${name} (${ws.meta.ticket})`;
  }
  if (ws.customName) return ws.customName;
  return `${ws.project.workspaces.prefix}-${ws.number}`;
}

export function getWorkspaceSubtitle(ws: CrabtermWorkspace): string {
  const parts: string[] = [];
  if (ws.branch && ws.branch !== "unknown") parts.push(ws.branch);
  if (ws.meta?.type && ws.meta.type !== "workspace") parts.push(ws.meta.type.toUpperCase());
  return parts.join(" | ");
}
