#!/usr/bin/env bash
# crabterm - workspace operations (iTerm2 native)
# Core workspace management: list, open, create layout, cleanup, restart, continue

# =============================================================================
# Workspace Naming
# =============================================================================

# Get the display name for a workspace
# Returns the custom name if set, otherwise "ws<N>"
get_workspace_name() {
  local num=$1
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  local name_file="$dir/.crabterm-name"

  if [ -f "$name_file" ]; then
    cat "$name_file"
  else
    echo "ws$num"
  fi
}

# Set a custom name for a workspace and update the iTerm2 tab title
set_workspace_name() {
  local num=$1
  local name="$2"
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"

  echo "$name" > "$dir/.crabterm-name"

  # Update iTerm2 tab title if workspace is active
  if state_workspace_exists "$SESSION_NAME" "$num"; then
    state_load_workspace "$SESSION_NAME" "$num"
    iterm_rename_tab_by_session "$WS_MAIN_SID" "$name" 2>/dev/null || true
  fi
}

# Clear the custom name for a workspace
clear_workspace_name() {
  local num=$1
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  rm -f "$dir/.crabterm-name"
}

# =============================================================================
# Workspace Locking
# =============================================================================

# Check if a workspace is locked
# Workspaces are unlocked by default (no lock file = unlocked)
is_workspace_locked() {
  local num=$1
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  [ -f "$dir/.crabterm-lock" ]
}

# Lock a workspace (mark as in-use, don't reuse for PR/ticket)
lock_workspace() {
  local num=$1
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"

  if [ ! -d "$dir" ]; then
    error "Workspace $num does not exist"
    return 1
  fi

  touch "$dir/.crabterm-lock"
  success "Workspace $num locked"
}

# Unlock a workspace (mark as available for reuse by PR/ticket)
unlock_workspace() {
  local num=$1
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"

  if [ ! -d "$dir" ]; then
    error "Workspace $num does not exist"
    return 1
  fi

  rm -f "$dir/.crabterm-lock"
  success "Workspace $num unlocked (available for reuse)"
}

# Unlock all non-active workspaces
unlock_all_workspaces() {
  local unlocked=0
  local skipped=0

  for dir in "$WORKSPACE_BASE/$WORKSPACE_PREFIX-"*; do
    [ -d "$dir" ] || continue
    local num
    num=$(basename "$dir" | sed "s/${WORKSPACE_PREFIX}-//")
    [[ "$num" =~ ^[0-9]+$ ]] || continue

    # Skip workspaces that don't have a lock file
    if ! [ -f "$dir/.crabterm-lock" ]; then
      continue
    fi

    # Skip active workspaces
    if state_workspace_exists "$SESSION_NAME" "$num"; then
      skipped=$((skipped + 1))
      continue
    fi

    rm -f "$dir/.crabterm-lock"
    unlocked=$((unlocked + 1))
  done

  if [ "$unlocked" -eq 0 ] && [ "$skipped" -eq 0 ]; then
    echo -e "${GRAY}No locked workspaces found${NC}"
  else
    [ "$unlocked" -gt 0 ] && success "Unlocked $unlocked workspace(s)"
    [ "$skipped" -gt 0 ] && echo -e "${GRAY}Skipped $skipped active workspace(s)${NC}"
  fi
}

# Find the first unlocked workspace
# Returns: workspace number, or empty string if none found
find_unlocked_workspace() {
  for dir in "$WORKSPACE_BASE/$WORKSPACE_PREFIX-"*; do
    [ -d "$dir" ] || continue
    local num
    num=$(basename "$dir" | sed "s/${WORKSPACE_PREFIX}-//")
    [[ "$num" =~ ^[0-9]+$ ]] || continue

    if ! [ -f "$dir/.crabterm-lock" ]; then
      echo "$num"
      return
    fi
  done

  echo ""
}

# Prepare an existing unlocked workspace for reuse
# Resets to origin/main, closes any active tab, preserves .env files
prepare_workspace_for_reuse() {
  local num=$1
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"

  echo -e "${YELLOW}Preparing workspace $num for reuse...${NC}"

  # Close the iTerm2 tab if it exists
  if state_workspace_exists "$SESSION_NAME" "$num"; then
    state_load_workspace "$SESSION_NAME" "$num"
    iterm_close_tab_by_session "$WS_MAIN_SID" 2>/dev/null || true
    state_remove_workspace "$SESSION_NAME" "$num"
    sleep 0.3
  fi

  # Kill any running processes
  local kill_pattern=$(config_get "cleanup.kill_pattern" "")
  if [ -n "$kill_pattern" ]; then
    kill_pattern="${kill_pattern//\{N\}/$num}"
    kill_pattern="${kill_pattern//\{PREFIX\}/$WORKSPACE_PREFIX}"
    pkill -f "$kill_pattern" 2>/dev/null || true
  fi

  cd "$dir"

  echo "  Fetching origin..."
  git fetch origin 2>/dev/null || true

  echo "  Resetting to origin/main..."
  git checkout main 2>/dev/null || git checkout -b main origin/main 2>/dev/null || true
  git reset --hard origin/main 2>/dev/null || true

  echo "  Cleaning untracked files..."
  local exclude_pattern=$(config_get "cleanup.preserve_files" ".env")
  git clean -fd --exclude="$exclude_pattern" --exclude=".crabterm-*" 2>/dev/null || true

  reset_submodules "$dir"

  # Lock the workspace now that it's being claimed
  touch "$dir/.crabterm-lock"

  # Clear the old name and metadata (caller will set new ones)
  clear_workspace_name "$num"
  clear_workspace_meta "$num"

  echo -e "${GREEN}Workspace $num ready for reuse${NC}"
}

