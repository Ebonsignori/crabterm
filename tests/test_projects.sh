#!/usr/bin/env bash
# Tests for multi-project resolution and management

if ! has_yq; then
  section "Project Resolution Tests"
  skip_test "Project resolution tests" "yq not installed"
  return 0 2>/dev/null || true
fi

source "$LIB/common.sh"

# =============================================================================
# Setup: isolated project environment
# =============================================================================

PROJ_TEST_DIR=$(mktemp -d)
_saved_config_dir="$CONFIG_DIR"
_saved_projects_dir="$PROJECTS_DIR"
_saved_global_config="$GLOBAL_CONFIG"
_saved_config_file="$CONFIG_FILE"
_saved_project_alias="$PROJECT_ALIAS"

CONFIG_DIR="$PROJ_TEST_DIR"
PROJECTS_DIR="$PROJ_TEST_DIR/projects"
GLOBAL_CONFIG="$PROJ_TEST_DIR/config.yaml"

mkdir -p "$PROJECTS_DIR"

# Create two project configs
cat > "$PROJECTS_DIR/alpha.yaml" << 'EOF'
session_name: alpha
workspace_base: /tmp/alpha-workspaces
main_repo: /tmp/alpha-main
workspaces:
  count: 3
  prefix: alpha-ws
EOF

cat > "$PROJECTS_DIR/beta.yaml" << 'EOF'
session_name: beta
workspace_base: /tmp/beta-workspaces
main_repo: /tmp/beta-main
workspaces:
  count: 2
  prefix: beta-ws
EOF

# Create global config with default
cat > "$GLOBAL_CONFIG" << 'EOF'
default_project: alpha
aliases:
  s: ws 1
  k: kill
EOF

source "$LIB/config.sh"
source "$LIB/projects.sh"

# =============================================================================
# resolve_project Tests
# =============================================================================

section "Project Resolution Tests"

# Test @alias resolution
CONFIG_FILE=""
PROJECT_ALIAS=""
resolve_project "@alpha"
run_test "resolve_project @alpha sets CONFIG_FILE" "[ '$CONFIG_FILE' = '$PROJECTS_DIR/alpha.yaml' ]"
run_test "resolve_project @alpha sets PROJECT_ALIAS" "[ '$PROJECT_ALIAS' = 'alpha' ]"

CONFIG_FILE=""
PROJECT_ALIAS=""
resolve_project "@beta"
run_test "resolve_project @beta sets CONFIG_FILE" "[ '$CONFIG_FILE' = '$PROJECTS_DIR/beta.yaml' ]"
run_test "resolve_project @beta sets PROJECT_ALIAS" "[ '$PROJECT_ALIAS' = 'beta' ]"

# Test missing @alias (uses exit 1, so run in subshell)
run_test "resolve_project @missing fails" "! (source '$LIB/common.sh' && source '$LIB/projects.sh' && PROJECTS_DIR='$PROJECTS_DIR' && resolve_project '@nonexistent' 2>/dev/null)"

# =============================================================================
# resolve_default_project Tests
# =============================================================================

section "Default Project Resolution Tests"

# With default_project set in global config
CONFIG_FILE=""
PROJECT_ALIAS=""
resolve_default_project
run_test "resolve_default picks config default" "[ '$PROJECT_ALIAS' = 'alpha' ]"
run_test "resolve_default sets CONFIG_FILE" "[ '$CONFIG_FILE' = '$PROJECTS_DIR/alpha.yaml' ]"

# With only one project (remove beta, clear default)
rm "$PROJECTS_DIR/beta.yaml"
cat > "$GLOBAL_CONFIG" << 'EOF'
default_project: ""
EOF

CONFIG_FILE=""
PROJECT_ALIAS=""
resolve_default_project
run_test "resolve_default auto-selects single project" "[ '$PROJECT_ALIAS' = 'alpha' ]"

