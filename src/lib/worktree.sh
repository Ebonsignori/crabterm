#!/usr/bin/env bash
# crabterm - git worktree operations, submodules, shared volume

# Get the branch name for workspace N
get_branch_name() {
  local num=$1
  echo "${BRANCH_PATTERN//\{N\}/$num}"
}

# Create workspace directory with git worktree
create_workspace() {
  local num=$1
  local workspace_dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  local branch_name=$(get_branch_name "$num")

  if [ -d "$workspace_dir" ]; then
    echo -e "  ${YELLOW}Workspace $num already exists${NC}"
    return 0
  fi

  echo -e "${CYAN}Creating workspace $num...${NC}"

  if [ ! -d "$MAIN_REPO" ]; then
    error "Main repo not found at $MAIN_REPO"
    exit 1
  fi

  mkdir -p "$WORKSPACE_BASE"

  echo "  Creating git worktree..."
  cd "$MAIN_REPO"
  git fetch origin 2>/dev/null || true

  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    git worktree add "$workspace_dir" "$branch_name"
  elif git show-ref --verify --quiet "refs/remotes/origin/main"; then
    git worktree add -b "$branch_name" "$workspace_dir" origin/main
  else
    git worktree add -b "$branch_name" "$workspace_dir" HEAD
  fi

  init_submodules "$workspace_dir"
  setup_shared_volume "$workspace_dir"
  sync_env_files "$workspace_dir" "$num"

  local install_cmd=$(config_get "install_command" "")
  if [ -n "$install_cmd" ]; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    cd "$workspace_dir"
    local install_env=$(config_get "install_env" "")
    local run_cmd="$install_cmd"
    if [ -n "$install_env" ] && [ "$install_env" != "null" ]; then
      run_cmd="$install_env $install_cmd"
    fi
    if bash -c "$run_cmd"; then
      touch "$workspace_dir/node_modules/.crabterm-installed"
      echo -e "${GREEN}Dependencies installed${NC}"
    else
      warn "Failed to install dependencies - run manually: $install_cmd"
    fi

    local submodules_count=$(yq -r '.submodules | length // 0' "$CONFIG_FILE" 2>/dev/null)
    for ((i=0; i<submodules_count; i++)); do
      local sub_path=$(yq -r ".submodules[$i].path" "$CONFIG_FILE" 2>/dev/null)
      local sub_install=$(yq -r ".submodules[$i].install_command // \"\"" "$CONFIG_FILE" 2>/dev/null)
      [ -z "$sub_path" ] || [ "$sub_path" = "null" ] && continue
      [ -z "$sub_install" ] || [ "$sub_install" = "null" ] && continue

      if [ -d "$workspace_dir/$sub_path" ]; then
        echo -e "${YELLOW}Installing $sub_path dependencies...${NC}"
        cd "$workspace_dir/$sub_path"
        local sub_run_cmd="$sub_install"
        if [ -n "$install_env" ] && [ "$install_env" != "null" ]; then
          sub_run_cmd="$install_env $sub_install"
        fi
        if bash -c "$sub_run_cmd"; then
          [ -d "node_modules" ] && touch "node_modules/.crabterm-installed"
        fi
        cd "$workspace_dir"
      fi
    done
  fi

  sync_mcp_servers "$workspace_dir"

  # Lock new workspaces by default
  touch "$workspace_dir/.crabterm-lock"

  success "Workspace $num created at $workspace_dir"
}

# Initialize submodules in workspace
init_submodules() {
  local dir=$1

  local submodules_count=$(yq -r '.submodules | length // 0' "$CONFIG_FILE" 2>/dev/null)
  [ "$submodules_count" = "0" ] && return

  cd "$dir"

  local git_dir=$(git rev-parse --git-common-dir 2>/dev/null)

  for ((i=0; i<submodules_count; i++)); do
    local sub_path=$(yq -r ".submodules[$i].path" "$CONFIG_FILE" 2>/dev/null)
    local reset_to=$(yq -r ".submodules[$i].reset_to" "$CONFIG_FILE" 2>/dev/null)

    [ -z "$sub_path" ] || [ "$sub_path" = "null" ] && continue

    if [ -d "$dir/$sub_path/.git" ] || [ -f "$dir/$sub_path/.git" ]; then
      echo "  Submodule $sub_path already initialized"
      continue
    fi

    local main_sub="$MAIN_REPO/$sub_path"
    if [ -d "$main_sub" ] && { [ -d "$main_sub/.git" ] || [ -f "$main_sub/.git" ]; }; then
      echo "  Copying submodule: $sub_path (fast copy from main repo)"

      [ -d "$dir/$sub_path" ] && rm -rf "$dir/$sub_path"
      cp -R "$MAIN_REPO/$sub_path" "$dir/$sub_path"

      if [ -f "$dir/$sub_path/.git" ]; then
        local modules_dir="$git_dir/modules/$sub_path"
        if [ -d "$modules_dir" ]; then
          echo "gitdir: $modules_dir" > "$dir/$sub_path/.git"
        fi
      fi
    else
      local modules_dir="$git_dir/modules/$sub_path"
      if [ -d "$modules_dir" ]; then
        echo "  Checking out submodule: $sub_path (using cached git data)"
        git submodule update "$sub_path" 2>/dev/null || git submodule update --init "$sub_path" 2>/dev/null || true
      else
        echo "  Fetching submodule: $sub_path (first time, may take a moment)"
        git submodule update --init "$sub_path" 2>/dev/null || true
      fi
    fi

    if [ -n "$reset_to" ] && [ "$reset_to" != "null" ] && [ -d "$dir/$sub_path" ]; then
      cd "$dir/$sub_path"
      if ! git rev-parse --verify "$reset_to" &>/dev/null; then
        echo "  Fetching $reset_to for $sub_path..."
        git fetch origin --quiet 2>/dev/null || true
      fi
      git checkout main 2>/dev/null || git checkout -b main 2>/dev/null || true
      git reset --hard "$reset_to" 2>/dev/null || true
      cd "$dir"
    fi
  done
}