# =============================================================================
# Workspace Listing
# =============================================================================

# List all workspaces
list_workspaces() {
  load_config

  echo -e "${CYAN}Crabterm Workspaces${NC}"
  echo ""

  if ! config_exists; then
    echo -e "${YELLOW}No config file found.${NC}"
    echo ""
    echo "Run 'crabterm init' to set up crabterm."
    return
  fi

  validate_config

  # Check for active workspaces via state files
  local has_active=false
  if [ -d "$STATE_DIR/$SESSION_NAME" ]; then
    for sf in "$STATE_DIR/$SESSION_NAME"/ws*.json; do
      [ -f "$sf" ] || continue
      has_active=true
      break
    done
  fi

  if [ "$has_active" = true ]; then
    echo -e "${GREEN}Active session: $SESSION_NAME${NC}"
    echo ""
  fi

  echo -e "${YELLOW}Available workspaces:${NC}"
  local found=false

  local max_ws=$WORKSPACE_COUNT
  for dir in "$WORKSPACE_BASE/$WORKSPACE_PREFIX-"*; do
    if [ -d "$dir" ]; then
      local num=$(basename "$dir" | sed "s/${WORKSPACE_PREFIX}-//")
      if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -gt "$max_ws" ]; then
        max_ws=$num
      fi
    fi
  done

  for ((i=1; i<=max_ws; i++)); do
    local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$i"
    if [ -d "$dir" ]; then
      found=true
      local branch=$(cd "$dir" && git branch --show-current 2>/dev/null || echo "unknown")
      local port_spacing=$(yq -r '.env_sync.port_spacing // 10' "$CONFIG_FILE" 2>/dev/null)
      [ "$port_spacing" = "null" ] && port_spacing=10
      local api_port=$((API_PORT_BASE + (i * port_spacing)))
      local env_port=$(read_env_port "$dir" "api")
      [ -n "$env_port" ] && api_port="$env_port"

      local status="${YELLOW}[available]${NC}"
      if state_workspace_exists "$SESSION_NAME" "$i"; then
        status="${GREEN}[active]${NC}"
      fi
      local lock_icon=""
      if is_workspace_locked "$i"; then
        lock_icon=" ${RED}[locked]${NC}"
      else
        lock_icon=" ${GRAY}[unlocked]${NC}"
      fi
      local ws_name
      ws_name=$(get_workspace_name "$i")
      local name_display=""
      if [ "$ws_name" != "ws$i" ]; then
        name_display=" ${BOLD}$ws_name${NC}"
      fi
      echo -e "  $i: $WORKSPACE_PREFIX-$i ($branch) :$api_port $status$lock_icon$name_display"
    fi
  done

  if [ "$found" = false ]; then
    echo "  No workspaces found."
    echo ""
    echo "Run 'crab ws new' or 'crab ws 1' to create a workspace."
  fi
}

# Interactive workspace menu
interactive_workspace_menu() {
  load_config

  if ! config_exists; then
    echo -e "${YELLOW}No config file found.${NC}"
    echo ""
    echo "Run 'crab init' to set up crabterm."
    return
  fi

  validate_config

  echo -e "${CYAN}Crabterm Workspaces${NC}"
  echo ""

  local max_ws=$WORKSPACE_COUNT
  local existing_workspaces=""
  for dir in "$WORKSPACE_BASE/$WORKSPACE_PREFIX-"*; do
    if [ -d "$dir" ]; then
      local num=$(basename "$dir" | sed "s/${WORKSPACE_PREFIX}-//")
      if [[ "$num" =~ ^[0-9]+$ ]]; then
        existing_workspaces="$existing_workspaces $num"
        [ "$num" -gt "$max_ws" ] && max_ws=$num
      fi
    fi
  done

  echo -e "${YELLOW}Workspaces:${NC}"
  local found=false
  for ((i=1; i<=max_ws; i++)); do
    local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$i"
    if [ -d "$dir" ]; then
      found=true
      local branch=$(cd "$dir" && git branch --show-current 2>/dev/null || echo "unknown")
      local port_spacing=$(yq -r '.env_sync.port_spacing // 10' "$CONFIG_FILE" 2>/dev/null)
      [ "$port_spacing" = "null" ] && port_spacing=10
      local api_port=$((API_PORT_BASE + (i * port_spacing)))
      local env_port=$(read_env_port "$dir" "api")
      [ -n "$env_port" ] && api_port="$env_port"

      local status="${YELLOW}[available]${NC}"
      if state_workspace_exists "$SESSION_NAME" "$i"; then
        status="${GREEN}[active]${NC}"
      fi
      local lock_icon=""
      if is_workspace_locked "$i"; then
        lock_icon=" ${RED}[locked]${NC}"
      else
        lock_icon=" ${GRAY}[unlocked]${NC}"
      fi
      local ws_name
      ws_name=$(get_workspace_name "$i")
      local name_display=""
      if [ "$ws_name" != "ws$i" ]; then
        name_display=" ${BOLD}$ws_name${NC}"
      fi
      echo -e "  $i: $WORKSPACE_PREFIX-$i ($branch) :$api_port $status$lock_icon$name_display"
    fi
  done

  if [ "$found" = false ]; then
    echo "  (none created yet)"
  fi

  echo ""
  echo -e "${CYAN}Actions:${NC}"
  echo "  [1-9] Open workspace    [n] New    [r] Restart    [c] Cleanup    [q] Quit"
  echo ""
  printf "  > "

  read -r choice

  case "$choice" in
    q|Q|quit|exit|"")
      return 0
      ;;
    n|N|new)
      create_new_workspace
      ;;
    r|R|restart)
      echo -n "  Restart which workspace? [1-9]: "
      read -r ws_num
      if [[ "$ws_num" =~ ^[0-9]+$ ]]; then
        restart_workspace "$ws_num"
      else
        error "Invalid workspace number"
      fi
      ;;
    c|C|cleanup)
      echo -n "  Cleanup which workspace? [1-9]: "
      read -r ws_num
      if [[ "$ws_num" =~ ^[0-9]+$ ]]; then
        cleanup_workspace "$ws_num"
      else
        error "Invalid workspace number"
      fi
      ;;
    *)
      if [[ "$choice" =~ ^[0-9]+$ ]]; then
        open_workspace "$choice"
      else
        error "Unknown option: $choice"
      fi
      ;;
  esac
}

