export interface CrabtermProject {
  alias: string;
  session_name: string;
  workspace_base: string;
  main_repo: string;
  workspaces: {
    count: number;
    prefix: string;
    branch_pattern: string;
  };
  ports?: {
    api_base?: number;
    app_base?: number;
  };
  layout?: {
    panes?: Array<{ name: string; command: string }>;
  };
}

export interface WorkspaceMeta {
  type?: "workspace" | "ticket" | "pr";
  name?: string;
  ticket?: string;
  ticket_url?: string;
  pr_number?: string;
  pr_title?: string;
  pr_url?: string;
  links?: Array<{ label: string; url: string }>;
}

export interface WorkspaceState {
  workspace: number | string;
  window_id: string;
  tab_id: string;
  panes: {
    terminal: string;
    server: string;
    main: string;
    info?: string;
  };
  created_at: string;
}

export interface CrabtermWorkspace {
  project: CrabtermProject;
  number: number;
  directory: string;
  branch: string;
  locked: boolean;
  active: boolean;
  meta?: WorkspaceMeta;
  state?: WorkspaceState;
  customName?: string;
}

export interface GlobalConfig {
  default_project?: string;
  aliases?: Record<string, string>;
}
