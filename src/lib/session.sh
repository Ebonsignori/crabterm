#!/usr/bin/env bash
# crabterm - session management

SESSIONS_DIR="$CONFIG_DIR/sessions"

# Get sessions directory for current project
get_sessions_dir() {
  local project="${PROJECT_ALIAS:-default}"
  echo "$SESSIONS_DIR/$project"
}

# Create a new session
session_create() {
  local name="$1"
  local context="${2:-}"
  local sessions_dir=$(get_sessions_dir)
  local session_dir="$sessions_dir/$name"

  if [ -d "$session_dir" ]; then
    error "Session '$name' already exists"
    echo "Use 'crab session resume $name' to continue it"
    return 1
  fi

  mkdir -p "$session_dir"

  cat > "$session_dir/session.yaml" << EOF
name: $name
project: ${PROJECT_ALIAS:-default}
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
last_accessed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
claude_session_id: ""
summary: ""
type: general
EOF

  if [ -n "$context" ]; then
    echo "$context" > "$session_dir/context.md"
  fi

  echo "$session_dir"
}

# Update session metadata
session_update() {
  local name="$1"
  local field="$2"
  local value="$3"
  local sessions_dir=$(get_sessions_dir)
  local session_file="$sessions_dir/$name/session.yaml"

  if [ ! -f "$session_file" ]; then
    error "Session '$name' not found"
    return 1
  fi

  yq -i ".$field = \"$value\"" "$session_file"
}

# Get session field
session_get() {
  local name="$1"
  local field="$2"
  local sessions_dir=$(get_sessions_dir)
  local session_file="$sessions_dir/$name/session.yaml"

  if [ ! -f "$session_file" ]; then
    return 1
  fi

  yq -r ".$field // \"\"" "$session_file"
}