# =============================================================================
# Workspace Layout (iTerm2)
# =============================================================================

# Get command for a pane from config
get_pane_command() {
  local pane_name=$1
  local panes_count=$(yq -r '.layout.panes | length // 0' "$CONFIG_FILE" 2>/dev/null)

  for ((i=0; i<panes_count; i++)); do
    local name=$(yq -r ".layout.panes[$i].name" "$CONFIG_FILE" 2>/dev/null)
    if [ "$name" = "$pane_name" ]; then
      yq -r ".layout.panes[$i].command // \"\"" "$CONFIG_FILE" 2>/dev/null
      return
    fi
  done
  echo ""
}

# Create the iTerm2 layout for a workspace
# Layout:
# ┌─────────┬────────────────┐
# │terminal │                │
# ├─────────┤ main           │
# │ server  │                │
# ├──────────────────────────┤
# │ info bar (full width)    │
# └──────────────────────────┘
create_workspace_layout() {
  local window_name=$1
  local dir=$2
  local dev_cmd=$3
  local claude_cmd=$4
  local port_msg=$5
  local mode=$6  # "new" or "add"
  local ws_num="${7:-}"  # workspace number (optional, extracted from name if not provided)

  # Create window or tab
  local ids=""
  if [ "$mode" = "new" ]; then
    ids=$(iterm_create_window "$window_name" "$dir")
  else
    ids=$(iterm_create_tab "$window_name" "$dir")
  fi

  # Parse returned IDs — full_pane is the initial pane spanning the whole tab
  # Note: window_name can contain colons (e.g. "PR #42: fix(app)"), so we
  # extract window_id from the front and session_id from the back, using
  # the fact that neither contains colons (integer and UUID respectively).
  local window_id=""
  local tab_id="$window_name"
  local full_pane=""

  if [ "$mode" = "new" ]; then
    window_id=$(echo "$ids" | cut -d: -f1)
    full_pane="${ids##*:}"
  else
    full_pane="${ids##*:}"
    window_id="current"
  fi

  if [ -z "$full_pane" ]; then
    error "Failed to get session ID from iTerm2 (ids='$ids')"
    return 1
  fi

  # Give iTerm2 time to fully register the new window
  sleep 0.5

  # Step 1: Split info bar off the bottom FIRST (full width)
  # Use a regular split first — we'll resize it at the end after layout settles
  local info_sid=$(iterm_split_horizontal "$full_pane")
  sleep 0.3

  if [ -z "$info_sid" ]; then
    warn "Info bar split failed (full_pane='$full_pane')"
  fi

  # full_pane is now the top area (terminal + main)
  local terminal_sid="$full_pane"

  # Step 2: Split terminal pane → right split for main
  local main_sid=$(iterm_split_vertical "$terminal_sid")
  sleep 0.3

  if [ -z "$main_sid" ]; then
    warn "Vertical split failed (terminal_sid='$terminal_sid')"
  fi

  # Step 3: Split terminal pane → bottom split for server
  local server_sid=$(iterm_split_horizontal "$terminal_sid")
  sleep 0.3

  if [ -z "$server_sid" ]; then
    warn "Horizontal split failed (terminal_sid='$terminal_sid')"
  fi

  # cd all panes to workspace dir before sending commands
  # Stagger sends to avoid iTerm2 race conditions with rapid write text calls
  iterm_send_text "$terminal_sid" "cd '$dir' && clear"
  sleep 0.2
  iterm_send_text "$server_sid" "cd '$dir' && clear"
  sleep 0.2
  iterm_send_text "$main_sid" "cd '$dir' && clear"
  sleep 0.3

  # Send commands to panes
  [ -n "$dev_cmd" ] && iterm_send_text "$server_sid" "$dev_cmd"
  [ -n "$claude_cmd" ] && iterm_send_text "$main_sid" "$claude_cmd"

  # Start info bar watch loop and resize to minimal height
  # Resize AFTER all splits are done so iTerm2 layout has fully settled,
  # then resize again after a delay to catch post-window-manager resize
  if [ -n "$info_sid" ]; then
    local infobar_cmd
    infobar_cmd=$(get_infobar_command "$dir")
    iterm_send_text "$info_sid" "cd '$dir' && clear && $infobar_cmd"
    sleep 0.3
    iterm_resize_session "$info_sid" 2
    # Second resize in background to catch tiling window manager expansion
    (sleep 2 && iterm_resize_session "$info_sid" 2) &
  fi

  # Export layout IDs for callers that manage their own state
  LAYOUT_WINDOW_ID="$window_id"
  LAYOUT_TERMINAL_SID="$terminal_sid"
  LAYOUT_SERVER_SID="$server_sid"
  LAYOUT_MAIN_SID="$main_sid"
  LAYOUT_INFO_SID="${info_sid:-}"

  # Save state for reconnection
  if [ -z "$ws_num" ] && [[ "$window_name" =~ ^ws([0-9]+)$ ]]; then
    ws_num="${BASH_REMATCH[1]}"
  fi

  if [ -n "$ws_num" ]; then
    state_save_workspace "$SESSION_NAME" "$ws_num" "$window_id" "$tab_id" "$terminal_sid" "$server_sid" "$main_sid" "$info_sid"
  fi
}

