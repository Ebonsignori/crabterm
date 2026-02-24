#!/usr/bin/env bash
# Tests for workspace lock/unlock, naming, detection, find_next

# =============================================================================
# Setup
# =============================================================================

source "$LIB/common.sh"

WS_TEST_DIR=$(mktemp -d)
WORKSPACE_BASE="$WS_TEST_DIR"
WORKSPACE_PREFIX="test-ws"

mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-1"
mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-2"
mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-3"

# Stub out external dependencies
state_workspace_exists() { return 1; }
state_load_workspace() { :; }
state_remove_workspace() { :; }
config_get() { echo "${2:-}"; }
reset_submodules() { :; }
iterm_rename_tab_by_session() { :; }
SESSION_NAME="test"
BRANCH_PATTERN="test-{N}"

source "$LIB/workspace.sh"

# =============================================================================
# Lock/Unlock Tests
# =============================================================================

section "Lock/Unlock Functional Tests"

# Start fresh (remove any lock files)
rm -f "$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-lock"
rm -f "$WORKSPACE_BASE/$WORKSPACE_PREFIX-2/.crabterm-lock"
rm -f "$WORKSPACE_BASE/$WORKSPACE_PREFIX-3/.crabterm-lock"

run_test "Fresh workspace is unlocked" "! is_workspace_locked 1"
run_test "lock_workspace creates lock file" "lock_workspace 1 >/dev/null && [ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-lock' ]"
run_test "Locked workspace detected" "is_workspace_locked 1"
run_test "unlock_workspace removes lock file" "unlock_workspace 1 >/dev/null && ! [ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-lock' ]"
run_test "Unlocked workspace detected" "! is_workspace_locked 1"
run_test "Lock non-existent workspace fails" "! lock_workspace 99 2>/dev/null"
run_test "Unlock non-existent workspace fails" "! unlock_workspace 99 2>/dev/null"

# find_unlocked_workspace tests
lock_workspace 1 >/dev/null
run_test "find_unlocked_workspace finds ws 2" "[ '$(find_unlocked_workspace)' = '2' ]"

lock_workspace 2 >/dev/null
lock_workspace 3 >/dev/null
run_test "find_unlocked_workspace empty when all locked" "[ -z '$(find_unlocked_workspace)' ]"

unlock_workspace 3 >/dev/null
run_test "find_unlocked_workspace finds ws 3 after unlock" "[ '$(find_unlocked_workspace)' = '3' ]"

# Unlock all (non-active) workspaces
lock_workspace 1 >/dev/null
lock_workspace 2 >/dev/null
lock_workspace 3 >/dev/null
# Note: || true needed because unlock_all_workspaces uses [ ] && echo pattern
# which returns non-zero when condition is false, triggering set -e
unlock_all_workspaces >/dev/null 2>&1 || true
run_test "unlock_all removes all lock files" "! is_workspace_locked 1 && ! is_workspace_locked 2 && ! is_workspace_locked 3"

# =============================================================================
# Workspace Naming Tests
# =============================================================================

section "Workspace Naming Tests"

# Reset lock state
rm -f "$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-lock"
rm -f "$WORKSPACE_BASE/$WORKSPACE_PREFIX-2/.crabterm-lock"
rm -f "$WORKSPACE_BASE/$WORKSPACE_PREFIX-3/.crabterm-lock"

run_test "Default name is ws1" "[ '$(get_workspace_name 1)' = 'ws1' ]"
run_test "Default name is ws2" "[ '$(get_workspace_name 2)' = 'ws2' ]"

set_workspace_name 1 "PR #42: Fix login" 2>/dev/null
run_test "set_workspace_name creates name file" "[ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-name' ]"
run_test "get_workspace_name returns custom name" "[ '$(get_workspace_name 1)' = 'PR #42: Fix login' ]"

clear_workspace_name 1
run_test "clear_workspace_name removes name file" "! [ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-name' ]"
run_test "Name reverts to default after clear" "[ '$(get_workspace_name 1)' = 'ws1' ]"

set_workspace_name 2 "ENG-123" 2>/dev/null
run_test "Ticket name set correctly" "[ '$(get_workspace_name 2)' = 'ENG-123' ]"

# Names with special characters
set_workspace_name 1 "fix(auth): handle edge case" 2>/dev/null
run_test "Name with parens and colon" "[ '$(get_workspace_name 1)' = 'fix(auth): handle edge case' ]"

set_workspace_name 1 "PR #99 - long description here" 2>/dev/null
run_test "Name with hash and dash" "[ '$(get_workspace_name 1)' = 'PR #99 - long description here' ]"

# =============================================================================
# find_next_workspace Tests
# =============================================================================

section "Workspace Discovery Tests"

