#!/usr/bin/env bash
# crabterm - help and cheat sheet

show_cheat() {
  cat << 'EOF'
+===============================================================================+
|                                                                               |
|      \___/                                                                    |
|     ( *_*)         CRABTERM CHEAT SHEET                                       |
|    /)🦀(\          Workspace manager for multi-repo development               |
|   <      >                                                                    |
|                    Tip: Use 'crab' as shorthand for 'crabterm'                |
|                                                                               |
+===============================================================================+
|                                                                               |
|  MULTI-PROJECT (crab @alias ...)                                             |
|  ────────────────────────────────────────────────────────────────────────     |
|  crab init              Register a new project (asks for alias)               |
|  crab init -t <tpl>     Register with template (e.g., promptfoo-cloud)        |
|  crab @pf ws 1          Open workspace 1 for project "pf"                    |
|  crab @cb config        Show config for project "cb"                          |
|  crab ws 1              Uses default project (or detects from cwd)            |
|  crab projects          List all registered projects                          |
|  crab projects rm <a>   Remove a project registration                         |
|  crab projects delete <a> Delete project + workspaces + state (double confirm)|
|  crab default pf        Set default project                                   |
|  crab default           Show current default                                  |
|                                                                               |
|  Config: ~/.crabterm/projects/<alias>.yaml                                   |
|  Auto-detect: crab figures out which project from your cwd                    |
|                                                                               |
+===============================================================================+
|                                                                               |
|  WORKSPACE COMMANDS (crab ws ...)                                             |
|  ────────────────────────────────────────────────────────────────────────     |
|  crab ws               Interactive menu (list + actions)                      |
|  crab ws ls            List workspaces (non-interactive)                      |
|  crab ws new (wn)      Create next available workspace                        |
|  crab ws <N>           Open/create workspace N                                |
|  crab ws <N> --separate   Open in new terminal window                         |
|  crab ws <N> restart   Reset git + restart panes (recreates full layout)      |
|  crab ws <N> cleanup   Kill window + reset to origin/main                     |
|  crab ws <N> destroy   Completely remove workspace (worktree + files)         |
|  crab destroy <N>      Shorthand for above                                    |
|  crab ws <N> continue  Resume with --continue flag                            |
|  crab ws <N> kill      Kill processes on managed ports                         |
|  crab ws <N> lock      Lock workspace (prevent reuse by pr/ticket)            |
|  crab ws <N> unlock    Unlock workspace (allow reuse by pr/ticket)            |
|  crab unlock-all       Unlock all non-active workspaces                      |
|                                                                               |
|  New workspaces are locked by default. Unlock when done to allow              |
|  pr/ticket commands to reuse the workspace instead of creating new ones.      |
|                                                                               |
|  INFO BAR: Workspaces include a status bar at the bottom showing             |
|  clickable links (Cmd+click): GitHub PR, ticket ID, localhost port.          |
|  Actions: [c] Cleanup [u] Lock/Unlock [p] Pull [k] Kill ports [q] Quit      |
|  The bar auto-refreshes every 60s and discovers PRs automatically.           |
|                                                                               |
|  SHORTCUTS (auto-detect workspace from cwd or iTerm2 tab)                    |
|  ────────────────────────────────────────────────────────────────────────     |
|  crab restart          Restart current workspace                              |
|  crab cleanup          Cleanup current workspace                              |
|  crab continue         Continue current workspace                             |
|  crab kill             Kill managed ports for current workspace               |
|  crab lock             Lock current workspace                                 |
|  crab unlock           Unlock current workspace                               |
|  crab unlock-all       Unlock all non-active workspaces                      |
|  crab switch           Switch between active workspaces (interactive)        |
|  crab switch <N>       Switch directly to workspace N                        |
|  crab <N>              Shorthand for: crab ws <N>                             |
|  crab <github-pr-url>  Shorthand for: crab pr <url>                          |
|  crab <linear-url>     Shorthand for: crab ticket <url>                      |
|                                                                               |
+===============================================================================+
|                                                                               |
|  SESSION COMMANDS (crab session ...)                                          |
|  ────────────────────────────────────────────────────────────────────────     |
|  crab session ls           List sessions with summaries                       |
|  crab session start "name" Start new named session                            |
|  crab session resume "name" Resume existing session                           |
|  crab session delete "name" Delete a session                                  |
|  crab session summary "name" "text"  Update session summary                   |
|                                                                               |
|  REVIEW COMMANDS (crab review ...)                                            |
|  ────────────────────────────────────────────────────────────────────────     |
|  crab review <PR>          Quick review (number, repo#num, or URL)            |
|  crab review new           Interactive mode (multiple PRs + context)          |
|  crab review ls            List review sessions                               |
|  crab review resume <PR>   Resume a review session                            |
|                                                                               |
|  PR formats: 3230, promptfoo#456, https://github.com/.../pull/123            |
|                                                                               |
+===============================================================================+
|                                                                               |
|  PR COMMANDS (crab pr ...)                                                    |
|  ────────────────────────────────────────────────────────────────────────     |
|  crab pr <PR>              Create/reopen workspace for a GitHub PR            |
|  crab ws <N> pr <PR>       Use workspace N for a PR                           |
|  crab @pf pr <PR>          PR workspace for specific project                  |
|                                                                               |
|  PR formats: 123, repo#456, https://github.com/.../pull/789                  |
|  Re-running the same PR finds and reopens the existing workspace              |
|                                                                               |
+===============================================================================+
|                                                                               |
|  TICKET COMMANDS (crab ticket ...)                                            |
|  ────────────────────────────────────────────────────────────────────────     |
|  crab ticket ENG-123       Auto-create workspace for ticket                   |
|  crab ticket <linear-url>  Create workspace from Linear URL                   |
|  crab ws 3 ticket ENG-123  Use workspace 3 for ticket                         |
|  crab @pf ticket ENG-123   Ticket for specific project                        |
|  Re-running the same ticket finds and reopens the existing workspace          |
|                                                                               |
+===============================================================================+
|                                                                               |
|  WIP COMMANDS (crab wip ...)                                                  |
|  ────────────────────────────────────────────────────────────────────────     |
|  crab wip save              Save current changes (branch, commits, patches)   |
|  crab wip save --restart    Save then restart workspace                       |
|  crab wip ls                List all WIPs globally with metadata              |
|  crab wip restore           Interactive restore from all WIPs                 |
|  crab wip restore <N>       Restore WIP #N to original workspace              |
|  crab wip restore <N> --to <ws>  Restore to different workspace               |
|  crab wip restore <N> --open     Restore and open workspace with claude       |
|  crab wip --continue        Restore most recent WIP (current workspace)       |
|  crab wip delete <name>     Delete a saved WIP state                          |
|                                                                               |
+===============================================================================+
|                                                                               |
|  COMMAND ALIASES (crab alias ...)                                            |
|  ────────────────────────────────────────────────────────────────────────     |
|  crab alias              List all aliases                                     |
|  crab alias set cu cleanup          Set alias: cu -> cleanup                  |
|  crab alias set rr "ws restart"     Multi-word: rr -> ws restart              |
|  crab alias rm cu        Remove an alias                                      |
|                                                                               |
|  Config: ~/.crabterm/config.yaml (aliases section)                           |
|                                                                               |
+===============================================================================+
|                                                                               |
|  OTHER COMMANDS                                                               |
|  ────────────────────────────────────────────────────────────────────────     |
|  crab config scan      Auto-detect .env files and ports                       |
|  crab config           Show current configuration                             |
|  crab doctor           Diagnose common issues                                 |
|  crab doctor --fix     Fix missing .env files in workspaces                   |
|  crab doctor fix --force  Re-copy all .env files from main repo              |
|  crab ports            Show port usage across workspaces                      |
|  crab shared           Show shared volume info                                |
|  crab update           Update crabterm to latest version                      |
|  crab cheat            Show this cheat sheet                                  |
|                                                                               |
+===============================================================================+
EOF
}

show_help() {
  echo '    \___/'
  echo '   ( *_*)  crabterm'
  echo '  /)🦀(\   Workspace manager for multi-repo development'
  echo ' <      >'
  echo "         v$VERSION"
  echo ""
  echo "Usage: crab [command] [arguments]"
  echo "       (crab is an alias for crabterm)"
  echo ""
  echo "Workspace Commands:"
  echo "  ws                List all workspaces"
  echo "  ws new (wn)       Create next available workspace"
  echo "  ws <N>            Open/create workspace N"
  echo "  ws <N> restart    Reset git + restart panes (recreates layout)"
  echo "  ws <N> cleanup    Kill window + reset to origin/main"
  echo "  ws <N> continue   Resume with --continue flag"
  echo "  ws <N> kill       Kill processes on managed ports"
  echo "  ws <N> lock       Lock workspace (prevent reuse)"
  echo "  ws <N> unlock     Unlock workspace (allow reuse by pr/ticket)"
  echo "  ws <N> --separate Open in new terminal window"
  echo ""
  echo ""
  echo "  Workspaces include an info bar at the bottom with clickable"
  echo "  links (PR, ticket, localhost). Auto-refreshes every 60s."
  echo ""
  echo "Shortcuts (auto-detect workspace):"
  echo "  <N>               Shorthand for: ws <N>"
  echo "  <github-pr-url>   Shorthand for: pr <url>"
  echo "  <linear-url>      Shorthand for: ticket <url>"
  echo "  restart           Restart current workspace"
  echo "  cleanup           Cleanup current workspace"
  echo "  continue          Continue current workspace"
  echo "  kill              Kill managed ports for current workspace"
  echo "  lock              Lock current workspace"
  echo "  unlock            Unlock current workspace"
  echo "  unlock-all        Unlock all non-active workspaces"
  echo "  switch            Switch between active workspaces"
  echo "  switch <N>        Switch directly to workspace N"
  echo ""
  echo "Session Commands:"
  echo "  session ls        List sessions with summaries"
  echo "  session start     Start new named session"
  echo "  session resume    Resume existing session"
  echo "  session delete    Delete a session"
  echo ""
  echo "Review Commands:"
  echo "  review <PR>       Quick review (number, repo#num, or URL)"
  echo "  review new        Interactive (multiple PRs + context)"
  echo "  review ls         List review sessions"
  echo "  review resume     Resume a review"
  echo ""
  echo "PR Commands:"
  echo "  pr <PR>           Create/reopen workspace for a GitHub PR"
  echo "  ws <N> pr <PR>    Use specific workspace for PR"
  echo "  Formats: 123, repo#456, https://github.com/.../pull/789"
  echo ""
  echo "Ticket Commands:"
  echo "  ticket <ID>       Create workspace for a Linear ticket"
  echo "  ticket <URL>      Create workspace from Linear URL"
  echo "  ws <N> ticket <ID> Use specific workspace for ticket"
  echo ""
  echo "WIP Commands:"
  echo "  wip save          Save current changes"
  echo "  wip ls            List all WIPs globally"
  echo "  wip restore       Interactive restore from all WIPs"
  echo "  wip restore <N>   Restore WIP #N"
  echo "  wip restore <N> --to <ws>  Restore to different workspace"
  echo "  wip --continue    Restore most recent WIP (current workspace)"
  echo ""
  echo "Multi-Project Commands:"
  echo "  @alias <cmd>      Run command against a specific project"
  echo "  projects          List registered projects"
  echo "  projects delete   Delete project + workspaces + state"
  echo "  default [alias]   Show/set default project"
  echo "  init              Register a new project (asks for alias)"
  echo ""
  echo "Alias Commands:"
  echo "  alias             List all aliases"
  echo "  alias set <name> <cmd>  Set a command alias"
  echo "  alias rm <name>   Remove an alias"
  echo ""
  echo "Other Commands:"
  echo "  init              Setup config (auto-detects project type)"
  echo "  init -t <name>    Setup with template (e.g., promptfoo-cloud)"
  echo "  init --list-templates  Show available templates"
  echo "  config            Show configuration"
  echo "  config scan       Auto-detect .env files and ports"
  echo "  doctor            Diagnose issues"
  echo "  doctor --fix      Fix missing .env files"
  echo "  doctor fix --force  Re-copy .env files from main repo"
  echo "  ports             Show port usage"
  echo "  shared            Show shared volume info"
  echo "  cheat             Show cheat sheet"
  echo ""
  echo "Config: $CONFIG_FILE"
}