# Check and setup workspace (dependencies, .env sync, shared volume)
check_and_setup_workspace() {
  local dir=$1
  local num=$2

  check_and_install_deps "$dir"
  setup_shared_volume "$dir"

  echo -e "${BLUE}Syncing .env files for workspace $num...${NC}"
  sync_env_files "$dir" "$num"
}

# Check if dependencies need installing
check_and_install_deps() {
  local dir=$1
  local install_cmd=$(config_get "install_command" "")

  [ -z "$install_cmd" ] && return

  cd "$dir"

  local marker="$dir/node_modules/.crabterm-installed"
  local need_install="false"

  if [ ! -d "$dir/node_modules" ]; then
    need_install="true"
  elif [ ! -f "$marker" ]; then
    need_install="true"
  elif [ -f "$dir/pnpm-lock.yaml" ] && [ "$dir/pnpm-lock.yaml" -nt "$marker" ]; then
    need_install="true"
  elif [ -f "$dir/package-lock.json" ] && [ "$dir/package-lock.json" -nt "$marker" ]; then
    need_install="true"
  elif [ -f "$dir/yarn.lock" ] && [ "$dir/yarn.lock" -nt "$marker" ]; then
    need_install="true"
  fi

  if [ "$need_install" = "true" ]; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    local install_env=$(config_get "install_env" "")
    local run_cmd="$install_cmd"
    if [ -n "$install_env" ] && [ "$install_env" != "null" ]; then
      run_cmd="$install_env $install_cmd"
    fi
    if bash -c "$run_cmd"; then
      touch "$marker"
      echo -e "${GREEN}Dependencies installed${NC}"
    else
      error "Failed to install dependencies"
      return 1
    fi
  fi

  local submodules_count=$(yq -r '.submodules | length // 0' "$CONFIG_FILE" 2>/dev/null)
  for ((i=0; i<submodules_count; i++)); do
    local sub_path=$(yq -r ".submodules[$i].path" "$CONFIG_FILE" 2>/dev/null)
    local sub_install=$(yq -r ".submodules[$i].install_command // \"\"" "$CONFIG_FILE" 2>/dev/null)

    [ -z "$sub_path" ] || [ "$sub_path" = "null" ] && continue
    [ -z "$sub_install" ] || [ "$sub_install" = "null" ] && continue

    local sub_dir="$dir/$sub_path"
    if [ -d "$sub_dir" ]; then
      local sub_marker="$sub_dir/node_modules/.crabterm-installed"
      local sub_need_install="false"

      if [ ! -d "$sub_dir/node_modules" ]; then
        sub_need_install="true"
      elif [ ! -f "$sub_marker" ]; then
        sub_need_install="true"
      fi

      if [ "$sub_need_install" = "true" ]; then
        echo -e "${YELLOW}Installing $sub_path dependencies...${NC}"
        cd "$sub_dir"
        local sub_run_cmd="$sub_install"
        local install_env=$(config_get "install_env" "")
        if [ -n "$install_env" ] && [ "$install_env" != "null" ]; then
          sub_run_cmd="$install_env $sub_install"
        fi
        if bash -c "$sub_run_cmd"; then
          [ -d "node_modules" ] && touch "$sub_marker"
          echo -e "${GREEN}$sub_path dependencies installed${NC}"
        else
          warn "Failed to install $sub_path dependencies"
        fi
        cd "$dir"
      fi
    fi
  done
}

# =============================================================================
# Open Workspace
# =============================================================================