# List all sessions with summaries
session_list() {
  local sessions_dir=$(get_sessions_dir)
  local filter="${1:-}"

  if [ ! -d "$sessions_dir" ]; then
    echo -e "${GRAY}No sessions yet.${NC}"
    echo "Start one with: crab session start \"name\""
    return
  fi

  local found=false
  local project_label=""
  [ -n "$PROJECT_ALIAS" ] && project_label="@$PROJECT_ALIAS "

  local header="Sessions"
  [[ "$filter" == "review" ]] && header="Reviews"
  echo -e "${BOLD}${project_label}${header}:${NC}"
  echo ""

  for session_dir in "$sessions_dir"/*/; do
    [ -d "$session_dir" ] || continue
    local name=$(basename "$session_dir")
    local session_file="$session_dir/session.yaml"

    [ -f "$session_file" ] || continue

    if [ -n "$filter" ]; then
      local type=$(yq -r '.type // "general"' "$session_file")
      [[ "$name" == "$filter"* ]] || [[ "$type" == "$filter" ]] || continue
    fi

    found=true
    local summary=$(yq -r '.summary // ""' "$session_file")
    local last_accessed=$(yq -r '.last_accessed // ""' "$session_file")
    local type=$(yq -r '.type // "general"' "$session_file")

    local time_ago=""
    if [ -n "$last_accessed" ] && [ "$last_accessed" != "null" ]; then
      local timestamp=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_accessed" "+%s" 2>/dev/null || echo "")
      if [ -n "$timestamp" ]; then
        local now=$(date "+%s")
        local diff=$((now - timestamp))
        if [ $diff -lt 60 ]; then
          time_ago="just now"
        elif [ $diff -lt 3600 ]; then
          time_ago="$((diff / 60))m ago"
        elif [ $diff -lt 86400 ]; then
          time_ago="$((diff / 3600))h ago"
        else
          time_ago="$((diff / 86400))d ago"
        fi
      fi
    fi

    local summary_display=""
    if [ -n "$summary" ] && [ "$summary" != "null" ]; then
      [ ${#summary} -gt 50 ] && summary="${summary:0:47}..."
      summary_display="\"$summary\""
    else
      summary_display="${GRAY}(no summary)${NC}"
    fi

    local type_color="$CYAN"
    [[ "$type" == "general" ]] && type_color="$GRAY"

    local output_marker=""
    if [ -f "$session_dir/review-output.md" ]; then
      output_marker=" ${GREEN}[saved]${NC}"
    fi

    printf "  ${BOLD}%-20s${NC} ${type_color}%-50b${NC}%b ${GRAY}%s${NC}\n" "$name" "$summary_display" "$output_marker" "$time_ago"
  done

  if [ "$found" = false ]; then
    echo -e "  ${GRAY}(none)${NC}"
  fi
  echo ""
}

# =============================================================================
# Session Layout Management (iTerm2)
# =============================================================================

# Save session layout pane IDs to layout.json
# Usage: _save_session_layout <session_dir> <window_id> <terminal> <server> <main> [info]
_save_session_layout() {
  local session_dir="$1"
  local window_id="$2"
  local terminal_sid="$3"
  local server_sid="$4"
  local main_sid="$5"
  local info_sid="${6:-}"

  jq -n \
    --arg wid "$window_id" \
    --arg term "$terminal_sid" \
    --arg srv "$server_sid" \
    --arg main "$main_sid" \
    --arg info "$info_sid" \
    '{window_id: $wid, terminal_sid: $term, server_sid: $srv, main_sid: $main, info_sid: $info}' \
    > "$session_dir/layout.json"
}

# Load session layout from layout.json, sets SESSION_*_SID globals
# Returns 1 if file missing or main pane dead
_load_session_layout() {
  local session_dir="$1"
  local layout_file="$session_dir/layout.json"

  if [ ! -f "$layout_file" ]; then
    return 1
  fi

  SESSION_WINDOW_ID=$(jq -r '.window_id // ""' "$layout_file")
  SESSION_TERMINAL_SID=$(jq -r '.terminal_sid // ""' "$layout_file")
  SESSION_SERVER_SID=$(jq -r '.server_sid // ""' "$layout_file")
  SESSION_MAIN_SID=$(jq -r '.main_sid // ""' "$layout_file")
  SESSION_INFO_SID=$(jq -r '.info_sid // ""' "$layout_file")

  # Check if main pane is still alive
  if [ -n "$SESSION_MAIN_SID" ] && iterm_session_exists "$SESSION_MAIN_SID"; then
    return 0
  fi

  # Layout is stale — clean up
  rm -f "$layout_file"
  return 1
}

# Write .crabterm-meta to a session directory for the info bar
# Like write_workspace_meta but takes a dir directly
# Usage: _write_session_meta <session_dir> <name> <type> [key value ...]
_write_session_meta() {
  local session_dir="$1"
  local name="$2"
  local type="$3"
  shift 3

  local meta_file="$session_dir/.crabterm-meta"

  local json
  json=$(jq -n --arg type "$type" --arg name "$name" '{"type": $type, "name": $name}')

  while [ $# -ge 2 ]; do
    local key="$1"
    local value="$2"
    shift 2
    json=$(echo "$json" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
  done

  # Add empty links array (no workspace-level config links for sessions)
  json=$(echo "$json" | jq '. + {links: []}')

  echo "$json" > "$meta_file"
}

# Open or reconnect to an iTerm2 layout for a session
# Usage: _open_session_layout <name> <session_dir> <claude_cmd> [server_cmd] [resume_flag]
_open_session_layout() {
  local name="$1"
  local session_dir="$2"
  local claude_cmd="$3"
  local server_cmd="${4:-}"
  local resume_flag="${5:-}"

  # Try to reconnect to existing layout
  if _load_session_layout "$session_dir"; then
    echo -e "${CYAN}Reconnecting to existing layout...${NC}"
    iterm_focus_session "$SESSION_MAIN_SID"

    if [ -n "$resume_flag" ]; then
      # Restart main pane with continue command
      iterm_send_interrupt "$SESSION_MAIN_SID"
      sleep 0.5
      iterm_send_text "$SESSION_MAIN_SID" "clear && $claude_cmd"
    fi

    # Refresh info bar if alive
    if [ -n "$SESSION_INFO_SID" ] && iterm_session_exists "$SESSION_INFO_SID" 2>/dev/null; then
      iterm_send_interrupt "$SESSION_INFO_SID"
      sleep 0.3
      local infobar_cmd
      infobar_cmd=$(get_infobar_command "$session_dir")
      iterm_send_text "$SESSION_INFO_SID" "clear && $infobar_cmd"
    fi
    return 0
  fi

  # Create new layout
  echo -e "${CYAN}Creating iTerm2 layout for: $name${NC}"
  create_workspace_layout "$name" "$session_dir" "$server_cmd" "$claude_cmd" "" "new" ""

  # Save layout IDs from LAYOUT_* globals
  _save_session_layout "$session_dir" \
    "$LAYOUT_WINDOW_ID" \
    "$LAYOUT_TERMINAL_SID" \
    "$LAYOUT_SERVER_SID" \
    "$LAYOUT_MAIN_SID" \
    "$LAYOUT_INFO_SID"
}

# =============================================================================
# Session Start / Resume
# =============================================================================

# Start a new session and launch Claude
session_start() {
  local name="$1"
  local context="${2:-}"

  local session_dir=$(session_create "$name" "$context")
  [ $? -eq 0 ] || return 1

  echo -e "${CYAN}Starting session: $name${NC}"

  local context_file="$session_dir/context.md"

  if [ -f "$context_file" ]; then
    echo -e "  Context loaded from: $context_file"
  fi

  session_update "$name" "last_accessed" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local claude_cmd="claude --dangerously-skip-permissions --chrome"
  if [ -f "$context_file" ]; then
    claude_cmd="$claude_cmd '$context_file'"
  fi

  _open_session_layout "$name" "$session_dir" "$claude_cmd"
}

# Resume an existing session
session_resume() {
  local name="$1"
  local sessions_dir=$(get_sessions_dir)
  local session_dir="$sessions_dir/$name"
  local session_file="$session_dir/session.yaml"

  if [ ! -f "$session_file" ]; then
    error "Session '$name' not found"
    echo "Use 'crab session ls' to see available sessions"
    return 1
  fi

  echo -e "${CYAN}Resuming session: $name${NC}"

  local summary=$(session_get "$name" "summary")
  [ -n "$summary" ] && [ "$summary" != "null" ] && echo -e "  ${GRAY}$summary${NC}"

  if [ -f "$session_dir/review-output.md" ]; then
    echo -e "  ${GREEN}Review output saved${NC}"
  fi

  session_update "$name" "last_accessed" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local claude_cmd="claude --dangerously-skip-permissions --chrome --continue"
  _open_session_layout "$name" "$session_dir" "$claude_cmd" "" "resume"
}

# Delete a session
session_delete() {
  local name="$1"
  local sessions_dir=$(get_sessions_dir)
  local session_dir="$sessions_dir/$name"

  if [ ! -d "$session_dir" ]; then
    error "Session '$name' not found"
    return 1
  fi

  read -p "Delete session '$name'? [y/N] " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm -rf "$session_dir"
    success "Deleted session: $name"
  else
    echo "Cancelled."
  fi
}

# Delete all sessions matching a prefix
_delete_all_sessions() {
  local prefix="${1:-}"
  local sessions_dir=$(get_sessions_dir)

  if [ ! -d "$sessions_dir" ]; then
    echo "No sessions found."
    return
  fi

  local count=0
  local sessions=()
  for session_dir in "$sessions_dir"/*/; do
    [ -d "$session_dir" ] || continue
    local name=$(basename "$session_dir")
    if [ -z "$prefix" ] || [[ "$name" == "$prefix"* ]]; then
      sessions+=("$name")
      ((count++))
    fi
  done

  if [ $count -eq 0 ]; then
    echo "No ${prefix:-}sessions found."
    return
  fi

  echo "Found $count ${prefix}session(s):"
  for name in "${sessions[@]}"; do
    echo "  - $name"
  done
  echo ""

  read -p "Delete all $count session(s)? [y/N] " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    for name in "${sessions[@]}"; do
      rm -rf "$sessions_dir/$name"
      echo "  Deleted: $name"
    done
    success "Deleted $count session(s)"
  else
    echo "Cancelled."
  fi
}

