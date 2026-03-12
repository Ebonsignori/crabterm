import { List, ActionPanel, Action, Icon, Color, showToast, Toast } from "@raycast/api";
import { useCachedPromise } from "@raycast/utils";
import { discoverProjects, loadGlobalConfig } from "./lib/config";
import { discoverWorkspaces } from "./lib/crabterm";
import { runCrabAsync } from "./lib/exec";
import { getActiveSessions } from "./lib/iterm";

function loadData() {
  const projects = discoverProjects();
  const globalConfig = loadGlobalConfig();
  const activeSessions = getActiveSessions();

  return projects.map((project) => {
    const workspaces = discoverWorkspaces(project, activeSessions);
    const activeCount = workspaces.filter((w) => w.active).length;
    const totalCount = workspaces.length;
    return {
      project,
      activeCount,
      totalCount,
      isDefault: globalConfig.default_project === project.alias,
    };
  });
}

export default function SwitchProject() {
  const { data, isLoading, revalidate } = useCachedPromise(async () => loadData(), [], {
    keepPreviousData: true,
  });

  const items = data ?? [];

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Filter projects...">
      {items.length === 0 && !isLoading && (
        <List.EmptyView
          title="No Projects Found"
          description="Run `crab init` to register a project."
          icon={Icon.Plus}
        />
      )}
      {items.map(({ project, activeCount, totalCount, isDefault }) => (
        <List.Item
          key={project.alias}
          title={`@${project.alias}`}
          subtitle={project.main_repo}
          icon={isDefault ? { source: Icon.Star, tintColor: Color.Yellow } : Icon.Folder}
          accessories={[
            {
              text: `${activeCount}/${totalCount} active`,
              tooltip: `${activeCount} active of ${totalCount} workspaces`,
            },
            ...(isDefault ? [{ tag: { value: "default", color: Color.Green } }] : []),
          ]}
          actions={
            <ActionPanel>
              <Action
                title="Open Main Repo"
                icon={Icon.Terminal}
                onAction={async () => {
                  await showToast({ style: Toast.Style.Animated, title: "Opening main..." });
                  try {
                    await runCrabAsync(`@${project.alias} main`);
                    await showToast({ style: Toast.Style.Success, title: "Opened" });
                  } catch (e) {
                    await showToast({
                      style: Toast.Style.Failure,
                      title: "Failed",
                      message: String(e),
                    });
                  }
                }}
              />
              {!isDefault && (
                <Action
                  title="Set as Default"
                  icon={Icon.Star}
                  shortcut={{ modifiers: ["cmd"], key: "d" }}
                  onAction={async () => {
                    try {
                      await runCrabAsync(`default ${project.alias}`);
                      await showToast({
                        style: Toast.Style.Success,
                        title: `Default set to @${project.alias}`,
                      });
                      revalidate();
                    } catch (e) {
                      await showToast({
                        style: Toast.Style.Failure,
                        title: "Failed",
                        message: String(e),
                      });
                    }
                  }}
                />
              )}
              <Action.CopyToClipboard
                title="Copy Repo Path"
                content={project.main_repo}
                shortcut={{ modifiers: ["cmd"], key: "c" }}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