open_workspace() {
  local num=$1
  local initial_prompt="${2:-}"
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  local window_name
  window_name=$(get_workspace_name "$num")

  if [ ! -d "$dir" ]; then
    create_workspace "$num"
  fi

  # Auto-lock workspace when opened
  touch "$dir/.crabterm-lock"

  local port_info=$(get_workspace_ports "$num" "$dir")
  local api_port=$(echo "$port_info" | cut -d: -f1)
  local app_port=$(echo "$port_info" | cut -d: -f2)
  local need_override=$(echo "$port_info" | cut -d: -f3)
  local env_api_port=$(echo "$port_info" | cut -d: -f4)

  check_and_setup_workspace "$dir" "$num"

  local dev_cmd=$(get_pane_command "server")
  local claude_cmd=$(get_pane_command "main")

  # Always ensure team context exists in CLAUDE.md
  local team_file="$dir/.claude/CLAUDE.md"
  mkdir -p "$dir/.claude"

  if ! grep -q "^## Team Mode$" "$team_file" 2>/dev/null; then
    cat >> "$team_file" << 'EOF'

## Team Mode

You can spawn agent teammates for complex tasks. Use the Task tool to create specialized agents (researcher, implementer, reviewer, debugger) that work in parallel. Coordinate the team, assign tasks, and synthesize results. Only spawn teams when the task benefits from parallel work.
EOF
  fi

  if [ "$need_override" = "true" ]; then
    dev_cmd="PORT=$api_port APP_PORT=$app_port $dev_cmd"
    echo -e "${YELLOW}  Port $env_api_port in use, using $api_port instead${NC}"
  fi

  local port_msg="Using port $env_api_port"
  [ "$need_override" = "true" ] && port_msg="Port $env_api_port in use → using $api_port"

  # Append initial prompt to claude command if provided
  if [ -n "$initial_prompt" ]; then
    if ! [[ "$claude_cmd" == *"claude"* ]]; then
      # Ticket/PR workflows require Claude — default to 'claude' if not configured
      claude_cmd="claude"
    fi
    # Write prompt to a file and pipe it to avoid AppleScript escaping issues
    # (printf '%q' produces actual newlines that break osascript strings)
    local prompt_file="$dir/.crabterm-prompt"
    echo "$initial_prompt" > "$prompt_file"
    claude_cmd="cat '$prompt_file' | $claude_cmd"
  fi

  # Check if workspace already has an active tab
  if state_workspace_exists "$SESSION_NAME" "$num"; then
    if [ -n "$initial_prompt" ]; then
      # Ticket mode: restart the main pane with the new prompt
      state_load_workspace "$SESSION_NAME" "$num"

      echo "  Tab exists, restarting with ticket prompt..."
      iterm_send_interrupt "$WS_SERVER_SID"
      sleep 0.3
      [ -n "$dev_cmd" ] && iterm_send_text "$WS_SERVER_SID" "$dev_cmd"

      iterm_send_interrupt "$WS_MAIN_SID"
      sleep 0.5
      [ -n "$claude_cmd" ] && iterm_send_text "$WS_MAIN_SID" "clear && $claude_cmd"

      # Refresh info bar
      if [ -n "$WS_INFO_SID" ] && [ "$WS_INFO_SID" != "null" ]; then
        iterm_send_interrupt "$WS_INFO_SID"
        sleep 0.3
        local infobar_cmd
        infobar_cmd=$(get_infobar_command "$dir")
        iterm_send_text "$WS_INFO_SID" "clear && $infobar_cmd"
      fi

      success "Workspace $num started with ticket prompt"
    else
      echo -e "${CYAN}Switching to workspace $num...${NC}"
      state_load_workspace "$SESSION_NAME" "$num"

      # Refresh info bar on reconnect
      if [ -n "$WS_INFO_SID" ] && [ "$WS_INFO_SID" != "null" ]; then
        iterm_send_interrupt "$WS_INFO_SID"
        sleep 0.3
        local infobar_cmd
        infobar_cmd=$(get_infobar_command "$dir")
        iterm_send_text "$WS_INFO_SID" "clear && $infobar_cmd"
      fi

      iterm_focus_session "$WS_MAIN_SID"
    fi
  else
    # Create new layout
    if [ -n "$initial_prompt" ]; then
      echo -e "${CYAN}Starting workspace $num (with ticket prompt)...${NC}"
    else
      echo -e "${CYAN}Starting workspace $num...${NC}"
    fi
    echo "  Directory: $dir"
    echo -e "  ${YELLOW}$port_msg${NC}"

    create_workspace_layout "$window_name" "$dir" "$dev_cmd" "$claude_cmd" "$port_msg" "new" "$num"
  fi
}

# Open workspace in a separate iTerm2 window (always creates new window)
open_workspace_separate() {
  local num=$1
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"

  if [ ! -d "$dir" ]; then
    create_workspace "$num"
  fi

  # Auto-lock workspace when opened
  touch "$dir/.crabterm-lock"

  local port_info=$(get_workspace_ports "$num" "$dir")
  local api_port=$(echo "$port_info" | cut -d: -f1)
  local app_port=$(echo "$port_info" | cut -d: -f2)
  local need_override=$(echo "$port_info" | cut -d: -f3)
  local env_api_port=$(echo "$port_info" | cut -d: -f4)

  echo -e "${CYAN}Starting workspace $num in separate window...${NC}"

  check_and_setup_workspace "$dir" "$num"

  local dev_cmd=$(get_pane_command "server")
  local claude_cmd=$(get_pane_command "main")

  if [ "$need_override" = "true" ]; then
    dev_cmd="PORT=$api_port APP_PORT=$app_port $dev_cmd"
    echo -e "${YELLOW}  Port $env_api_port in use, using $api_port instead${NC}"
  fi

  local port_msg="Using port $env_api_port"
  [ "$need_override" = "true" ] && port_msg="Port $env_api_port in use → using $api_port"

  local window_name
  window_name=$(get_workspace_name "$num")
  create_workspace_layout "$window_name" "$dir" "$dev_cmd" "$claude_cmd" "$port_msg" "new" "$num"
}

# =============================================================================
# Cleanup / Restart / Continue
# =============================================================================

cleanup_workspace() {
  local num=$1
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  local window_name="ws$num"

  if [ ! -d "$dir" ]; then
    error "Workspace $num does not exist at $dir"
    exit 1
  fi

  echo -e "${YELLOW}Cleaning up workspace $num...${NC}"

  # Close the iTerm2 tab if it exists
  if state_workspace_exists "$SESSION_NAME" "$num"; then
    state_load_workspace "$SESSION_NAME" "$num"
    iterm_close_tab_by_session "$WS_MAIN_SID" 2>/dev/null || true
    state_remove_workspace "$SESSION_NAME" "$num"
  fi

  # Kill any running processes for this workspace
  local kill_pattern=$(config_get "cleanup.kill_pattern" "")
  if [ -n "$kill_pattern" ]; then
    kill_pattern="${kill_pattern//\{N\}/$num}"
    kill_pattern="${kill_pattern//\{PREFIX\}/$WORKSPACE_PREFIX}"
    pkill -f "$kill_pattern" 2>/dev/null || true
  fi

  cd "$dir"

  echo "  Fetching origin..."
  git fetch origin

  echo "  Resetting to origin/main..."
  git checkout main 2>/dev/null || git checkout -b main origin/main
  git reset --hard origin/main

  echo "  Cleaning untracked files..."
  local exclude_pattern=$(config_get "cleanup.preserve_files" ".env")
  git clean -fd --exclude="$exclude_pattern" --exclude=".crabterm-*"

  reset_submodules "$dir"

  # Unlock and clear name/metadata so the workspace is available for reuse
  rm -f "$dir/.crabterm-lock"
  clear_workspace_name "$num"
  clear_workspace_meta "$num"

  success "Workspace $num cleaned, unlocked, and ready for reuse"
}