run_test "find_next_workspace skips existing" "[ '$(find_next_workspace)' = '4' ]"

# Create a gap
mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-5"
run_test "find_next_workspace finds gap at 4" "[ '$(find_next_workspace)' = '4' ]"

# Fill the gap
mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-4"
run_test "find_next_workspace finds 6" "[ '$(find_next_workspace)' = '6' ]"

# =============================================================================
# get_branch_name Tests
# =============================================================================

section "Branch Name Tests"

source "$LIB/worktree.sh"

BRANCH_PATTERN="workspace-{N}"
run_test "get_branch_name substitutes N" "[ '$(get_branch_name 3)' = 'workspace-3' ]"

BRANCH_PATTERN="feature/ws-{N}"
run_test "get_branch_name with prefix" "[ '$(get_branch_name 1)' = 'feature/ws-1' ]"

BRANCH_PATTERN="dev-{N}"
run_test "get_branch_name dev pattern" "[ '$(get_branch_name 42)' = 'dev-42' ]"

# =============================================================================
# build_ticket_prompt Tests
# =============================================================================

section "Ticket Prompt Tests"

# build_ticket_prompt is in workspace.sh, already sourced
# config_get is stubbed to return the default (second arg)
run_test "build_ticket_prompt includes identifier" "build_ticket_prompt 'ENG-123' | grep -q 'ENG-123'"
run_test "build_ticket_prompt includes Linear" "build_ticket_prompt 'ENG-123' | grep -q 'Linear'"
run_test "build_ticket_prompt includes branch" "build_ticket_prompt 'ENG-123' | grep -q 'branch'"

# =============================================================================
# get_pane_command Tests
# =============================================================================

section "Pane Command Tests"

if has_yq; then
  PANE_TEST_DIR=$(mktemp -d)
  PANE_CONFIG="$PANE_TEST_DIR/config.yaml"
  cat > "$PANE_CONFIG" << 'PANEEOF'
layout:
  panes:
    - name: terminal
      command: ""
    - name: server
      command: pnpm dev
    - name: main
      command: claude --dangerously-skip-permissions
PANEEOF

  _saved_cf="$CONFIG_FILE"
  CONFIG_FILE="$PANE_CONFIG"

  # Temporarily replace config_get with real version for pane tests
  _stub_config_get() { echo "${2:-}"; }
  # get_pane_command reads CONFIG_FILE directly via yq, doesn't use config_get

  run_test "get_pane_command finds server" "[ \"\$(get_pane_command 'server')\" = 'pnpm dev' ]"
  run_test "get_pane_command finds main" "[ \"\$(get_pane_command 'main')\" = 'claude --dangerously-skip-permissions' ]"
  run_test "get_pane_command terminal is empty" "[ -z \"\$(get_pane_command 'terminal')\" ]"
  run_test "get_pane_command missing pane is empty" "[ -z \"\$(get_pane_command 'nonexistent')\" ]"

  CONFIG_FILE="$_saved_cf"
  rm -rf "$PANE_TEST_DIR"
else
  skip_test "get_pane_command tests" "yq not installed"
fi

# =============================================================================
# build_ticket_prompt with custom template
# =============================================================================

section "Custom Ticket Prompt Tests"

# Override config_get to return a custom template
_real_config_get_stub() { echo "${2:-}"; }
config_get() {
  if [ "$1" = "ticket.prompt_template" ]; then
    echo 'Work on ticket {identifier} now. Branch: {identifier}-fix'
  else
    _real_config_get_stub "$@"
  fi
}

run_test "Custom prompt substitutes identifier" "[ \"\$(build_ticket_prompt 'PROJ-99')\" = 'Work on ticket PROJ-99 now. Branch: PROJ-99-fix' ]"

# Restore stub
config_get() { echo "${2:-}"; }

# =============================================================================
# Workspace Detection Tests
# =============================================================================

section "Workspace Detection Tests"

# detect_workspace_from_dir uses pwd, so we test by cd-ing
# First, create dirs that match the pattern
WORKSPACE_PREFIX="test-ws"

_orig_dir=$(pwd)

cd "$WORKSPACE_BASE/$WORKSPACE_PREFIX-2"
run_test "detect_workspace_from_dir finds ws 2" "[ '$(detect_workspace_from_dir)' = '2' ]"

cd "$WORKSPACE_BASE/$WORKSPACE_PREFIX-1"
run_test "detect_workspace_from_dir finds ws 1" "[ '$(detect_workspace_from_dir)' = '1' ]"

cd /tmp
run_test "detect_workspace_from_dir empty outside workspace" "[ -z '$(detect_workspace_from_dir)' ]"

cd "$_orig_dir"

# =============================================================================
# Cleanup
# =============================================================================

rm -rf "$WS_TEST_DIR"
