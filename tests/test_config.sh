#!/usr/bin/env bash
# Tests for config parsing, config_get, expand_path

section "Config Parsing Tests"

TEST_CONFIG_DIR=$(mktemp -d)
TEST_CONFIG="$TEST_CONFIG_DIR/config.yaml"

cat > "$TEST_CONFIG" << 'EOF'
session_name: testcrab
workspace_base: /tmp/test-workspaces
main_repo: /tmp/test-main

workspaces:
  count: 3
  prefix: test-ws
  branch_pattern: test-{N}

ports:
  api_base: 4000
  app_base: 5000

layout:
  panes:
    - name: terminal
      command: ""
    - name: server
      command: echo "server"
    - name: main
      command: echo "main"
EOF

if has_yq; then
  run_test "yq installed" "true"
  # Note: \$() defers command substitution to eval time; $TEST_CONFIG is expanded
  # at string-creation time since single quotes don't prevent expansion inside double quotes
  run_test "Parse session_name" "[ \"\$(yq -r '.session_name' '$TEST_CONFIG')\" = 'testcrab' ]"
  run_test "Parse workspace_base" "[ \"\$(yq -r '.workspace_base' '$TEST_CONFIG')\" = '/tmp/test-workspaces' ]"
  run_test "Parse workspaces.count" "[ \"\$(yq -r '.workspaces.count' '$TEST_CONFIG')\" = '3' ]"
  run_test "Parse workspaces.prefix" "[ \"\$(yq -r '.workspaces.prefix' '$TEST_CONFIG')\" = 'test-ws' ]"
  run_test "Parse workspaces.branch_pattern" "[ \"\$(yq -r '.workspaces.branch_pattern' '$TEST_CONFIG')\" = 'test-{N}' ]"
  run_test "Parse ports.api_base" "[ \"\$(yq -r '.ports.api_base' '$TEST_CONFIG')\" = '4000' ]"
  run_test "Parse ports.app_base" "[ \"\$(yq -r '.ports.app_base' '$TEST_CONFIG')\" = '5000' ]"
  run_test "Parse pane command" "[ \"\$(yq -r '.layout.panes[1].command' '$TEST_CONFIG')\" = 'echo \"server\"' ]"
  run_test "Parse pane name" "[ \"\$(yq -r '.layout.panes[0].name' '$TEST_CONFIG')\" = 'terminal' ]"
  run_test "Parse pane count" "[ \"\$(yq -r '.layout.panes | length' '$TEST_CONFIG')\" = '3' ]"
else
  skip_test "Config parsing tests" "yq not installed"
fi

rm -rf "$TEST_CONFIG_DIR"

# =============================================================================
# config_get / config_exists / expand_path tests
# =============================================================================

section "Config Helper Function Tests"

source "$LIB/common.sh"

# Test expand_path
source "$LIB/config.sh"

run_test "expand_path with tilde" "[ '$(expand_path '~/foo')' = '$HOME/foo' ]"
run_test "expand_path with absolute path" "[ '$(expand_path '/tmp/foo')' = '/tmp/foo' ]"
run_test "expand_path with plain path" "[ '$(expand_path 'relative/path')' = 'relative/path' ]"

# Test config_get with a real config file
CFG_TEST_DIR=$(mktemp -d)
CFG_TEST_FILE="$CFG_TEST_DIR/test.yaml"
cat > "$CFG_TEST_FILE" << 'EOF'
name: testval
nested:
  key: nestedval
EOF

if has_yq; then
  # Save and restore CONFIG_FILE
  _saved_config_file="${CONFIG_FILE:-}"
  CONFIG_FILE="$CFG_TEST_FILE"

  run_test "config_get existing key" "[ '$(config_get 'name')' = 'testval' ]"
  run_test "config_get nested key" "[ '$(config_get 'nested.key')' = 'nestedval' ]"
  run_test "config_get missing key with default" "[ '$(config_get 'missing' 'fallback')' = 'fallback' ]"
  run_test "config_get missing key no default" "[ -z '$(config_get 'missing')' ]"
  run_test "config_exists with file" "config_exists"

  CONFIG_FILE="/nonexistent/file.yaml"
  run_test "config_get with missing file returns default" "[ '$(config_get 'name' 'default')' = 'default' ]"
  run_test "config_exists without file fails" "! config_exists"

  CONFIG_FILE="$_saved_config_file"
else
  skip_test "config_get tests" "yq not installed"
fi

rm -rf "$CFG_TEST_DIR"

# =============================================================================
# validate_config Tests
# =============================================================================

section "Config Validation Tests"

if has_yq; then
  VAL_TEST_DIR=$(mktemp -d)

  # Valid config
  VAL_CONFIG="$VAL_TEST_DIR/valid.yaml"
  cat > "$VAL_CONFIG" << 'EOF'
session_name: testcrab
workspace_base: /tmp/test-ws
main_repo: /tmp/test-main
EOF

  _saved_cf="$CONFIG_FILE"
  CONFIG_FILE="$VAL_CONFIG"
  # validate_config calls exit on error, so run in subshell
  # Note: CONFIG_FILE must be set AFTER sourcing common.sh since common.sh resets it
  run_test "validate_config passes with valid config" "(source '$LIB/common.sh' && source '$LIB/config.sh' && CONFIG_FILE='$VAL_CONFIG' && validate_config 2>/dev/null)"

  # Missing session_name
  VAL_BAD="$VAL_TEST_DIR/bad.yaml"
  cat > "$VAL_BAD" << 'EOF'