# Completely destroy a workspace (remove worktree and all files)
destroy_workspace() {
  local num=$1
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  local window_name="ws$num"
  local branch_name=$(get_branch_name "$num")

  if [ ! -d "$dir" ]; then
    error "Workspace $num does not exist at $dir"
    exit 1
  fi

  echo -e "${RED}Destroying workspace $num...${NC}"
  echo -e "${YELLOW}This will permanently delete all files in the workspace!${NC}"
  echo ""

  if [ "${2:-}" != "--force" ] && [ "${2:-}" != "-f" ]; then
    echo -n "Are you sure? (y/N) "
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
      echo "Aborted."
      return 1
    fi
  fi

  # Close the iTerm2 tab if it exists
  if state_workspace_exists "$SESSION_NAME" "$num"; then
    echo "  Closing iTerm2 tab..."
    state_load_workspace "$SESSION_NAME" "$num"
    iterm_close_tab_by_session "$WS_MAIN_SID" 2>/dev/null || true
    state_remove_workspace "$SESSION_NAME" "$num"
  fi

  # Kill any running processes
  local kill_pattern=$(config_get "cleanup.kill_pattern" "")
  if [ -n "$kill_pattern" ]; then
    kill_pattern="${kill_pattern//\{N\}/$num}"
    kill_pattern="${kill_pattern//\{PREFIX\}/$WORKSPACE_PREFIX}"
    echo "  Killing processes..."
    pkill -f "$kill_pattern" 2>/dev/null || true
  fi

  echo "  Removing git worktree..."
  cd "$MAIN_REPO"
  git worktree remove "$dir" --force 2>/dev/null || true

  if [ -d "$dir" ]; then
    echo "  Force removing directory..."
    rm -rf "$dir"
  fi

  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    local branch_in_use=$(git worktree list | grep "\[$branch_name\]" | wc -l | tr -d ' ')
    if [ "$branch_in_use" = "0" ]; then
      echo "  Deleting branch $branch_name..."
      git branch -D "$branch_name" 2>/dev/null || true
    fi
  fi

  success "Workspace $num destroyed"
}

restart_workspace() {
  local num=$1
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  local window_name
  window_name=$(get_workspace_name "$num")
  local branch_name=$(get_branch_name "$num")

  if [ ! -d "$dir" ]; then
    error "Workspace $num does not exist at $dir"
    exit 1
  fi

  echo -e "${YELLOW}Restarting workspace $num...${NC}"

  cd "$dir"

  local current_branch=$(git branch --show-current)

  echo "  Fetching origin..."
  git fetch origin

  if [ "$current_branch" != "$branch_name" ]; then
    echo "  Switching from $current_branch to $branch_name..."
    git checkout "$branch_name" 2>/dev/null || git checkout -b "$branch_name"
  fi

  echo "  Resetting $branch_name to origin/main content..."
  git reset --hard origin/main

  echo "  Cleaning untracked files..."
  local exclude_pattern=$(config_get "cleanup.preserve_files" ".env")
  git clean -fd --exclude="$exclude_pattern" --exclude=".crabterm-*"

  reset_submodules "$dir"
  setup_shared_volume "$dir"
  sync_env_files "$dir" "$num"
  check_and_install_deps "$dir"

  success "Git reset complete (on branch: $branch_name)"

  # Close old tab if exists, create fresh layout
  if state_workspace_exists "$SESSION_NAME" "$num"; then
    state_load_workspace "$SESSION_NAME" "$num"
    echo "  Closing old tab..."
    iterm_close_tab_by_session "$WS_MAIN_SID" 2>/dev/null || true
    state_remove_workspace "$SESSION_NAME" "$num"
    sleep 0.5
  fi

  local port_info=$(get_workspace_ports "$num" "$dir")
  local api_port=$(echo "$port_info" | cut -d: -f1)
  local app_port=$(echo "$port_info" | cut -d: -f2)
  local need_override=$(echo "$port_info" | cut -d: -f3)
  local env_api_port=$(echo "$port_info" | cut -d: -f4)

  local dev_cmd=$(get_pane_command "server")
  local claude_cmd=$(get_pane_command "main")

  if [ "$need_override" = "true" ]; then
    dev_cmd="PORT=$api_port APP_PORT=$app_port $dev_cmd"
  fi

  local port_msg="Using port $env_api_port"
  [ "$need_override" = "true" ] && port_msg="Port $env_api_port in use → using $api_port"

  echo "  Creating fresh workspace layout..."
  create_workspace_layout "$window_name" "$dir" "$dev_cmd" "$claude_cmd" "$port_msg" "new" "$num"

  success "Workspace $num restarted with fresh layout!"
}

