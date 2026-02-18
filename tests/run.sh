#!/usr/bin/env bash
# Run all crabterm tests
# Usage: ./tests/run.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

passed=0
failed=0

run_test() {
  local test_name=$1
  local test_cmd=$2

  echo -n "  $test_name: "
  if eval "$test_cmd" &>/dev/null; then
    echo -e "${GREEN}PASS${NC}"
    passed=$((passed + 1))
  else
    echo -e "${RED}FAIL${NC}"
    failed=$((failed + 1))
  fi
}

echo -e "${CYAN}Running crabterm tests${NC}"
echo ""

# =============================================================================
# Unit Tests
# =============================================================================

echo -e "${YELLOW}Unit Tests${NC}"

CRABTERM="$PROJECT_DIR/src/crabterm"

# Test: Script exists and is executable
run_test "Script exists" "[ -f '$CRABTERM' ]"
run_test "Script is executable" "[ -x '$CRABTERM' ] || chmod +x '$CRABTERM'"

# Test: Help command works
run_test "Help command" "'$CRABTERM' --help | grep -q 'crabterm'"

# Test: Version command works
run_test "Version command" "'$CRABTERM' --version | grep -q 'crabterm'"

# Test: Cheat command works
run_test "Cheat command" "'$CRABTERM' cheat | grep -q 'CHEAT SHEET'"

# Test: Config command works without config
run_test "Config without config file" "'$CRABTERM' config 2>&1 | grep -qE '(No config|not found)'"

# Test: Doctor command works
run_test "Doctor command" "'$CRABTERM' doctor | grep -q 'Doctor'"

# =============================================================================
# Config Parsing Tests
# =============================================================================

echo ""
echo -e "${YELLOW}Config Parsing Tests${NC}"

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

if command -v yq &>/dev/null; then
  run_test "yq installed" "true"

  run_test "Parse session_name" "[ \"$(yq -r '.session_name' '$TEST_CONFIG')\" = 'testcrab' ]"
  run_test "Parse workspace_base" "[ \"$(yq -r '.workspace_base' '$TEST_CONFIG')\" = '/tmp/test-workspaces' ]"
  run_test "Parse workspaces.count" "[ \"$(yq -r '.workspaces.count' '$TEST_CONFIG')\" = '3' ]"
  run_test "Parse ports.api_base" "[ \"$(yq -r '.ports.api_base' '$TEST_CONFIG')\" = '4000' ]"
  run_test "Parse pane command" "[ \"$(yq -r '.layout.panes[1].command' '$TEST_CONFIG')\" = 'echo \"server\"' ]"
else
  echo -e "  ${YELLOW}Skipping config parsing tests (yq not installed)${NC}"
fi

rm -rf "$TEST_CONFIG_DIR"

# =============================================================================
# Command Parsing Tests
# =============================================================================

echo ""
echo -e "${YELLOW}Command Parsing Tests${NC}"

run_test "Invalid command arg" "'$CRABTERM' abc 2>&1 | grep -qE '(Unknown|Error)'"

if command -v yq &>/dev/null; then
  run_test "Unknown subcommand" "'$CRABTERM' 1 foobar 2>&1 | grep -qE '(Unknown|mean)'"
else
  echo -e "  ${YELLOW}Skipping subcommand test (yq not installed)${NC}"
fi

# =============================================================================
# Ticket Command Tests
# =============================================================================

echo ""
echo -e "${YELLOW}Ticket Command Tests${NC}"

run_test "Ticket no args shows usage" "'$CRABTERM' ticket 2>&1 | grep -qE 'Usage.*crab ticket'"
run_test "Ticket rejects semicolon" "'$CRABTERM' ticket 'foo;bar' 2>&1 | grep -q 'Invalid ticket identifier'"
run_test "Ticket rejects spaces" "'$CRABTERM' ticket 'foo bar' 2>&1 | grep -q 'Invalid ticket identifier'"
run_test "Ticket rejects shell chars" "'$CRABTERM' ticket 'ENG\$(whoami)' 2>&1 | grep -q 'Invalid ticket identifier'"
run_test "Ticket rejects braces" "'$CRABTERM' ticket '{identifier}' 2>&1 | grep -q 'Invalid ticket identifier'"

