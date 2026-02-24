#!/usr/bin/env bash
# Tests for session management (create, get, update, list)

section "Session Management Tests"

source "$LIB/common.sh"

SESSION_TEST_DIR=$(mktemp -d)
CONFIG_DIR="$SESSION_TEST_DIR"
SESSIONS_DIR="$CONFIG_DIR/sessions"
PROJECT_ALIAS=""

# Stub functions session.sh depends on
iterm_session_exists() { return 1; }
iterm_focus_session() { :; }
iterm_send_interrupt() { :; }
iterm_send_text() { :; }

source "$LIB/session.sh"

# =============================================================================
# get_sessions_dir Tests
# =============================================================================

PROJECT_ALIAS=""
run_test "get_sessions_dir defaults to 'default'" "[ '$(get_sessions_dir)' = '$SESSIONS_DIR/default' ]"

PROJECT_ALIAS="myproject"
run_test "get_sessions_dir uses project alias" "[ '$(get_sessions_dir)' = '$SESSIONS_DIR/myproject' ]"

PROJECT_ALIAS=""

# =============================================================================
# session_create Tests
# =============================================================================

if has_yq; then
  session_dir=$(session_create "test-session" "Some context here")
  run_test "session_create returns directory path" "[ -d '$session_dir' ]"
  run_test "session_create creates session.yaml" "[ -f '$session_dir/session.yaml' ]"
  run_test "session_create creates context.md" "[ -f '$session_dir/context.md' ]"
  run_test "session context has correct content" "grep -q 'Some context here' '$session_dir/context.md'"
  run_test "session.yaml has name" "yq -r '.name' '$session_dir/session.yaml' | grep -q 'test-session'"
  run_test "session.yaml has created timestamp" "yq -r '.created' '$session_dir/session.yaml' | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}'"
  run_test "session.yaml has type" "[ \"\$(yq -r '.type' '$session_dir/session.yaml')\" = 'general' ]"

  # session_create fails on duplicate
  run_test "session_create rejects duplicate" "! session_create 'test-session' 2>/dev/null"

  # session_create without context
  session_dir2=$(session_create "no-context-session")
  run_test "session_create without context succeeds" "[ -d '$session_dir2' ]"
  run_test "session_create without context has no context.md" "! [ -f '$session_dir2/context.md' ]"

  # =============================================================================
  # session_get / session_update Tests
  # =============================================================================

  section "Session Get/Update Tests"

  run_test "session_get returns name" "[ '$(session_get 'test-session' 'name')' = 'test-session' ]"
  run_test "session_get returns type" "[ '$(session_get 'test-session' 'type')' = 'general' ]"
  run_test "session_get missing session fails" "! session_get 'nonexistent' 'name' 2>/dev/null"

  session_update "test-session" "summary" "My test summary"
  run_test "session_update changes field" "[ '$(session_get 'test-session' 'summary')' = 'My test summary' ]"

  session_update "test-session" "type" "review"
  run_test "session_update changes type" "[ '$(session_get 'test-session' 'type')' = 'review' ]"

  run_test "session_update missing session fails" "! session_update 'nonexistent' 'summary' 'foo' 2>/dev/null"

else
  skip_test "Session management tests" "yq not installed"
fi

# =============================================================================
# Cleanup
# =============================================================================

rm -rf "$SESSION_TEST_DIR"
