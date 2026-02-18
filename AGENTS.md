# Crabterm - Agent Guide

## What is Crabterm?

An iTerm2-native workspace manager for multi-repo development on macOS. Fork of [crabcode](https://github.com/promptfoo/crabcode) with tmux replaced by iTerm2 AppleScript and the monolithic script split into modular files.

Each workspace is a **git worktree** with its own branch. Opening a workspace creates an iTerm2 window/tab with 3 panes (terminal, server, main) and runs configured commands in each.

## Architecture

### Source Layout

```
src/
  crabterm                # Entry point: sources all libs, main() case router
  lib/
    common.sh             # Colors, VERSION, CONFIG_DIR, error/warn/info/success, command_exists
    config.sh             # config_get, config_exists, validate_config, load_config, sync_mcp_servers
    projects.sh           # Multi-project resolution, show_projects, handle_alias_command
    iterm.sh              # iTerm2 AppleScript abstraction layer (16 functions)
    state.sh              # Workspace pane state persistence (JSON files)
    ports.sh              # Port management, env file syncing
    worktree.sh           # Git worktree creation, submodules, shared volume
    workspace.sh          # Core workspace operations (open, create, cleanup, restart, etc.)
    wip.sh                # WIP save/restore with git patches
    session.sh            # Named session management for Claude Code
    review.sh             # PR review and court (multi-agent) review
    ticket.sh             # Linear ticket workspace creation
    doctor.sh             # Diagnostic checks
    init.sh               # Project registration, templates, config scan
    help.sh               # Help text and cheat sheet
```

### Key Directories

| Path | Purpose |
|------|---------|
| `~/.crabterm/` | Config directory (CONFIG_DIR) |
| `~/.crabterm/projects/<alias>.yaml` | Per-project config files |
| `~/.crabterm/config.yaml` | Global config (default_project, aliases) |
| `~/.crabterm/state/<session>/*.json` | iTerm2 session ID state files |
| `~/.crabterm/sessions/<project>/` | Named Claude sessions |
| `~/.crabterm/wip/<prefix>-<N>/` | Saved WIP states (patches, metadata) |
| `~/.crabterm/shared/` | Shared volume (symlinked into workspaces) |

### Data Flow

```
main() → resolve project (@alias or cwd detection)
       → resolve command aliases
       → case router → load_config → validate_config → handler function
```

For workspace operations:
```
open_workspace → state_workspace_exists? → iterm_focus_tab (existing)
                                         → create_workspace_layout (new)
                                           → create_workspace (git worktree)
                                           → iterm_create_window/tab
                                           → iterm_split_vertical/horizontal
                                           → iterm_send_text (run commands)
                                           → state_save_workspace (persist IDs)
```

## Tech Stack

- **Bash** - Pure bash, no compiled dependencies
- **iTerm2 AppleScript** (`osascript`) - Window/pane management
- **yq** - YAML config parsing
- **jq** - JSON state file parsing
- **git** - Worktrees, submodules, patches

## Key Concepts

### iTerm2 Abstraction (`iterm.sh`)

All iTerm2 interaction goes through `iterm_*` functions. Never call `osascript` directly outside this file. Key functions:

| Function | Returns | Purpose |
|----------|---------|---------|
| `iterm_create_window <name> <dir>` | `window_id:tab_id:session_id` | New window with named tab |
| `iterm_create_tab <name> <dir>` | `tab_id:session_id` | New tab in current window |
| `iterm_split_vertical <session_id>` | `new_session_id` | Split pane right |
| `iterm_split_horizontal <session_id>` | `new_session_id` | Split pane below |
| `iterm_send_text <session_id> <text>` | - | Send command to pane |
| `iterm_send_interrupt <session_id>` | - | Send Ctrl-C to pane |
| `iterm_focus_tab <tab_name>` | - | Activate + select tab by name |
| `iterm_session_exists <session_id>` | bool | Check if session is alive |

### State Persistence (`state.sh`)

iTerm2 has no built-in session tracking like tmux. State files at `~/.crabterm/state/<session_name>/ws<N>.json` store:

```json
{
  "workspace": 1,
  "window_id": "...",
  "tab_id": "...",
  "panes": {
    "terminal": "<session_id>",
    "server": "<session_id>",
    "main": "<session_id>"
  },
  "created_at": "..."
}
```

`state_workspace_exists()` checks both the file AND validates the session is alive (auto-cleans stale state).

### Config Loading (`config.sh`)

Config is lazily loaded via `load_config()`. Key globals set:

- `SESSION_NAME`, `WORKSPACE_BASE`, `MAIN_REPO`, `CONFIG_FILE`
- `WORKSPACE_PREFIX`, `WORKSPACE_COUNT`, `BRANCH_PATTERN`
- `API_PORT_BASE`, `APP_PORT_BASE`
- `SHARED_VOLUME_ENABLED`, `SHARED_VOLUME_PATH`, `SHARED_VOLUME_LINK`
- `WIP_BASE`

### Multi-Project (`projects.sh`)

Projects are identified by alias (e.g., `@pf`). Resolution order:
1. Explicit `@alias` argument
2. Detect from current working directory (`resolve_project_from_cwd`)
3. Fall back to default project in global config

### Port Management (`ports.sh`)

Ports are auto-incremented per workspace: `base_port + (workspace_num * port_spacing)`. The `sync_env_files()` function handles:
- Copying `.env` from templates
- Incrementing port variables (`ports:` list)
- Rewriting URL variables that reference ports (`refs:` map)

## Development

### Prerequisites

- macOS with iTerm2
- `brew install yq jq git`

### Running

```bash
# Direct execution
./src/crabterm --version
./src/crabterm doctor
./src/crabterm cheat

# With a configured project
./src/crabterm init          # Register a project
./src/crabterm ws 1          # Open workspace 1
```

### Testing

```bash
make test                    # Run unit tests
make lint                    # Run shellcheck
```

### Adding a New Command

1. Create handler function in the appropriate `src/lib/*.sh` file
2. Add case to `main()` in `src/crabterm`
3. If it needs config, add to the project-aware commands case list
4. Update `show_help()` and `show_cheat()` in `src/lib/help.sh`
5. Add tests to `tests/run.sh`

### Adding an iTerm2 Operation

Add wrapper function to `src/lib/iterm.sh` following the existing pattern:
- Use `osascript -e` with AppleScript
- Iterate windows → tabs → sessions to find targets by ID
- Return IDs as colon-separated strings
- Redirect stderr to `/dev/null`

## Conventions

- **Pure bash** - No Python, Node, or compiled tools in the core
- **macOS only** - iTerm2 is macOS-only; use `sed -i ''` (BSD sed), not `sed -i` (GNU)
- **No tmux** - All terminal multiplexing via iTerm2 AppleScript
- **Modular files** - Each file handles one domain; source order matters (see entry point)
- **Color output** - Use `$RED`, `$GREEN`, `$YELLOW`, `$CYAN`, `$NC` from `common.sh`
- **Error handling** - Use `error "msg"` / `warn "msg"` / `success "msg"` helpers
- **Config access** - Always use `config_get "key" "default"` or `yq` directly on `$CONFIG_FILE`
- **State files** - JSON via `jq`; config files via `yq` on YAML
- **Exit codes** - `exit 1` for fatal errors; `return 1` for recoverable failures
- **Naming** - Functions use `snake_case`; private helpers prefixed with `_` (e.g., `_restore_wip`)

## Features Removed from Crabcode

These were intentionally removed in the fork and should not be re-added:
- Toolkit/share (`tk share`)
- Slack integration
- Mood system
- Mobile companion / push notifications
- Handoff system
- Snapshots / rewind / time travel
- Live pairing (tmate)
- Promptfoo plugin (`pf`)

## Verification Checklist

After changes, verify:
- [ ] `crab --version` shows version
- [ ] `crab --help` shows help text
- [ ] `crab cheat` shows cheat sheet
- [ ] `crab doctor` runs diagnostics
- [ ] `crab config` works (with and without config)
- [ ] `make test` passes
- [ ] No `crabcode` references in source (only in README attribution)
- [ ] No `tmux` calls in source (only comment in iterm.sh)