continue_workspace() {
  local num=$1
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  local window_name
  window_name=$(get_workspace_name "$num")

  if [ ! -d "$dir" ]; then
    error "Workspace $num does not exist at $dir"
    exit 1
  fi

  echo -e "${CYAN}Continuing workspace $num...${NC}"

  local port_info=$(get_workspace_ports "$num" "$dir")
  local api_port=$(echo "$port_info" | cut -d: -f1)
  local app_port=$(echo "$port_info" | cut -d: -f2)
  local need_override=$(echo "$port_info" | cut -d: -f3)

  local dev_cmd=$(get_pane_command "server")
  local claude_cmd=$(get_pane_command "main")

  # Add --continue to claude command
  if [[ "$claude_cmd" == *"claude"* ]]; then
    claude_cmd="$claude_cmd --continue"
  fi

  if [ "$need_override" = "true" ]; then
    dev_cmd="PORT=$api_port APP_PORT=$app_port $dev_cmd"
  fi

  if state_workspace_exists "$SESSION_NAME" "$num"; then
    echo "  Tab exists, restarting with --continue..."
    state_load_workspace "$SESSION_NAME" "$num"

    iterm_send_interrupt "$WS_SERVER_SID"
    sleep 0.3
    [ -n "$dev_cmd" ] && iterm_send_text "$WS_SERVER_SID" "$dev_cmd"

    iterm_send_interrupt "$WS_MAIN_SID"
    sleep 0.5
    [ -n "$claude_cmd" ] && iterm_send_text "$WS_MAIN_SID" "clear && $claude_cmd"

    success "Workspace $num continued with previous session"
  else
    echo "  Creating window with --continue..."
    create_workspace_layout "$window_name" "$dir" "$dev_cmd" "$claude_cmd" "" "new" "$num"

    success "Workspace $num started with previous session"
  fi
}

# =============================================================================
# Workspace Detection
# =============================================================================

