# crabterm 🦀

iTerm2-native workspace manager for multi-repo development. Fork of [crabcode](https://github.com/promptfoo/crabcode) with tmux replaced by native iTerm2 AppleScript.

## Why crabterm?

- **Native iTerm2** - No tmux. Full mouse support, native keyboard shortcuts, shift+enter works in Claude Code
- **Modular** - 14 focused source files instead of one monolith
- **macOS native** - Built specifically for iTerm2 on macOS

## Requirements

- **macOS** (iTerm2 is macOS only)
- **[iTerm2](https://iterm2.com)** - Terminal emulator
- **git** - Version control
- **[yq](https://github.com/mikefarah/yq)** - YAML parser (`brew install yq`)
- **[jq](https://jqlang.github.io/jq/)** - JSON parser (`brew install jq`)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/promptfoo/crabterm/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/promptfoo/crabterm.git
cd crabterm
make install
```

## Quick Start

```bash
# Register a project
crab init

# Open workspace 1 (creates iTerm2 window with 3 panes)
crab 1

# List workspaces
crab

# Restart current workspace
crab restart
```

## Commands

### Workspaces

```bash
crab ws               # Interactive menu
crab ws <N>           # Open/create workspace N
crab ws new           # Create next available workspace
crab ws <N> restart   # Reset git + recreate panes
crab ws <N> cleanup   # Close window + reset to origin/main
crab ws <N> destroy   # Remove workspace completely
crab ws <N> continue  # Resume with --continue flag
```

### Shortcuts (auto-detect workspace from cwd)

```bash
crab <N>              # Shorthand for: crab ws <N>
crab restart          # Restart current workspace
crab cleanup          # Cleanup current workspace
crab continue         # Continue current workspace
```

### WIP (Work in Progress)

```bash
crab wip save              # Save current changes (branch, commits, patches)
crab wip save --restart    # Save then restart workspace
crab wip ls                # List all WIPs globally
crab wip restore           # Interactive restore
crab wip restore <N>       # Restore WIP #N
crab wip --continue        # Restore most recent WIP
```

### Sessions

```bash
crab session ls            # List sessions
crab session start "name"  # Start new session
crab session resume "name" # Resume session
```

### Reviews

```bash
crab review <PR>           # Quick review (number, repo#num, or URL)
crab review new            # Interactive multi-PR review
crab court <PR>            # Thorough multi-agent review
```

### Tickets

```bash
crab ticket ENG-123        # Auto-create workspace for ticket
crab ws 3 ticket ENG-123   # Use specific workspace
```

### Multi-Project

```bash
crab init                  # Register a project
crab @alias ws 1           # Run command for specific project
crab projects              # List registered projects
crab default <alias>       # Set default project
```

### Other

```bash
crab config                # Show configuration
crab config scan           # Auto-detect .env files and ports
crab doctor                # Diagnose issues
crab ports                 # Show port usage
crab cheat                 # Full cheat sheet
```

## Configuration

Config files live at `~/.crabterm/projects/<alias>.yaml`:

```yaml
session_name: myproject
workspace_base: ~/Projects/myproject-workspaces
main_repo: ~/Projects/myproject

workspaces:
  prefix: ws
  branch_pattern: workspace-{N}

layout:
  panes:
    - name: terminal
      command: ""
    - name: server
      command: "npm run dev"
    - name: main
      command: "claude --dangerously-skip-permissions --chrome"

env_sync:
  port_spacing: 10
  files:
    - path: .env
      ports: [PORT]
```

## How It Works

Each workspace is a **git worktree** with its own branch. When you open a workspace, crabterm:

1. Creates the worktree (if needed)
2. Opens an iTerm2 window/tab with 3 panes (terminal, server, main)
3. Runs configured commands in each pane
4. Syncs `.env` files with unique ports per workspace

Workspace state (iTerm2 session IDs) is persisted at `~/.crabterm/state/` so crabterm can reconnect to existing panes.

## License

MIT
