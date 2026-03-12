import {
  List,
  ActionPanel,
  Action,
  Icon,
  Color,
  Clipboard,
  showToast,
  Toast,
  confirmAlert,
  Alert,
} from "@raycast/api";
import { useCachedPromise } from "@raycast/utils";
import { getAllWorkspaces, getWorkspaceTitle, getWorkspaceSubtitle } from "./lib/crabterm";
import { crabtermExists } from "./lib/config";
import { focusSession } from "./lib/iterm";
import { runCrabAsync } from "./lib/exec";
import type { CrabtermWorkspace } from "./lib/types";
import { existsSync, unlinkSync, writeFileSync } from "fs";
import { join } from "path";

export default function ListWorkspaces() {
  if (!crabtermExists()) {
    return (
      <List>
        <List.EmptyView
          title="Crabterm Not Configured"
          description="Run `crab init` in your terminal to set up crabterm."
          icon={Icon.Warning}
        />
      </List>
    );
  }

  const { data, isLoading, revalidate } = useCachedPromise(async () => getAllWorkspaces(), [], {
    keepPreviousData: true,
  });

  const workspaces = data?.workspaces ?? [];
  const projects = data?.projects ?? [];

  // Group by project
  const grouped = new Map<string, CrabtermWorkspace[]>();
  for (const ws of workspaces) {
    const key = ws.project.alias;
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key)!.push(ws);
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Filter workspaces...">
      {projects.length === 0 && !isLoading && (
        <List.EmptyView
          title="No Projects Found"
          description="Run `crab init` to register a project."
          icon={Icon.Plus}
        />
      )}
      {workspaces.length === 0 && projects.length > 0 && !isLoading && (
        <List.EmptyView
          title="No Workspaces Found"
          description="Open a workspace with `crab ws <N>` or use New Workspace."
          icon={Icon.Desktop}
        />
      )}
      {Array.from(grouped.entries()).map(([alias, wsList]) => (
        <List.Section key={alias} title={`@${alias}`} subtitle={`${wsList.length} workspace(s)`}>
          {wsList.map((ws) => (
            <WorkspaceItem key={`${alias}-${ws.number}`} ws={ws} revalidate={revalidate} />
          ))}
        </List.Section>
      ))}
    </List>
  );
}

function WorkspaceItem({ ws, revalidate }: { ws: CrabtermWorkspace; revalidate: () => void }) {
  const title = getWorkspaceTitle(ws);
  const subtitle = getWorkspaceSubtitle(ws);

  const accessories: List.Item.Accessory[] = [];
  if (ws.active) {
    accessories.push({ icon: { source: Icon.Circle, tintColor: Color.Green }, tooltip: "Active" });
  }
  if (ws.locked) {
    accessories.push({ icon: { source: Icon.Lock, tintColor: Color.Orange }, tooltip: "Locked" });
  }
  if (ws.meta?.type === "pr") {
    accessories.push({ tag: { value: `PR`, color: Color.Purple } });
  } else if (ws.meta?.type === "ticket") {
    accessories.push({ tag: { value: ws.meta.ticket || "ticket", color: Color.Blue } });
  }

  const icon = ws.active
    ? { source: Icon.Terminal, tintColor: Color.Green }
    : { source: Icon.Terminal, tintColor: Color.SecondaryText };

  return (
    <List.Item
      title={title}
      subtitle={subtitle}
      icon={icon}
      accessories={accessories}
      actions={
        <ActionPanel>
          <ActionPanel.Section>
            {ws.active && ws.state?.panes.terminal && (
              <Action
                title="Focus Workspace"
                icon={Icon.Eye}
                onAction={() => {
                  focusSession(ws.state!.panes.terminal);
                }}
              />
            )}
            <Action
              title="Open Workspace"
              icon={Icon.Play}
              shortcut={{ modifiers: ["cmd"], key: "o" }}
              onAction={async () => {
                await showToast({ style: Toast.Style.Animated, title: "Opening workspace..." });
                try {
                  await runCrabAsync(`@${ws.project.alias} ws ${ws.number}`);
                  await showToast({ style: Toast.Style.Success, title: "Workspace opened" });
                  revalidate();
                } catch (e) {
                  await showToast({
                    style: Toast.Style.Failure,
                    title: "Failed to open",
                    message: String(e),
                  });
                }
              }}
            />
          </ActionPanel.Section>
          <ActionPanel.Section>
            <Action
              title={ws.locked ? "Unlock Workspace" : "Lock Workspace"}
              icon={ws.locked ? Icon.LockUnlocked : Icon.Lock}
              shortcut={{ modifiers: ["cmd"], key: "l" }}
              onAction={() => {
                const lockFile = join(ws.directory, ".crabterm-lock");
                if (ws.locked) {
                  try {
                    unlinkSync(lockFile);
                  } catch {
                    /* already unlocked */
                  }
                } else {
                  writeFileSync(lockFile, "");
                }
                showToast({
                  style: Toast.Style.Success,
                  title: ws.locked ? "Unlocked" : "Locked",
                });
                revalidate();
              }}
            />
            <Action
              title="Copy Branch Name"
              icon={Icon.Clipboard}
              shortcut={{ modifiers: ["cmd"], key: "b" }}
              onAction={async () => {
                await Clipboard.copy(ws.branch);
                await showToast({ style: Toast.Style.Success, title: "Branch copied" });
              }}
            />
          </ActionPanel.Section>
          <ActionPanel.Section>
            <Action
              title="Cleanup Workspace"
              icon={Icon.Trash}
              style={Action.Style.Destructive}
              shortcut={{ modifiers: ["cmd", "shift"], key: "c" }}
              onAction={async () => {
                if (
                  await confirmAlert({
                    title: "Cleanup Workspace?",
                    message: `This will close the window and reset @${ws.project.alias} ws${ws.number} to origin/main.`,
                    primaryAction: { title: "Cleanup", style: Alert.ActionStyle.Destructive },
                  })
                ) {
                  await showToast({ style: Toast.Style.Animated, title: "Cleaning up..." });
                  try {
                    await runCrabAsync(`@${ws.project.alias} ws ${ws.number} cleanup`);
                    await showToast({ style: Toast.Style.Success, title: "Cleaned up" });
                    revalidate();
                  } catch (e) {
                    await showToast({
                      style: Toast.Style.Failure,
                      title: "Cleanup failed",
                      message: String(e),
                    });
                  }
                }
              }}
            />
            <Action
              title="Destroy Workspace"
              icon={Icon.XMarkCircle}
              style={Action.Style.Destructive}
              shortcut={{ modifiers: ["cmd", "shift"], key: "d" }}
              onAction={async () => {
                if (
                  await confirmAlert({
                    title: "Destroy Workspace?",
                    message: `This will permanently remove @${ws.project.alias} ws${ws.number} and its git worktree. This cannot be undone.`,
                    primaryAction: { title: "Destroy", style: Alert.ActionStyle.Destructive },
                  })
                ) {
                  await showToast({ style: Toast.Style.Animated, title: "Destroying..." });
                  try {
                    await runCrabAsync(`@${ws.project.alias} ws ${ws.number} destroy`);
                    await showToast({ style: Toast.Style.Success, title: "Destroyed" });
                    revalidate();
                  } catch (e) {
                    await showToast({
                      style: Toast.Style.Failure,
                      title: "Destroy failed",
                      message: String(e),
                    });
                  }
                }
              }}
            />
          </ActionPanel.Section>
        </ActionPanel>
      }
    />
  );
}