# Detect workspace number from current directory only
detect_workspace_from_dir() {
  local cwd=$(pwd)
  if [[ "$cwd" =~ $WORKSPACE_PREFIX-([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  echo ""
}

# Detect workspace number from current directory or iTerm2 tab name
detect_workspace() {
  # First try: current directory
  local cwd=$(pwd)
  if [[ "$cwd" =~ $WORKSPACE_PREFIX-([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi

  # Second try: iTerm2 tab name (ws1, ws2, etc.)
  local tab_name
  tab_name=$(iterm_get_current_tab_name 2>/dev/null)
  if [[ "$tab_name" =~ ^ws([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi

  echo ""
}

# Find the next available workspace number
find_next_workspace() {
  local num=1
  while true; do
    local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
    if [ ! -d "$dir" ]; then
      echo "$num"
      return
    fi
    num=$((num + 1))
    if [ $num -gt 100 ]; then
      echo ""
      return
    fi
  done
}

# Build a prompt for Claude to handle a Linear ticket
build_ticket_prompt() {
  local identifier="$1"
  local default_prompt='Fetch the Linear ticket {identifier} using your Linear MCP tools. Read the ticket title, description, and any relevant comments. Then:
1. Create and checkout a git branch using the ticket'\''s suggested branch name from Linear
2. Analyze the requirements from the ticket
3. Create an implementation plan and enter plan mode for my approval before writing any code
If you need clarification on the requirements, ask me before proceeding.'

  local template
  template=$(config_get "ticket.prompt_template" "$default_prompt")
  echo "${template//\{identifier\}/$identifier}"
}

# Create a new workspace with the next available number
create_new_workspace() {
  local next_num=$(find_next_workspace)

  if [ -z "$next_num" ]; then
    error "Could not find an available workspace number"
    exit 1
  fi

  echo -e "${CYAN}Creating new workspace $next_num...${NC}"
  open_workspace "$next_num"
}

# =============================================================================
# Quit / Cleanup Workspace (from info bar)
# =============================================================================

# Close other panes, kill processes, remove state
# Shared helper for quit_workspace and cleanup_workspace_infobar
# Called from the info bar pane — does NOT close the info pane itself
_close_workspace_panes() {
  local dir="$1"
  local num
  num=$(basename "$dir" | sed "s/${WORKSPACE_PREFIX}-//")

  if state_load_workspace "$SESSION_NAME" "$num"; then
    iterm_close_session "$WS_TERMINAL_SID" 2>/dev/null || true
    iterm_close_session "$WS_SERVER_SID" 2>/dev/null || true
    iterm_close_session "$WS_MAIN_SID" 2>/dev/null || true

    # Kill running processes
    local kill_pattern=$(config_get "cleanup.kill_pattern" "")
    if [ -n "$kill_pattern" ]; then
      kill_pattern="${kill_pattern//\{N\}/$num}"
      kill_pattern="${kill_pattern//\{PREFIX\}/$WORKSPACE_PREFIX}"
      pkill -f "$kill_pattern" 2>/dev/null || true
    fi

    state_remove_workspace "$SESSION_NAME" "$num"
  fi
}

# Gracefully quit a workspace: save WIP, close panes, kill processes
quit_workspace() {
  local dir="$1"
  local num
  num=$(basename "$dir" | sed "s/${WORKSPACE_PREFIX}-//")

  # Save WIP state (skip if no changes)
  wip_save "$num" "false" 2>/dev/null || true

  _close_workspace_panes "$dir"
}

# Cleanup a workspace from the info bar: reset git, unlock, clear metadata, close panes
cleanup_workspace_infobar() {
  local dir="$1"
  local num
  num=$(basename "$dir" | sed "s/${WORKSPACE_PREFIX}-//")

  _close_workspace_panes "$dir"

  # Reset git to origin/main
  cd "$dir"
  git fetch origin 2>/dev/null || true
  git checkout main 2>/dev/null || git checkout -b main origin/main 2>/dev/null || true
  git reset --hard origin/main 2>/dev/null || true

  local exclude_pattern=$(config_get "cleanup.preserve_files" ".env")
  git clean -fd --exclude="$exclude_pattern" --exclude=".crabterm-*" 2>/dev/null || true

  reset_submodules "$dir"

  # Unlock and clear name/metadata so the workspace is available for reuse
  rm -f "$dir/.crabterm-lock"
  clear_workspace_name "$num"
  clear_workspace_meta "$num"
}

# =============================================================================
# Workspace Subcommand Handler
# =============================================================================

switch_workspace() {
  local target="${1:-}"

  # Direct switch: crab switch <N>
  if [[ "$target" =~ ^[0-9]+$ ]]; then
    if ! state_workspace_exists "$SESSION_NAME" "$target"; then
      error "Workspace $target is not active"
      return 1
    fi
    state_load_workspace "$SESSION_NAME" "$target"
    iterm_focus_session "$WS_MAIN_SID"
    local ws_name=$(get_workspace_name "$target")
    echo -e "${GREEN}Switched to workspace $target ($ws_name)${NC}"
    return 0
  fi

  # Collect active workspaces
  local active_nums=()
  for dir in "$WORKSPACE_BASE/$WORKSPACE_PREFIX-"*; do
    [ -d "$dir" ] || continue
    local num=$(basename "$dir" | sed "s/${WORKSPACE_PREFIX}-//")
    [[ "$num" =~ ^[0-9]+$ ]] || continue
    if state_workspace_exists "$SESSION_NAME" "$num"; then
      active_nums+=("$num")
    fi
  done

  if [ ${#active_nums[@]} -eq 0 ]; then
    echo "No active workspaces."
    echo "Run 'crab ws <N>' to open a workspace."
    return 0
  fi

  # Single active workspace — switch immediately
  if [ ${#active_nums[@]} -eq 1 ]; then
    local num="${active_nums[0]}"
    state_load_workspace "$SESSION_NAME" "$num"
    iterm_focus_session "$WS_MAIN_SID"
    local ws_name=$(get_workspace_name "$num")
    echo -e "${GREEN}Switched to workspace $num ($ws_name)${NC}"
    return 0
  fi

  # Multiple active — show picker
  echo -e "${CYAN}Active workspaces:${NC}"
  echo ""

  local idx=1
  for num in "${active_nums[@]}"; do
    local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
    local branch=$(cd "$dir" && git branch --show-current 2>/dev/null || echo "unknown")
    local ws_name=$(get_workspace_name "$num")
    local name_display=""
    [ "$ws_name" != "ws$num" ] && name_display=" ${BOLD}$ws_name${NC}"

    local lock_icon=""
    if is_workspace_locked "$num"; then
      lock_icon=" ${RED}[locked]${NC}"
    fi

    echo -e "  [${idx}] ${BOLD}$num${NC}: $WORKSPACE_PREFIX-$num ($branch)$lock_icon$name_display"
    idx=$((idx + 1))
  done

  echo ""
  printf "  Switch to [1-${#active_nums[@]}, q to cancel]: "
  read -r choice

  case "$choice" in
    q|Q|"") return 0 ;;
  esac

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#active_nums[@]} ]; then
    error "Invalid selection"
    return 1
  fi

  local selected_num="${active_nums[$((choice-1))]}"
  state_load_workspace "$SESSION_NAME" "$selected_num"
  iterm_focus_session "$WS_MAIN_SID"
  local ws_name=$(get_workspace_name "$selected_num")
  echo -e "${GREEN}Switched to workspace $selected_num ($ws_name)${NC}"
}

handle_ws_command() {
  local arg="${1:-}"
  shift || true

  case "$arg" in
    "")
      interactive_workspace_menu
      ;;
    "ls"|"list")
      list_workspaces
      ;;
    "new"|"create")
      create_new_workspace
      ;;
    *)
      if [[ "$arg" =~ ^[0-9]+$ ]]; then
        local num="$arg"

        case "${1:-}" in
          "cleanup"|"clean")
            cleanup_workspace "$num"
            ;;
          "destroy"|"rm"|"remove")
            destroy_workspace "$num" "${2:-}"
            ;;
          "restart"|"reset"|"refresh")
            restart_workspace "$num"
            ;;
          "continue"|"resume")
            continue_workspace "$num"
            ;;
          "--separate"|"-s"|"separate")
            open_workspace_separate "$num"
            ;;
          "wip")
            handle_wip_for_workspace "$num" "${@:2}"
            ;;
          "ticket"|"tkt")
            local ticket_id="${2:-}"
            if [ -z "$ticket_id" ]; then
              error "Ticket identifier required: crab ws $num ticket <identifier>"
              exit 1
            fi
            ticket_id=$(parse_ticket_identifier "$ticket_id")
            if ! [[ "$ticket_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
              error "Invalid ticket identifier: $ticket_id"
              echo "Identifiers must be alphanumeric (dashes and underscores allowed)"
              exit 1
            fi
            open_workspace "$num" "$(build_ticket_prompt "$ticket_id")"
            ;;
          "pr")
            handle_ws_pr_command "$num" "${2:-}"
            ;;
          "lock")
            lock_workspace "$num"
            ;;
          "unlock")
            unlock_workspace "$num"
            ;;
          "kill")
            local ws_dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
            echo -e "${YELLOW}Killing ports for workspace $num...${NC}"
            kill_workspace_ports "$ws_dir"
            ;;
          "")
            open_workspace "$num"
            ;;
          *)
            error "Unknown command: crab ws $num $1"
            echo "Try: crab ws $num restart|cleanup|continue|wip|ticket|pr|lock|unlock|kill"
            exit 1
            ;;
        esac
      else
        error "Invalid workspace argument: $arg"
        echo "Usage: crab ws <N> or crab ws new"
        exit 1
      fi
      ;;
  esac
}