workspace_base: /tmp/test-ws
main_repo: /tmp/test-main
EOF
  run_test "validate_config fails without session_name" "! (source '$LIB/common.sh' && source '$LIB/config.sh' && CONFIG_FILE='$VAL_BAD' && validate_config 2>/dev/null)"

  # Missing workspace_base
  cat > "$VAL_BAD" << 'EOF'
session_name: testcrab
main_repo: /tmp/test-main
EOF
  run_test "validate_config fails without workspace_base" "! (source '$LIB/common.sh' && source '$LIB/config.sh' && CONFIG_FILE='$VAL_BAD' && validate_config 2>/dev/null)"

  # Missing main_repo
  cat > "$VAL_BAD" << 'EOF'
session_name: testcrab
workspace_base: /tmp/test-ws
EOF
  run_test "validate_config fails without main_repo" "! (source '$LIB/common.sh' && source '$LIB/config.sh' && CONFIG_FILE='$VAL_BAD' && validate_config 2>/dev/null)"

  # No config file at all
  run_test "validate_config fails with no config" "! (source '$LIB/common.sh' && source '$LIB/config.sh' && CONFIG_FILE='/nonexistent' && validate_config 2>/dev/null)"

  CONFIG_FILE="$_saved_cf"
  rm -rf "$VAL_TEST_DIR"
else
  skip_test "Config validation tests" "yq not installed"
fi

# =============================================================================
# load_config Tests
# =============================================================================

section "Load Config Tests"

if has_yq; then
  LOAD_TEST_DIR=$(mktemp -d)
  LOAD_CONFIG="$LOAD_TEST_DIR/config.yaml"
  cat > "$LOAD_CONFIG" << 'EOF'
session_name: loadtest
workspace_base: /tmp/load-ws
main_repo: /tmp/load-main
workspaces:
  count: 7
  prefix: lws
  branch_pattern: load-{N}
ports:
  api_base: 5000
  app_base: 6000
EOF

  _saved_cf="$CONFIG_FILE"
  _saved_loaded="$_config_loaded"
  CONFIG_FILE="$LOAD_CONFIG"
  _config_loaded=false

  load_config

  run_test "load_config sets SESSION_NAME" "[ '$SESSION_NAME' = 'loadtest' ]"
  run_test "load_config sets WORKSPACE_BASE" "[ '$WORKSPACE_BASE' = '/tmp/load-ws' ]"
  run_test "load_config sets MAIN_REPO" "[ '$MAIN_REPO' = '/tmp/load-main' ]"
  run_test "load_config sets WORKSPACE_COUNT" "[ '$WORKSPACE_COUNT' = '7' ]"
  run_test "load_config sets WORKSPACE_PREFIX" "[ '$WORKSPACE_PREFIX' = 'lws' ]"
  run_test "load_config sets BRANCH_PATTERN" "[ '$BRANCH_PATTERN' = 'load-{N}' ]"
  run_test "load_config sets API_PORT_BASE" "[ '$API_PORT_BASE' = '5000' ]"
  run_test "load_config sets APP_PORT_BASE" "[ '$APP_PORT_BASE' = '6000' ]"
  run_test "load_config marks loaded" "[ '$_config_loaded' = 'true' ]"

  # Second call should be a no-op (idempotent)
  SESSION_NAME="changed"
  load_config
  run_test "load_config is idempotent" "[ '$SESSION_NAME' = 'changed' ]"

  _config_loaded="$_saved_loaded"
  CONFIG_FILE="$_saved_cf"
  rm -rf "$LOAD_TEST_DIR"
else
  skip_test "load_config tests" "yq not installed"
fi

# =============================================================================
# is_legacy_config Tests
# =============================================================================

section "Legacy Config Detection Tests"

if has_yq; then
  LEGACY_TEST_DIR=$(mktemp -d)
  _saved_cd="$CONFIG_DIR"
  _saved_pd="$PROJECTS_DIR"
  CONFIG_DIR="$LEGACY_TEST_DIR"
  PROJECTS_DIR="$LEGACY_TEST_DIR/projects"

  # No config.yaml at all
  run_test "is_legacy_config false with no config" "! is_legacy_config"

  # Legacy config with main_repo, no projects dir
  cat > "$LEGACY_TEST_DIR/config.yaml" << 'EOF'
session_name: old
workspace_base: /tmp/old-ws
main_repo: /tmp/old-main
EOF
  run_test "is_legacy_config true with legacy config" "is_legacy_config"

  # Legacy config but projects dir exists with files
  mkdir -p "$PROJECTS_DIR"
  cat > "$PROJECTS_DIR/proj.yaml" << 'EOF'
session_name: proj
EOF
  run_test "is_legacy_config false when projects exist" "! is_legacy_config"

  # Config without main_repo
  rm -rf "$PROJECTS_DIR"
  cat > "$LEGACY_TEST_DIR/config.yaml" << 'EOF'
session_name: global
EOF
  run_test "is_legacy_config false without main_repo" "! is_legacy_config"

  CONFIG_DIR="$_saved_cd"
  PROJECTS_DIR="$_saved_pd"
  rm -rf "$LEGACY_TEST_DIR"
else
  skip_test "Legacy config tests" "yq not installed"
fi
