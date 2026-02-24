#!/usr/bin/env bash
# Tests for workspace state persistence (save/load/remove)

section "State Persistence Tests"

source "$LIB/common.sh"

STATE_TEST_DIR=$(mktemp -d)
CONFIG_DIR="$STATE_TEST_DIR"

# Stub iterm_session_exists (always return false for state_workspace_exists)
iterm_session_exists() { return 1; }

source "$LIB/state.sh"

# =============================================================================
# state_save_workspace Tests
# =============================================================================

state_save_workspace "testsession" "1" "win-123" "tab-456" "term-sid" "srv-sid" "main-sid" "info-sid"

STATE_FILE="$STATE_TEST_DIR/state/testsession/ws1.json"

run_test "state_save creates state dir" "[ -d '$STATE_TEST_DIR/state/testsession' ]"
run_test "state_save creates json file" "[ -f '$STATE_FILE' ]"

if has_jq; then
  run_test "state file has workspace number" "[ \"\$(jq -r '.workspace' '$STATE_FILE')\" = '1' ]"
  run_test "state file has window_id" "[ \"\$(jq -r '.window_id' '$STATE_FILE')\" = 'win-123' ]"
  run_test "state file has tab_id" "[ \"\$(jq -r '.tab_id' '$STATE_FILE')\" = 'tab-456' ]"
  run_test "state file has terminal pane" "[ \"\$(jq -r '.panes.terminal' '$STATE_FILE')\" = 'term-sid' ]"
  run_test "state file has server pane" "[ \"\$(jq -r '.panes.server' '$STATE_FILE')\" = 'srv-sid' ]"
  run_test "state file has main pane" "[ \"\$(jq -r '.panes.main' '$STATE_FILE')\" = 'main-sid' ]"
  run_test "state file has info pane" "[ \"\$(jq -r '.panes.info' '$STATE_FILE')\" = 'info-sid' ]"
  run_test "state file has created_at" "[ -n \"\$(jq -r '.created_at' '$STATE_FILE')\" ]"
else
  skip_test "state file content tests" "jq not installed"
fi

# =============================================================================
# state_load_workspace Tests
# =============================================================================

state_load_workspace "testsession" "1"
run_test "state_load sets WS_WINDOW_ID" "[ '$WS_WINDOW_ID' = 'win-123' ]"
run_test "state_load sets WS_TAB_ID" "[ '$WS_TAB_ID' = 'tab-456' ]"
run_test "state_load sets WS_TERMINAL_SID" "[ '$WS_TERMINAL_SID' = 'term-sid' ]"
run_test "state_load sets WS_SERVER_SID" "[ '$WS_SERVER_SID' = 'srv-sid' ]"
run_test "state_load sets WS_MAIN_SID" "[ '$WS_MAIN_SID' = 'main-sid' ]"
run_test "state_load sets WS_INFO_SID" "[ '$WS_INFO_SID' = 'info-sid' ]"

run_test "state_load missing file returns 1" "! state_load_workspace 'testsession' '99'"

# =============================================================================
# state_save without info pane
# =============================================================================

state_save_workspace "testsession" "2" "win-A" "tab-B" "t-sid" "s-sid" "m-sid"

if has_jq; then
  STATE_FILE2="$STATE_TEST_DIR/state/testsession/ws2.json"
  run_test "state without info pane has empty info" "[ \"\$(jq -r '.panes.info' '$STATE_FILE2')\" = '' ]"
fi

# =============================================================================
# state_list_workspaces Tests
# =============================================================================

run_test "state_list finds ws1" "state_list_workspaces 'testsession' | grep -q '1'"
run_test "state_list finds ws2" "state_list_workspaces 'testsession' | grep -q '2'"
run_test "state_list empty for unknown session" "[ -z \"\$(state_list_workspaces 'nosuchsession')\" ]"

# =============================================================================
# state_remove_workspace Tests
# =============================================================================

state_remove_workspace "testsession" "1"
run_test "state_remove deletes file" "! [ -f '$STATE_TEST_DIR/state/testsession/ws1.json' ]"
run_test "state_load after remove returns 1" "! state_load_workspace 'testsession' '1'"

# Removing non-existent is a no-op
run_test "state_remove non-existent is no-op" "state_remove_workspace 'testsession' '99'"

# =============================================================================
# state_workspace_exists Tests (with stubbed iterm_session_exists)
# =============================================================================

# iterm_session_exists always returns 1 (false), so state_workspace_exists
# should return false even if file exists, and clean up the stale state
state_save_workspace "testsession" "3" "w" "t" "term" "srv" "main"
run_test "state_workspace_exists false when iterm dead" "! state_workspace_exists 'testsession' '3'"
run_test "state_workspace_exists cleans stale state" "! [ -f '$STATE_TEST_DIR/state/testsession/ws3.json' ]"

# =============================================================================
# Cleanup
# =============================================================================

rm -rf "$STATE_TEST_DIR"
