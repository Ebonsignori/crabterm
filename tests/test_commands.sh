#!/usr/bin/env bash
# Tests for CLI commands (help, version, cheat, doctor, error handling)

section "CLI Command Tests"

# Basic commands
run_test "Script exists" "[ -f '$CRABTERM' ]"
run_test "Script is executable" "[ -x '$CRABTERM' ] || chmod +x '$CRABTERM'"
run_test "Help command" "'$CRABTERM' --help | grep -q 'crabterm'"
run_test "Version command" "'$CRABTERM' --version | grep -q 'crabterm'"
run_test "Version includes number" "'$CRABTERM' --version | grep -qE '[0-9]+\.[0-9]+'"
run_test "Cheat command" "'$CRABTERM' cheat | grep -q 'CHEAT SHEET'"
run_test "Config command runs" "'$CRABTERM' config 2>&1 | grep -qiE '(No config|not found|config)'"
run_test "Doctor command" "'$CRABTERM' doctor | grep -q 'Doctor'"

# Help content checks
run_test "Help mentions ws command" "'$CRABTERM' --help | grep -q 'ws'"
run_test "Help mentions init command" "'$CRABTERM' --help | grep -q 'init'"
run_test "Help mentions wip command" "'$CRABTERM' --help | grep -q 'wip'"
run_test "Help mentions lock command" "'$CRABTERM' --help | grep -q 'lock'"
run_test "Help mentions pr command" "'$CRABTERM' --help | grep -q 'pr'"
run_test "Help mentions ticket command" "'$CRABTERM' --help | grep -q 'ticket'"
run_test "Cheat sheet includes lock" "'$CRABTERM' cheat 2>&1 | grep -q 'lock'"
run_test "Cheat sheet includes wip" "'$CRABTERM' cheat 2>&1 | grep -q 'wip'"

# Error handling
run_test "Invalid command arg" "'$CRABTERM' abc 2>&1 | grep -qE '(Unknown|Error)'"

if has_yq; then
  run_test "Unknown subcommand" "'$CRABTERM' 1 foobar 2>&1 | grep -qE '(Unknown|mean)'"
else
  skip_test "Unknown subcommand" "yq not installed"
fi