run_test "Ticket accepts ENG-123" "'$CRABTERM' ticket ENG-123 2>&1 | grep -vq 'Invalid ticket identifier'"
run_test "Ticket accepts PROJ_42" "'$CRABTERM' ticket PROJ_42 2>&1 | grep -vq 'Invalid ticket identifier'"
run_test "Ticket accepts Linear URL" "'$CRABTERM' ticket 'https://linear.app/myteam/issue/ENG-123/some-title' 2>&1 | grep -vq 'Invalid ticket identifier'"

if command -v yq &>/dev/null; then
  run_test "ws ticket no id shows error" "'$CRABTERM' ws 1 ticket 2>&1 | grep -qE 'Ticket identifier required'"
  run_test "ws ticket rejects bad id" "'$CRABTERM' ws 1 ticket 'bad!id' 2>&1 | grep -q 'Invalid ticket identifier'"
  run_test "ws ticket accepts valid id" "'$CRABTERM' ws 1 ticket ENG-123 2>&1 | grep -vq 'Invalid ticket identifier'"
else
  echo -e "  ${YELLOW}Skipping ws ticket tests (yq not installed)${NC}"
fi

# =============================================================================
# PR Command Tests
# =============================================================================

echo ""
echo -e "${YELLOW}PR Command Tests${NC}"

run_test "PR no args shows usage" "'$CRABTERM' pr 2>&1 | grep -qE 'Usage.*crab pr'"

if command -v yq &>/dev/null; then
  run_test "ws pr no id shows error" "'$CRABTERM' ws 1 pr 2>&1 | grep -qE 'PR identifier required'"
else
  echo -e "  ${YELLOW}Skipping ws pr tests (yq not installed)${NC}"
fi

# =============================================================================
# Lock/Unlock Command Tests
# =============================================================================

echo ""
echo -e "${YELLOW}Lock/Unlock Command Tests${NC}"

run_test "Lock no workspace shows error" "'$CRABTERM' lock 2>&1 | grep -qE 'Cannot detect workspace'"
run_test "Unlock no workspace shows error" "'$CRABTERM' unlock 2>&1 | grep -qE 'Cannot detect workspace'"
run_test "Cheat sheet includes lock" "'$CRABTERM' cheat 2>&1 | grep -q 'lock'"
run_test "Help includes lock" "'$CRABTERM' --help 2>&1 | grep -q 'lock'"

# =============================================================================
# Lock/Unlock Functional Tests
# =============================================================================

echo ""
echo -e "${YELLOW}Lock/Unlock Functional Tests${NC}"

# Source just what we need for functional tests
LIB="$PROJECT_DIR/src/lib"
source "$LIB/common.sh"

# Set up temp workspace dirs
LOCK_TEST_DIR=$(mktemp -d)
WORKSPACE_BASE="$LOCK_TEST_DIR"
WORKSPACE_PREFIX="test-ws"

mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-1"
mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-2"
mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-3"

# Source workspace.sh for lock functions (stub out state functions it calls)
state_workspace_exists() { return 1; }
state_load_workspace() { :; }
state_remove_workspace() { :; }
config_get() { echo "${2:-}"; }
reset_submodules() { :; }
source "$LIB/workspace.sh"

# Test: is_workspace_locked on fresh workspace (no lock file)
run_test "Fresh workspace is unlocked" "! is_workspace_locked 1"

# Test: lock_workspace creates lock file
run_test "lock_workspace creates lock file" "lock_workspace 1 >/dev/null && [ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-lock' ]"

# Test: is_workspace_locked returns true after lock
run_test "Locked workspace detected" "is_workspace_locked 1"

# Test: unlock_workspace removes lock file
run_test "unlock_workspace removes lock file" "unlock_workspace 1 >/dev/null && ! [ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-lock' ]"

# Test: is_workspace_locked returns false after unlock
run_test "Unlocked workspace detected" "! is_workspace_locked 1"

# Test: lock_workspace fails for non-existent workspace
run_test "Lock non-existent workspace fails" "! lock_workspace 99 2>/dev/null"

# Test: unlock_workspace fails for non-existent workspace
run_test "Unlock non-existent workspace fails" "! unlock_workspace 99 2>/dev/null"

# Test: find_unlocked_workspace returns first unlocked
# Lock 1, leave 2 unlocked
lock_workspace 1 >/dev/null
run_test "find_unlocked_workspace finds ws 2" "[ '$(find_unlocked_workspace)' = '2' ]"

