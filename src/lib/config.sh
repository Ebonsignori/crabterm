#!/usr/bin/env bash
# crabterm - configuration loading and management

# Load a config value, with optional default
# Usage: config_get "path.to.value" "default"
config_get() {
  local path="$1"
  local default="${2:-}"
  local value

  if [ ! -f "$CONFIG_FILE" ]; then
    echo "$default"
    return
  fi

  value=$(yq -r ".$path // \"\"" "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "$default"
  else
    echo "$value"
  fi
}

# Check if config exists and is valid
config_exists() {
  [ -f "$CONFIG_FILE" ]
}

# Validate required config fields
validate_config() {
  local errors=0

  if ! config_exists; then
    if [ -n "${PROJECT_ALIAS:-}" ]; then
      error "Config not found for project @$PROJECT_ALIAS at $CONFIG_FILE"
    else
      error "No config file found at $CONFIG_FILE"
    fi
    echo "Run 'crabterm init' to create one."
    exit 1
  fi

  local session_name=$(config_get "session_name")
  local workspace_base=$(config_get "workspace_base")
  local main_repo=$(config_get "main_repo")

  if [ -z "$session_name" ]; then
    error "Missing required config: session_name"
    errors=$((errors + 1))
  fi

  if [ -z "$workspace_base" ]; then
    error "Missing required config: workspace_base"
    errors=$((errors + 1))
  fi

  if [ -z "$main_repo" ]; then
    error "Missing required config: main_repo"
    errors=$((errors + 1))
  fi

  if [ $errors -gt 0 ]; then
    echo ""
    echo "Run 'crabterm doctor' to diagnose issues."
    exit 1
  fi
}

# Sync MCP config from main repo to workspace
sync_mcp_servers() {
  local workspace_dir=$1
  local main_repo=$(config_get "main_repo" "")

  [ -z "$main_repo" ] && return

  if [ -f "$main_repo/.mcp.json" ]; then
    cp "$main_repo/.mcp.json" "$workspace_dir/.mcp.json"
    echo -e "${GREEN}Copied .mcp.json from main repo${NC}"
  fi
}

# Expand ~ and environment variables in paths
expand_path() {
  local path="$1"
  path="${path/#\~/$HOME}"
  eval echo "$path"
}

# =============================================================================
# Config Variables (loaded lazily)
# =============================================================================

_config_loaded=false

load_config() {
  if [ "$_config_loaded" = true ]; then
    return
  fi

  if ! config_exists; then
    return
  fi

  SESSION_NAME=$(config_get "session_name" "crab")
  WORKSPACE_BASE=$(expand_path "$(config_get "workspace_base")")
  MAIN_REPO=$(expand_path "$(config_get "main_repo")")

  WORKSPACE_COUNT=$(config_get "workspaces.count" "5")
  WORKSPACE_PREFIX=$(config_get "workspaces.prefix" "workspace")
  BRANCH_PATTERN=$(config_get "workspaces.branch_pattern" "workspace-{N}")

  API_PORT_BASE=$(config_get "ports.api_base" "3200")
  APP_PORT_BASE=$(config_get "ports.app_base" "3000")

  # Shared volume settings
  SHARED_VOLUME_PATH=$(expand_path "$(config_get "shared_volume.path" "$CONFIG_DIR/shared")")
  SHARED_VOLUME_LINK=$(config_get "shared_volume.link_as" ".local")
  SHARED_VOLUME_ENABLED=$(config_get "shared_volume.enabled" "true")

  _config_loaded=true

  # WIP isolation: per-project WIP directories
  if [ -n "${PROJECT_ALIAS:-}" ]; then
    WIP_BASE="$CONFIG_DIR/wip/$PROJECT_ALIAS"
  fi
}

# Check if we're in legacy single-project mode
is_legacy_config() {
  if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
    return 1
  fi
  local has_main_repo=$(yq -r '.main_repo // ""' "$CONFIG_DIR/config.yaml" 2>/dev/null)
  if [ -z "$has_main_repo" ] || [ "$has_main_repo" = "null" ]; then
    return 1
  fi
  if [ -d "$PROJECTS_DIR" ] && [ -n "$(ls -A "$PROJECTS_DIR" 2>/dev/null)" ]; then
    return 1
  fi
  return 0
}

# Prompt user to migrate legacy config.yaml → projects/<alias>.yaml
check_legacy_migration() {
  echo -e "${CYAN}Multi-project support detected.${NC}"
  echo ""
  echo "Your config at ~/.crabterm/config.yaml can be migrated to the new"
  echo "per-project format. This enables managing multiple repos with crab."
  echo ""
  read -p "Migrate now? [Y/n]: " migrate
  if [ "$migrate" = "n" ] || [ "$migrate" = "N" ]; then
    return
  fi

  local repo_path=$(yq -r '.main_repo // ""' "$CONFIG_DIR/config.yaml" 2>/dev/null)
  local default_alias=$(basename "$repo_path" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')
  echo ""
  read -p "Project alias [$default_alias]: " alias_input
  alias_input=${alias_input:-$default_alias}

  if ! [[ "$alias_input" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Alias must be alphanumeric (dashes and underscores allowed)"
    return 1
  fi

  mkdir -p "$PROJECTS_DIR"
  cp "$CONFIG_DIR/config.yaml" "$PROJECTS_DIR/${alias_input}.yaml"

  # Update session_name in the project config to use the alias
  yq -i ".session_name = \"$alias_input\"" "$PROJECTS_DIR/${alias_input}.yaml"

  # Backup old config and create new global config
  cp "$CONFIG_DIR/config.yaml" "$CONFIG_DIR/config.yaml.bak"

  cat > "$GLOBAL_CONFIG" << EOF
# Crabterm Global Configuration
default_project: $alias_input
EOF

  CONFIG_FILE="$PROJECTS_DIR/${alias_input}.yaml"
  PROJECT_ALIAS="$alias_input"

  echo ""
  success "Migrated to @$alias_input"
  echo "  Project config: $PROJECTS_DIR/${alias_input}.yaml"
  echo "  Backup: ~/.crabterm/config.yaml.bak"
  echo "  Default set to: @$alias_input"
  echo ""
}