# Reset submodules to configured state
reset_submodules() {
  local dir=$1

  local submodules_count=$(yq -r '.submodules | length // 0' "$CONFIG_FILE" 2>/dev/null)
  [ "$submodules_count" = "0" ] && return

  for ((i=0; i<submodules_count; i++)); do
    local sub_path=$(yq -r ".submodules[$i].path" "$CONFIG_FILE" 2>/dev/null)
    local reset_to=$(yq -r ".submodules[$i].reset_to" "$CONFIG_FILE" 2>/dev/null)

    [ -z "$sub_path" ] || [ "$sub_path" = "null" ] && continue

    if [ -d "$dir/$sub_path" ]; then
      echo "  Resetting submodule: $sub_path"
      cd "$dir/$sub_path"
      git checkout -- . 2>/dev/null || true
      git clean -fd 2>/dev/null || true
      git checkout main 2>/dev/null || git checkout -b main origin/main 2>/dev/null || true
      git fetch origin main --quiet 2>/dev/null || true
      if [ -n "$reset_to" ] && [ "$reset_to" != "null" ]; then
        git reset --hard "$reset_to"
      else
        git reset --hard origin/main
      fi
      cd "$dir"
      echo -e "  ${GREEN}Submodule $sub_path reset${NC}"
    fi
  done
}

# Setup shared volume symlink in a workspace
setup_shared_volume() {
  local dir=$1

  if [ "$SHARED_VOLUME_ENABLED" != "true" ]; then
    return 0
  fi

  local link_name="$SHARED_VOLUME_LINK"
  local link_path="$dir/$link_name"
  local shared_path="$SHARED_VOLUME_PATH"

  if [ ! -d "$shared_path" ]; then
    echo "  Creating shared volume at $shared_path..."
    mkdir -p "$shared_path"
  fi

  if [ -L "$link_path" ]; then
    local current_target=$(readlink "$link_path")
    if [ "$current_target" = "$shared_path" ]; then
      return 0
    else
      echo "  Updating $link_name symlink..."
      rm "$link_path"
    fi
  elif [ -d "$link_path" ]; then
    echo "  Migrating existing $link_name to shared volume..."

    if [ "$(ls -A "$link_path" 2>/dev/null)" ]; then
      local migrated=0
      for item in "$link_path"/*; do
        [ ! -e "$item" ] && continue
        local basename=$(basename "$item")
        if [ -e "$shared_path/$basename" ]; then
          local ws_name=$(basename "$dir")
          local backup_name="${basename}.from-${ws_name}"
          echo "    $basename exists in shared, saving as $backup_name"
          mv "$item" "$shared_path/$backup_name"
        else
          echo "    Moving $basename to shared volume"
          mv "$item" "$shared_path/"
        fi
        migrated=$((migrated + 1))
      done
      if [ $migrated -gt 0 ]; then
        echo -e "  ${GREEN}Migrated $migrated item(s) to shared volume${NC}"
      fi
    fi

    rmdir "$link_path" 2>/dev/null || rm -rf "$link_path"
  elif [ -e "$link_path" ]; then
    echo "  Backing up existing $link_name..."
    mv "$link_path" "$link_path.backup.$(date +%Y%m%d%H%M%S)"
  fi

  ln -s "$shared_path" "$link_path"
  echo -e "  ${GREEN}Linked $link_name → $shared_path${NC}"

  local gitignore="$dir/.gitignore"
  if [ -f "$gitignore" ]; then
    if ! grep -q "^${link_name}$" "$gitignore" 2>/dev/null; then
      echo "" >> "$gitignore"
      echo "# Shared local volume (crabterm)" >> "$gitignore"
      echo "$link_name" >> "$gitignore"
      echo "  Added $link_name to .gitignore"
    fi
  else
    echo "# Shared local volume (crabterm)" > "$gitignore"
    echo "$link_name" >> "$gitignore"
    echo "  Created .gitignore with $link_name"
  fi
}

# Show shared volume info
show_shared() {
  load_config

  if [ "$SHARED_VOLUME_ENABLED" != "true" ]; then
    echo -e "${YELLOW}Shared volume is disabled.${NC}"
    echo ""
    echo "To enable, add to your config:"
    echo "  shared_volume:"
    echo "    enabled: true"
    return
  fi

  echo -e "${CYAN}Shared Volume${NC}"
  echo ""
  echo -e "  Path: ${GREEN}$SHARED_VOLUME_PATH${NC}"
  echo -e "  Link name: $SHARED_VOLUME_LINK"
  echo ""

  if [ -d "$SHARED_VOLUME_PATH" ]; then
    local count=$(ls -1 "$SHARED_VOLUME_PATH" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Contents ($count items):"
    ls -la "$SHARED_VOLUME_PATH" 2>/dev/null | tail -n +2 | while read -r line; do
      echo "    $line"
    done
  else
    echo -e "  ${YELLOW}Not yet created (will be created on first workspace open)${NC}"
  fi
}