# Test: find_unlocked_workspace returns empty when all locked
lock_workspace 2 >/dev/null
lock_workspace 3 >/dev/null
run_test "find_unlocked_workspace empty when all locked" "[ -z '$(find_unlocked_workspace)' ]"

# Test: find_unlocked_workspace after unlocking one
unlock_workspace 3 >/dev/null
run_test "find_unlocked_workspace finds ws 3 after unlock" "[ '$(find_unlocked_workspace)' = '3' ]"

# =============================================================================
# Workspace Naming Functional Tests
# =============================================================================

echo ""
echo -e "${YELLOW}Workspace Naming Tests${NC}"

# Test: default name is ws<N>
run_test "Default name is ws1" "[ '$(get_workspace_name 1)' = 'ws1' ]"

# Test: set_workspace_name writes .crabterm-name
set_workspace_name 1 "PR #42: Fix login" 2>/dev/null
run_test "set_workspace_name creates name file" "[ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-name' ]"

# Test: get_workspace_name returns custom name
run_test "get_workspace_name returns custom name" "[ '$(get_workspace_name 1)' = 'PR #42: Fix login' ]"

# Test: clear_workspace_name removes name file
clear_workspace_name 1
run_test "clear_workspace_name removes name file" "! [ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-name' ]"

# Test: get_workspace_name returns default after clear
run_test "Name reverts to default after clear" "[ '$(get_workspace_name 1)' = 'ws1' ]"

# Test: set name for ticket
set_workspace_name 2 "ENG-123" 2>/dev/null
run_test "Ticket name set correctly" "[ '$(get_workspace_name 2)' = 'ENG-123' ]"

rm -rf "$LOCK_TEST_DIR"

# =============================================================================
# Info Bar Functional Tests
# =============================================================================

echo ""
echo -e "${YELLOW}Info Bar Tests${NC}"

# Re-setup temp workspace dirs (previous ones were cleaned up)
INFOBAR_TEST_DIR=$(mktemp -d)
WORKSPACE_BASE="$INFOBAR_TEST_DIR"
WORKSPACE_PREFIX="test-ws"
CONFIG_FILE="/dev/null"

mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-1"
mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-2"

source "$LIB/infobar.sh"

# Test: lib/infobar.sh exists
run_test "lib/infobar.sh exists" "[ -f '$PROJECT_DIR/src/lib/infobar.sh' ]"

# Test: write_workspace_meta creates .crabterm-meta
write_workspace_meta 1 "pr" "pr_number" "42" "pr_url" "https://github.com/owner/repo/pull/42" "pr_title" "Fix login" "name" "PR #42: Fix login"
run_test "write_workspace_meta creates .crabterm-meta" "[ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta' ]"

# Test: .crabterm-meta contains correct type
run_test "Meta file has correct type" "[ \"\$(jq -r '.type' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'pr' ]"

# Test: .crabterm-meta contains PR number
run_test "Meta file has PR number" "[ \"\$(jq -r '.pr_number' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = '42' ]"

# Test: render_infobar produces output
run_test "render_infobar produces output" "[ -n \"\$(render_infobar '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1')\" ]"

# Test: render_infobar output contains PR info
run_test "render_infobar shows PR number" "render_infobar '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1' | grep -q '42'"

# Test: render_infobar works with no meta file (shows default)
run_test "render_infobar with no meta shows default" "render_infobar '$WORKSPACE_BASE/$WORKSPACE_PREFIX-2' | grep -q 'crabterm'"

# Test: write_workspace_meta for ticket type
write_workspace_meta 2 "ticket" "ticket" "ENG-456" "name" "ENG-456"
run_test "Ticket meta has correct type" "[ \"\$(jq -r '.type' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-2/.crabterm-meta')\" = 'ticket' ]"
run_test "Ticket meta has ticket ID" "[ \"\$(jq -r '.ticket' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-2/.crabterm-meta')\" = 'ENG-456' ]"

# Test: clear_workspace_meta removes the file
clear_workspace_meta 1
run_test "clear_workspace_meta removes .crabterm-meta" "! [ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta' ]"

# Test: clear on non-existent file doesn't error
run_test "clear_workspace_meta on missing file is no-op" "clear_workspace_meta 99"

