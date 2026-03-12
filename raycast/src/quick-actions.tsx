import { List, ActionPanel, Action, Icon, showToast, Toast } from "@raycast/api";
import { runCrabAsync } from "./lib/exec";

interface QuickAction {
  title: string;
  description: string;
  icon: Icon;
  command: string;
}

const actions: QuickAction[] = [
  {
    title: "Unlock All Workspaces",
    description: "Unlock all non-active workspaces across projects",
    icon: Icon.LockUnlocked,
    command: "unlock-all",
  },
  {
    title: "Doctor",
    description: "Diagnose crabterm configuration issues",
    icon: Icon.Stethoscope,
    command: "doctor",
  },
  {
    title: "Show Ports",
    description: "Show port usage across workspaces",
    icon: Icon.Network,
    command: "ports",
  },
  {
    title: "Kill All Ports",
    description: "Kill managed port processes in current workspace",
    icon: Icon.XMarkCircle,
    command: "kill",
  },
];

export default function QuickActions() {
  return (
    <List searchBarPlaceholder="Filter actions...">
      {actions.map((action) => (
        <List.Item
          key={action.command}
          title={action.title}
          subtitle={action.description}
          icon={action.icon}
          actions={
            <ActionPanel>
              <Action
                title={`Run ${action.title}`}
                icon={Icon.Play}
                onAction={async () => {
                  await showToast({ style: Toast.Style.Animated, title: `Running ${action.title}...` });
                  try {
                    const output = await runCrabAsync(action.command);
                    await showToast({
                      style: Toast.Style.Success,
                      title: action.title,
                      message: output.slice(0, 200) || "Done",
                    });
                  } catch (e) {
                    await showToast({
                      style: Toast.Style.Failure,
                      title: `${action.title} failed`,
                      message: String(e),
                    });
                  }
                }}
              />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
