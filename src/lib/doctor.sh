#!/usr/bin/env bash
# crabterm - doctor diagnostics

show_doctor() {
  echo -e "${CYAN}    \\___/${NC}"
  echo -e "${CYAN}   ( *_*)  Crabterm Doctor${NC}"
  echo -e "${CYAN}  /)🦀(\\${NC}"
  echo ""

  if [ -n "${PROJECT_ALIAS:-}" ]; then
    echo -e "  project: ${GREEN}@$PROJECT_ALIAS${NC}"
  fi

  local issues=0

  # Check yq
  echo -n "  yq: "
  if command_exists yq; then
    echo -e "${GREEN}installed${NC}"
  else
    echo -e "${RED}not installed${NC}"
    issues=$((issues + 1))
  fi

  # Check jq (required for state management)
  echo -n "  jq: "
  if command_exists jq; then
    echo -e "${GREEN}installed${NC}"
  else
    echo -e "${RED}not installed${NC}"
    issues=$((issues + 1))
  fi

  # Check iTerm2
  echo -n "  iTerm2: "
  if iterm_is_installed; then
    if iterm_is_running; then
      echo -e "${GREEN}installed and running${NC}"
    else
      echo -e "${YELLOW}installed (not running)${NC}"
    fi
  else
    echo -e "${RED}not installed${NC}"
    issues=$((issues + 1))
  fi

  # Check git
  echo -n "  git: "
  if command_exists git; then
    echo -e "${GREEN}installed${NC}"
  else
    echo -e "${RED}not installed${NC}"
    issues=$((issues + 1))
  fi

  # Check config
  echo -n "  config: "
  if config_exists; then
    echo -e "${GREEN}exists${NC}"

    load_config

    echo -n "  session_name: "
    if [ -n "$SESSION_NAME" ]; then
      echo -e "${GREEN}$SESSION_NAME${NC}"
    else
      echo -e "${RED}not set${NC}"
      issues=$((issues + 1))
    fi

    echo -n "  workspace_base: "
    if [ -n "$WORKSPACE_BASE" ]; then
      if [ -d "$WORKSPACE_BASE" ] || [ -d "$(dirname "$WORKSPACE_BASE")" ]; then
        echo -e "${GREEN}$WORKSPACE_BASE${NC}"
      else
        echo -e "${YELLOW}$WORKSPACE_BASE (will be created)${NC}"
      fi
    else
      echo -e "${RED}not set${NC}"
      issues=$((issues + 1))
    fi

    echo -n "  main_repo: "
    if [ -n "$MAIN_REPO" ]; then
      if [ -d "$MAIN_REPO" ]; then
        echo -e "${GREEN}$MAIN_REPO${NC}"
      else
        echo -e "${RED}$MAIN_REPO (not found)${NC}"
        issues=$((issues + 1))
      fi
    else
      echo -e "${RED}not set${NC}"
      issues=$((issues + 1))
    fi

  else
    echo -e "${YELLOW}not found${NC}"
    echo ""
    echo "Run 'crab init' to create a config file."
    return
  fi

  # Check shared volume
  echo -n "  shared_volume: "
  if [ "$SHARED_VOLUME_ENABLED" = "true" ]; then
    if [ -d "$SHARED_VOLUME_PATH" ]; then
      echo -e "${GREEN}$SHARED_VOLUME_PATH${NC}"
    else
      echo -e "${YELLOW}$SHARED_VOLUME_PATH (will be created)${NC}"
    fi
  else
    echo -e "${YELLOW}disabled${NC}"
  fi

  # Check workspace .env files
  local env_files_count=$(yq -r '.env_sync.files | length // 0' "$CONFIG_FILE" 2>/dev/null)
  if [ "$env_files_count" -gt 0 ] && [ -d "$WORKSPACE_BASE" ]; then
    echo ""
    echo -e "  ${BOLD}Workspace .env files:${NC}"

    local fixable_envs=0

    for dir in "$WORKSPACE_BASE/$WORKSPACE_PREFIX"-*/; do
      [ ! -d "$dir" ] && continue
      local ws_name=$(basename "$dir")

      local ws_fixable=""
      local ws_warnings=""
      for ((i=0; i<env_files_count; i++)); do
        local env_path=$(yq -r ".env_sync.files[$i].path" "$CONFIG_FILE" 2>/dev/null)
        [ -z "$env_path" ] || [ "$env_path" = "null" ] && continue

        local full_path="$dir$env_path"
        local source_path="$MAIN_REPO/$env_path"

        if [ ! -f "$full_path" ]; then
          if [ -f "$source_path" ]; then
            ws_fixable="${ws_fixable}      ${env_path} (fixable)\n"
            fixable_envs=$((fixable_envs + 1))
          else
            ws_warnings="${ws_warnings}      ${env_path} (not in main repo)\n"
          fi
        fi
      done

      if [ -n "$ws_fixable" ] || [ -n "$ws_warnings" ]; then
        if [ -n "$ws_fixable" ]; then
          echo -e "  ${RED}$ws_name: missing .env files${NC}"
          echo -ne "  ${RED}${ws_fixable}${NC}"
        else
          echo -e "  ${YELLOW}$ws_name: missing optional .env files${NC}"
        fi
        [ -n "$ws_warnings" ] && echo -ne "  ${YELLOW}${ws_warnings}${NC}"
      else
        echo -e "  ${GREEN}$ws_name: all .env files present${NC}"
      fi
    done

    if [ $fixable_envs -gt 0 ]; then
      issues=$((issues + fixable_envs))
      echo ""
      echo -e "  ${YELLOW}Run 'crab doctor --fix' to sync missing .env files${NC}"
    fi
  fi

  echo ""
  if [ $issues -eq 0 ]; then
    echo -e "${GREEN}   \\o/${NC}"
    echo -e "${GREEN}  ( ^v^ )  All checks passed!${NC}"
    echo -e "${GREEN}  /)🦀(\\${NC}"
  else
    echo -e "${RED}   \\__/${NC}"
    echo -e "${RED}  ( ;_; )  $issues issue(s) found${NC}"
    echo -e "${RED}  /)🦀(\\${NC}"
  fi
}

