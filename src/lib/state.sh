#!/usr/bin/env bash
# crabterm - workspace pane state persistence
# Stores iTerm2 session IDs in JSON files so we can reconnect to panes

STATE_DIR="$CONFIG_DIR/state"

# Save workspace state (iTerm2 session IDs for a workspace)
# Usage: state_save_workspace <session_name> <num> <window_id> <tab_id> <terminal_sid> <server_sid> <main_sid> [info_sid]
state_save_workspace() {
  local session_name="$1"
  local num="$2"
  local window_id="$3"
  local tab_id="$4"
  local terminal_sid="$5"
  local server_sid="$6"
  local main_sid="$7"
  local info_sid="${8:-}"

  local state_dir="$STATE_DIR/$session_name"
  mkdir -p "$state_dir"

  local state_file="$state_dir/ws${num}.json"
  cat > "$state_file" << EOF
{
  "workspace": $num,
  "window_id": "$window_id",
  "tab_id": "$tab_id",
  "panes": {
    "terminal": "$terminal_sid",
    "server": "$server_sid",
    "main": "$main_sid",
    "info": "$info_sid"
  },
  "created_at": "$(date -Iseconds)"
}
EOF
}

# Load workspace state - sets WS_WINDOW_ID, WS_TAB_ID, WS_TERMINAL_SID, WS_SERVER_SID, WS_MAIN_SID
# Returns 0 if state exists and loaded, 1 otherwise
state_load_workspace() {
  local session_name="$1"
  local num="$2"

  local state_file="$STATE_DIR/$session_name/ws${num}.json"
  if [ ! -f "$state_file" ]; then
    return 1
  fi

  WS_WINDOW_ID=$(jq -r '.window_id' "$state_file" 2>/dev/null)
  WS_TAB_ID=$(jq -r '.tab_id' "$state_file" 2>/dev/null)
  WS_TERMINAL_SID=$(jq -r '.panes.terminal' "$state_file" 2>/dev/null)
  WS_SERVER_SID=$(jq -r '.panes.server' "$state_file" 2>/dev/null)
  WS_MAIN_SID=$(jq -r '.panes.main' "$state_file" 2>/dev/null)
  WS_INFO_SID=$(jq -r '.panes.info // ""' "$state_file" 2>/dev/null)

  return 0
}

# Remove workspace state
state_remove_workspace() {
  local session_name="$1"
  local num="$2"

  local state_file="$STATE_DIR/$session_name/ws${num}.json"
  rm -f "$state_file"
}

# Check if workspace state exists AND the main session is still alive in iTerm2
state_workspace_exists() {
  local session_name="$1"
  local num="$2"

  local state_file="$STATE_DIR/$session_name/ws${num}.json"
  if [ ! -f "$state_file" ]; then
    return 1
  fi

  local main_sid
  main_sid=$(jq -r '.panes.main' "$state_file" 2>/dev/null)
  if [ -z "$main_sid" ] || [ "$main_sid" = "null" ]; then
    return 1
  fi

  # Check if the session is still alive in iTerm2
  if iterm_session_exists "$main_sid"; then
    return 0
  else
    # Session is dead, clean up stale state
    rm -f "$state_file"
    return 1
  fi
}

# List all workspace states for a session
state_list_workspaces() {
  local session_name="$1"
  local state_dir="$STATE_DIR/$session_name"

  if [ ! -d "$state_dir" ]; then
    return
  fi

  for f in "$state_dir"/ws*.json; do
    [ -f "$f" ] || continue
    local num
    num=$(jq -r '.workspace' "$f" 2>/dev/null)
    echo "$num"
  done
}