# Handle session commands
handle_session_command() {
  local cmd="${1:-ls}"
  shift || true

  case "$cmd" in
    "ls"|"list")
      session_list "$@"
      ;;
    "start"|"new")
      local name="${1:-}"
      if [ -z "$name" ]; then
        read -p "Session name: " name
        [ -z "$name" ] && { error "Name required"; return 1; }
      fi
      session_start "$name"
      ;;
    "resume"|"continue")
      local name="${1:-}"
      if [ -z "$name" ]; then
        error "Specify session name: crab session resume <name>"
        return 1
      fi
      session_resume "$name"
      ;;
    "delete"|"rm")
      local name="${1:-}"
      if [ -z "$name" ]; then
        error "Specify session name: crab session delete <name>"
        return 1
      fi
      session_delete "$name"
      ;;
    "summary")
      local name="${1:-}"
      local summary="${2:-}"
      if [ -z "$name" ]; then
        error "Usage: crab session summary <name> \"summary text\""
        return 1
      fi
      if [ -z "$summary" ]; then
        read -p "Summary: " summary
      fi
      session_update "$name" "summary" "$summary"
      success "Updated summary for: $name"
      ;;
    *)
      error "Unknown session command: $cmd"
      echo "Usage: crab session [ls|start|resume|delete|summary]"
      return 1
      ;;
  esac
}