# Fix workspace issues (sync missing .env files)
# Usage: doctor_fix [force]
#   force=true: re-copy all env files from main repo before applying adjustments
doctor_fix() {
  local force="${1:-false}"
  load_config
  validate_config

  local env_files_count=$(yq -r '.env_sync.files | length // 0' "$CONFIG_FILE" 2>/dev/null)
  if [ "$env_files_count" = "0" ]; then
    echo "No env_sync files configured."
    return
  fi

  if [ ! -d "$WORKSPACE_BASE" ]; then
    echo "No workspaces found."
    return
  fi

  local fixed=0

  for dir in "$WORKSPACE_BASE/$WORKSPACE_PREFIX"-*/; do
    [ ! -d "$dir" ] && continue
    local ws_name=$(basename "$dir")
    local num=$(echo "$ws_name" | grep -oE '[0-9]+$')

    [ -z "$num" ] && continue

    local ws_fixed=0
    for ((i=0; i<env_files_count; i++)); do
      local env_path=$(yq -r ".env_sync.files[$i].path" "$CONFIG_FILE" 2>/dev/null)
      [ -z "$env_path" ] || [ "$env_path" = "null" ] && continue

      local full_path="$dir$env_path"
      local source_path="$MAIN_REPO/$env_path"

      if [ -f "$source_path" ]; then
        if [ ! -f "$full_path" ]; then
          mkdir -p "$(dirname "$full_path")"
          cp "$source_path" "$full_path"
          echo -e "  ${GREEN}$ws_name: copied $env_path${NC}"
          ws_fixed=$((ws_fixed + 1))
          fixed=$((fixed + 1))
        elif [ "$force" = "true" ]; then
          cp "$source_path" "$full_path"
          echo -e "  ${GREEN}$ws_name: re-copied $env_path${NC}"
          ws_fixed=$((ws_fixed + 1))
          fixed=$((fixed + 1))
        fi
      fi
    done

    # Apply port adjustments, overrides, and refs via sync_env_files
    sync_env_files "$dir" "$num" true
  done

  if [ "$force" = "true" ] && [ $fixed -gt 0 ]; then
    success "Re-synced $fixed .env file(s) from main repo"
  elif [ $fixed -eq 0 ]; then
    echo "All workspace .env files are up to date."
  else
    success "Fixed $fixed missing .env file(s)"
  fi
}