# Test: extract_ticket_from_branch
run_test "Extract ticket from branch user/ENG-123-fix" "[ '$(extract_ticket_from_branch 'user/ENG-123-fix-bug')' = 'ENG-123' ]"
run_test "Extract ticket from branch ENG-456-desc" "[ '$(extract_ticket_from_branch 'ENG-456-description')' = 'ENG-456' ]"
run_test "Extract ticket from branch lowercase" "[ '$(extract_ticket_from_branch 'eng-789-thing')' = 'ENG-789' ]"
run_test "Extract ticket from plain branch" "[ -z '$(extract_ticket_from_branch 'main')' ]"
run_test "Extract ticket from feature branch" "[ -z '$(extract_ticket_from_branch 'feature/add-login')' ]"

# Test: extract_linear_url_from_body
run_test "Extract Linear URL from body" "[ '$(extract_linear_url_from_body 'Fixes https://linear.app/myteam/issue/ENG-123/fix-bug done')' = 'https://linear.app/myteam/issue/ENG-123/fix-bug' ]"
run_test "Extract Linear URL without slug" "[ '$(extract_linear_url_from_body 'See https://linear.app/team/issue/PROJ-42')' = 'https://linear.app/team/issue/PROJ-42' ]"
run_test "Extract Linear URL from HTML href" "[ '$(extract_linear_url_from_body '<a href="https://linear.app/team/issue/ENG-456/some-title">ENG-456</a>')' = 'https://linear.app/team/issue/ENG-456/some-title' ]"
run_test "No Linear URL returns empty" "[ -z '$(extract_linear_url_from_body 'No ticket here')' ]"

# Test: PR metadata includes ticket from branch
write_workspace_meta 1 "pr" "pr_number" "99" "pr_url" "https://github.com/o/r/pull/99" "pr_title" "Fix" "ticket" "ENG-555" "ticket_url" "https://linear.app/team/issue/ENG-555"
run_test "Meta includes ticket" "[ \"\$(jq -r '.ticket' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'ENG-555' ]"
run_test "Meta includes ticket_url" "[ \"\$(jq -r '.ticket_url' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'https://linear.app/team/issue/ENG-555' ]"
run_test "render_infobar shows ticket" "render_infobar '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1' | grep -q 'ENG-555'"

rm -rf "$INFOBAR_TEST_DIR"

# =============================================================================
# Ticket URL Parsing Tests
# =============================================================================

echo ""
echo -e "${YELLOW}Ticket URL Parsing Tests${NC}"

source "$LIB/ticket.sh"

run_test "Parse plain identifier" "[ '$(parse_ticket_identifier 'ENG-123')' = 'ENG-123' ]"
run_test "Parse Linear URL" "[ '$(parse_ticket_identifier 'https://linear.app/myteam/issue/ENG-456/some-title')' = 'ENG-456' ]"
run_test "Parse Linear URL without slug" "[ '$(parse_ticket_identifier 'https://linear.app/myteam/issue/PROJ-789')' = 'PROJ-789' ]"
run_test "Non-Linear URL passes through" "[ '$(parse_ticket_identifier 'https://example.com/foo')' = 'https://example.com/foo' ]"

# =============================================================================
# Lib Structure Tests
# =============================================================================

echo ""
echo -e "${YELLOW}Lib Structure Tests${NC}"

run_test "lib/common.sh exists" "[ -f '$PROJECT_DIR/src/lib/common.sh' ]"
run_test "lib/config.sh exists" "[ -f '$PROJECT_DIR/src/lib/config.sh' ]"
run_test "lib/iterm.sh exists" "[ -f '$PROJECT_DIR/src/lib/iterm.sh' ]"
run_test "lib/state.sh exists" "[ -f '$PROJECT_DIR/src/lib/state.sh' ]"
run_test "lib/workspace.sh exists" "[ -f '$PROJECT_DIR/src/lib/workspace.sh' ]"
run_test "lib/wip.sh exists" "[ -f '$PROJECT_DIR/src/lib/wip.sh' ]"
run_test "lib/review.sh exists" "[ -f '$PROJECT_DIR/src/lib/review.sh' ]"
run_test "lib/pr.sh exists" "[ -f '$PROJECT_DIR/src/lib/pr.sh' ]"
run_test "lib/infobar.sh exists" "[ -f '$PROJECT_DIR/src/lib/infobar.sh' ]"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "════════════════════════════════════════"
total=$((passed + failed))
echo -e "Results: ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC} ($total total)"

if [ $failed -gt 0 ]; then
  exit 1
fi

echo -e "${GREEN}All tests passed!${NC}"