# With multiple projects and no default (restore beta)
cat > "$PROJECTS_DIR/beta.yaml" << 'EOF'
session_name: beta
workspace_base: /tmp/beta-workspaces
main_repo: /tmp/beta-main
EOF

CONFIG_FILE=""
PROJECT_ALIAS=""
resolve_default_project
run_test "resolve_default no pick with multiple projects" "[ -z '$PROJECT_ALIAS' ]"

# With empty projects dir
rm "$PROJECTS_DIR/alpha.yaml" "$PROJECTS_DIR/beta.yaml"
CONFIG_FILE=""
PROJECT_ALIAS=""
resolve_default_project
run_test "resolve_default no pick with empty dir" "[ -z '$PROJECT_ALIAS' ]"

# Restore project files
cat > "$PROJECTS_DIR/alpha.yaml" << 'EOF'
session_name: alpha
workspace_base: /tmp/alpha-workspaces
main_repo: /tmp/alpha-main
EOF
cat > "$PROJECTS_DIR/beta.yaml" << 'EOF'
session_name: beta
workspace_base: /tmp/beta-workspaces
main_repo: /tmp/beta-main
EOF
cat > "$GLOBAL_CONFIG" << 'EOF'
default_project: alpha
aliases:
  s: ws 1
  k: kill
EOF

# =============================================================================
# resolve_project_from_cwd Tests
# =============================================================================

section "Project CWD Resolution Tests"

# Create workspace dirs to match
mkdir -p /tmp/alpha-workspaces/alpha-ws-1
mkdir -p /tmp/beta-workspaces/beta-ws-1

_orig_dir=$(pwd)

CONFIG_FILE=""
PROJECT_ALIAS=""
cd /tmp/alpha-workspaces/alpha-ws-1
resolve_project_from_cwd
run_test "resolve_from_cwd matches alpha workspace_base" "[ '$PROJECT_ALIAS' = 'alpha' ]"

CONFIG_FILE=""
PROJECT_ALIAS=""
cd /tmp/beta-workspaces/beta-ws-1
resolve_project_from_cwd
run_test "resolve_from_cwd matches beta workspace_base" "[ '$PROJECT_ALIAS' = 'beta' ]"

CONFIG_FILE=""
PROJECT_ALIAS=""
cd /tmp
run_test "resolve_from_cwd no match returns 1" "! resolve_project_from_cwd"
run_test "resolve_from_cwd no match leaves alias empty" "[ -z '$PROJECT_ALIAS' ]"

cd "$_orig_dir"
rmdir /tmp/alpha-workspaces/alpha-ws-1 /tmp/alpha-workspaces /tmp/beta-workspaces/beta-ws-1 /tmp/beta-workspaces 2>/dev/null || true

# =============================================================================
# resolve_command_aliases Tests
# =============================================================================

section "Command Alias Resolution Tests"

run_test "resolve_command_aliases finds 's'" "[ '$(resolve_command_aliases 's')' = 'ws 1' ]"
run_test "resolve_command_aliases finds 'k'" "[ '$(resolve_command_aliases 'k')' = 'kill' ]"
run_test "resolve_command_aliases missing returns 1" "! resolve_command_aliases 'nonexistent'"
run_test "resolve_command_aliases empty returns 1" "! resolve_command_aliases ''"

# Without global config
_saved_gc="$GLOBAL_CONFIG"
GLOBAL_CONFIG="/nonexistent"
run_test "resolve_command_aliases no config returns 1" "! resolve_command_aliases 's'"
GLOBAL_CONFIG="$_saved_gc"

# =============================================================================
# Cleanup
# =============================================================================

CONFIG_DIR="$_saved_config_dir"
PROJECTS_DIR="$_saved_projects_dir"
GLOBAL_CONFIG="$_saved_global_config"
CONFIG_FILE="$_saved_config_file"
PROJECT_ALIAS="$_saved_project_alias"

rm -rf "$PROJ_TEST_DIR"
