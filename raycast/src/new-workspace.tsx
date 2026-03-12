import { Form, ActionPanel, Action, showToast, Toast, popToRoot } from "@raycast/api";
import { useState } from "react";
import { discoverProjects } from "./lib/config";
import { runCrabAsync } from "./lib/exec";

export default function NewWorkspace() {
  const projects = discoverProjects();
  const [isSubmitting, setIsSubmitting] = useState(false);

  if (projects.length === 0) {
    return (
      <Form>
        <Form.Description text="No projects found. Run `crab init` to register a project." />
      </Form>
    );
  }

  return (
    <Form
      isLoading={isSubmitting}
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Create Workspace"
            onSubmit={async (values: { project: string; number: string; ticket: string }) => {
              setIsSubmitting(true);
              try {
                let cmd: string;
                if (values.ticket) {
                  cmd = `@${values.project} ticket ${values.ticket}`;
                } else if (values.number) {
                  cmd = `@${values.project} ws ${values.number}`;
                } else {
                  cmd = `@${values.project} ws new`;
                }

                await showToast({ style: Toast.Style.Animated, title: "Creating workspace..." });
                await runCrabAsync(cmd);
                await showToast({ style: Toast.Style.Success, title: "Workspace created" });
                popToRoot();
              } catch (e) {
                await showToast({
                  style: Toast.Style.Failure,
                  title: "Failed to create workspace",
                  message: String(e),
                });
              } finally {
                setIsSubmitting(false);
              }
            }}
          />
        </ActionPanel>
      }
    >
      <Form.Dropdown id="project" title="Project" defaultValue={projects[0]?.alias}>
        {projects.map((p) => (
          <Form.Dropdown.Item key={p.alias} value={p.alias} title={`@${p.alias}`} />
        ))}
      </Form.Dropdown>
      <Form.TextField
        id="number"
        title="Workspace Number"
        placeholder="Auto-detect next free"
        info="Leave blank to automatically use the next available workspace."
      />
      <Form.TextField
        id="ticket"
        title="Ticket ID or URL"
        placeholder="PROJ-123 or https://linear.app/..."
        info="If provided, creates a ticket workspace instead. Overrides workspace number."
      />
    </Form>
  );
}
