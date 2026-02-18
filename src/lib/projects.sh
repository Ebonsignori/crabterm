#!/usr/bin/env bash
# crabterm - multi-project resolution and management

# Resolve project from @alias argument or fall back to default
resolve_project() {
  local arg="${1:-}"

  if [[ "$arg" == @* ]]; then
    local alias="${arg#@}"
    local project_file="$PROJECTS_DIR/${alias}.yaml"
    if [ ! -f "$project_file" ]; then
      error "No project registered with alias: @$alias"
      echo "Run 'crab projects' to see registered projects."
      exit 1
    fi
    CONFIG_FILE="$project_file"
    PROJECT_ALIAS="$alias"
    return
  fi

  resolve_default_project
}

# Resolve the default project when no @alias is given
resolve_default_project() {
  if [ ! -d "$PROJECTS_DIR" ] || [ -z "$(ls -A "$PROJECTS_DIR" 2>/dev/null)" ]; then
    return
  fi

  local default_alias=""
  if [ -f "$GLOBAL_CONFIG" ]; then
    default_alias=$(yq -r '.default_project // ""' "$GLOBAL_CONFIG" 2>/dev/null)
    [ "$default_alias" = "null" ] && default_alias=""
  fi

  if [ -n "$default_alias" ]; then
    local project_file="$PROJECTS_DIR/${default_alias}.yaml"
    if [ -f "$project_file" ]; then
      CONFIG_FILE="$project_file"
      PROJECT_ALIAS="$default_alias"
      return
    fi
    warn "Default project '@$default_alias' not found, ignoring."
  fi

  local count=0
  local single_file=""
  for f in "$PROJECTS_DIR"/*.yaml; do
    [ -f "$f" ] || continue
    count=$((count + 1))
    single_file="$f"
  done

  if [ "$count" -eq 1 ]; then
    local alias=$(basename "$single_file" .yaml)
    CONFIG_FILE="$single_file"
    PROJECT_ALIAS="$alias"
    return
  fi
}

# Try to resolve the correct project from the current working directory
resolve_project_from_cwd() {
  local cwd=$(pwd)

  if [ ! -d "$PROJECTS_DIR" ]; then
    return 1
  fi

  for f in "$PROJECTS_DIR"/*.yaml; do
    [ -f "$f" ] || continue
    local ws_base=$(yq -r '.workspace_base // ""' "$f" 2>/dev/null)
    [ -z "$ws_base" ] || [ "$ws_base" = "null" ] && continue
    ws_base="${ws_base/#\~/$HOME}"

    if [[ "$cwd" == "$ws_base"* ]]; then
      local alias=$(basename "$f" .yaml)
      CONFIG_FILE="$f"
      PROJECT_ALIAS="$alias"
      return 0
    fi

    local repo=$(yq -r '.main_repo // ""' "$f" 2>/dev/null)
    [ -z "$repo" ] || [ "$repo" = "null" ] && continue
    repo="${repo/#\~/$HOME}"

    if [[ "$cwd" == "$repo"* ]]; then
      local alias=$(basename "$f" .yaml)
      CONFIG_FILE="$f"
      PROJECT_ALIAS="$alias"
      return 0
    fi
  done

  return 1
}

# Resolve user-configured command aliases from global config
resolve_command_aliases() {
  local cmd="${1:-}"
  [ -z "$cmd" ] && return 1

  if [ ! -f "$GLOBAL_CONFIG" ]; then
    return 1
  fi

  local resolved
  resolved=$(cmd="$cmd" yq -r '.aliases.[strenv(cmd)] // ""' "$GLOBAL_CONFIG" 2>/dev/null)
  if [ -n "$resolved" ] && [ "$resolved" != "null" ]; then
    echo "$resolved"
    return 0
  fi
  return 1
}

# List all registered projects
show_projects() {
  local subcmd="${1:-}"

  if [ "$subcmd" = "rm" ] || [ "$subcmd" = "remove" ] || [ "$subcmd" = "delete" ]; then
    remove_project "${2:-}"
    return
  fi

  echo -e "${CYAN}Registered Projects${NC}"
  echo ""

  if [ ! -d "$PROJECTS_DIR" ] || [ -z "$(ls -A "$PROJECTS_DIR" 2>/dev/null)" ]; then
    echo "  No projects registered."
    echo ""
    echo "  Run 'crab init' to register your first project."
    return
  fi

  local default_alias=""
  if [ -f "$GLOBAL_CONFIG" ]; then
    default_alias=$(yq -r '.default_project // ""' "$GLOBAL_CONFIG" 2>/dev/null)
    [ "$default_alias" = "null" ] && default_alias=""
  fi

  for f in "$PROJECTS_DIR"/*.yaml; do
    [ -f "$f" ] || continue
    local alias=$(basename "$f" .yaml)
    local repo=$(yq -r '.main_repo // ""' "$f" 2>/dev/null)
    local session=$(yq -r '.session_name // ""' "$f" 2>/dev/null)

    # Check if workspace state exists for this session
    local status_icon="  "
    local state_dir="$CONFIG_DIR/state/$session"
    if [ -d "$state_dir" ] && [ -n "$(ls -A "$state_dir" 2>/dev/null)" ]; then
      status_icon="${GREEN}●${NC} "
    fi

    local default_marker=""
    if [ "$alias" = "$default_alias" ]; then
      default_marker=" ${YELLOW}(default)${NC}"
    fi

    echo -e "  ${status_icon}${BOLD}@$alias${NC}${default_marker}"
    echo -e "    ${GRAY}$repo${NC}"
  done
  echo ""
}

# Remove a project registration
remove_project() {
  local alias="${1:-}"

  if [ -z "$alias" ]; then
    error "Usage: crab projects rm <alias>"
    return 1
  fi

  alias="${alias#@}"

  local project_file="$PROJECTS_DIR/${alias}.yaml"
  if [ ! -f "$project_file" ]; then
    error "No project registered with alias: @$alias"
    return 1
  fi

  echo -e "Remove project registration for ${BOLD}@$alias${NC}?"
  echo -e "  ${GRAY}(This only removes the config, not your workspaces or repo)${NC}"
  read -p "  [y/N]: " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled."
    return
  fi

  rm "$project_file"

  if [ -f "$GLOBAL_CONFIG" ]; then
    local current_default=$(yq -r '.default_project // ""' "$GLOBAL_CONFIG" 2>/dev/null)
    if [ "$current_default" = "$alias" ]; then
      yq -i '.default_project = ""' "$GLOBAL_CONFIG"
      echo -e "  ${YELLOW}Cleared default project (was @$alias)${NC}"
    fi
  fi

  success "Removed project @$alias"
}

# Set or show the default project
set_default_project() {
  local alias="${1:-}"

  if [ -z "$alias" ]; then
    local current=""
    if [ -f "$GLOBAL_CONFIG" ]; then
      current=$(yq -r '.default_project // ""' "$GLOBAL_CONFIG" 2>/dev/null)
      [ "$current" = "null" ] && current=""
    fi
    if [ -n "$current" ]; then
      echo -e "Default project: ${BOLD}@$current${NC}"
    else
      echo "No default project set."
      echo "Usage: crab default <alias>"
    fi
    return
  fi

  alias="${alias#@}"

  local project_file="$PROJECTS_DIR/${alias}.yaml"
  if [ ! -f "$project_file" ]; then
    error "No project registered with alias: @$alias"
    echo "Run 'crab projects' to see registered projects."
    return 1
  fi

  mkdir -p "$CONFIG_DIR"
  if [ -f "$GLOBAL_CONFIG" ]; then
    yq -i ".default_project = \"$alias\"" "$GLOBAL_CONFIG"
  else
    cat > "$GLOBAL_CONFIG" << EOF
# Crabterm Global Configuration
default_project: $alias
EOF
  fi

  success "Default project set to @$alias"
}

# =============================================================================
# Alias Management
# =============================================================================

handle_alias_command() {
  local subcmd="${1:-}"

  case "$subcmd" in
    "")
      if [ ! -f "$GLOBAL_CONFIG" ]; then
        echo -e "${YELLOW}No aliases configured.${NC}"
        echo ""
        echo "Set one with: crab alias set <name> <command...>"
        return
      fi

      local aliases
      aliases=$(yq -r '.aliases // {} | to_entries[] | .key + " → " + (.value | tostring)' "$GLOBAL_CONFIG" 2>/dev/null)
      if [ -z "$aliases" ]; then
        echo -e "${YELLOW}No aliases configured.${NC}"
        echo ""
        echo "Set one with: crab alias set <name> <command...>"
        return
      fi

      echo -e "${CYAN}Command Aliases${NC}"
      echo ""
      while IFS= read -r line; do
        local name="${line%% →*}"
        local value="${line#*→ }"
        echo -e "  ${GREEN}$name${NC} → $value"
      done <<< "$aliases"
      echo ""
      echo -e "${GRAY}Config: $GLOBAL_CONFIG${NC}"
      ;;
    "set"|"add")
      local name="${2:-}"
      if [ -z "$name" ]; then
        error "Usage: crab alias set <name> <command...>"
        exit 1
      fi
      if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid alias name '$name'. Use only letters, numbers, hyphens, and underscores."
        exit 1
      fi

      shift 2
      local value="$*"
      if [ -z "$value" ]; then
        error "Usage: crab alias set <name> <command...>"
        exit 1
      fi

      mkdir -p "$CONFIG_DIR"
      if [ ! -f "$GLOBAL_CONFIG" ]; then
        echo "{}" > "$GLOBAL_CONFIG"
      fi

      NAME="$name" VALUE="$value" yq -i '.aliases.[strenv(NAME)] = strenv(VALUE)' "$GLOBAL_CONFIG"
      echo -e "${GREEN}Alias set:${NC} $name → $value"
      ;;
    "rm"|"remove"|"delete")
      local name="${2:-}"
      if [ -z "$name" ]; then
        error "Usage: crab alias rm <name>"
        exit 1
      fi

      if [ ! -f "$GLOBAL_CONFIG" ]; then
        error "No aliases configured"
        exit 1
      fi

      local existing
      existing=$(NAME="$name" yq -r '.aliases.[strenv(NAME)] // ""' "$GLOBAL_CONFIG" 2>/dev/null)
      if [ -z "$existing" ] || [ "$existing" = "null" ]; then
        error "Alias '$name' not found"
        exit 1
      fi

      NAME="$name" yq -i 'del(.aliases.[strenv(NAME)])' "$GLOBAL_CONFIG"

      local remaining
      remaining=$(yq -r '.aliases // {} | length' "$GLOBAL_CONFIG" 2>/dev/null)
      if [ "$remaining" = "0" ]; then
        yq -i 'del(.aliases)' "$GLOBAL_CONFIG"
      fi

      echo -e "${GREEN}Removed alias:${NC} $name"
      ;;
    *)
      error "Unknown alias subcommand: $subcmd"
      echo ""
      echo "Usage:"
      echo "  crab alias              List all aliases"
      echo "  crab alias set <name> <command...>  Set an alias"
      echo "  crab alias rm <name>    Remove an alias"
      exit 1
      ;;
  esac
}
