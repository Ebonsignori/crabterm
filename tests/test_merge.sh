#!/usr/bin/env bash
# Tests for merge command

section "Merge Command Tests"

# Source checks
run_test "merge.sh exists" "[ -f '$LIB/merge.sh' ]"
run_test "merge.sh is sourceable" "bash -c 'source $LIB/common.sh && source $LIB/config.sh && source $LIB/worktree.sh && source $LIB/merge.sh'"
run_test "handle_merge_command defined" "bash -c 'source $LIB/common.sh && source $LIB/config.sh && source $LIB/worktree.sh && source $LIB/merge.sh && declare -f handle_merge_command >/dev/null'"
run_test "_resolve_conflicts_with_claude defined" "bash -c 'source $LIB/common.sh && source $LIB/config.sh && source $LIB/worktree.sh && source $LIB/merge.sh && declare -f _resolve_conflicts_with_claude >/dev/null'"
run_test "_merge_usage defined" "bash -c 'source $LIB/common.sh && source $LIB/config.sh && source $LIB/worktree.sh && source $LIB/merge.sh && declare -f _merge_usage >/dev/null'"

# Help/cheat integration
run_test "Help mentions merge command" "'$CRABTERM' --help | grep -q 'merge'"
run_test "Cheat sheet includes merge" "'$CRABTERM' cheat | grep -q 'MERGE COMMANDS'"
run_test "Cheat sheet merge dry-run" "'$CRABTERM' cheat | grep -q 'dry-run'"

# Command recognition (merge without config should fail with config error, not unknown command)
run_test "merge is recognized command" "! '$CRABTERM' merge 2>&1 | grep -q 'Unknown command'"
