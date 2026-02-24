#!/usr/bin/env bash
# Tests for library file structure and integrity

section "Lib Structure Tests"

# All expected library files exist
run_test "lib/common.sh exists" "[ -f '$PROJECT_DIR/src/lib/common.sh' ]"
run_test "lib/config.sh exists" "[ -f '$PROJECT_DIR/src/lib/config.sh' ]"
run_test "lib/iterm.sh exists" "[ -f '$PROJECT_DIR/src/lib/iterm.sh' ]"
run_test "lib/state.sh exists" "[ -f '$PROJECT_DIR/src/lib/state.sh' ]"
run_test "lib/workspace.sh exists" "[ -f '$PROJECT_DIR/src/lib/workspace.sh' ]"
run_test "lib/worktree.sh exists" "[ -f '$PROJECT_DIR/src/lib/worktree.sh' ]"
run_test "lib/wip.sh exists" "[ -f '$PROJECT_DIR/src/lib/wip.sh' ]"
run_test "lib/review.sh exists" "[ -f '$PROJECT_DIR/src/lib/review.sh' ]"
run_test "lib/pr.sh exists" "[ -f '$PROJECT_DIR/src/lib/pr.sh' ]"
run_test "lib/infobar.sh exists" "[ -f '$PROJECT_DIR/src/lib/infobar.sh' ]"
run_test "lib/ports.sh exists" "[ -f '$PROJECT_DIR/src/lib/ports.sh' ]"
run_test "lib/ticket.sh exists" "[ -f '$PROJECT_DIR/src/lib/ticket.sh' ]"
run_test "lib/projects.sh exists" "[ -f '$PROJECT_DIR/src/lib/projects.sh' ]"
run_test "lib/session.sh exists" "[ -f '$PROJECT_DIR/src/lib/session.sh' ]"
run_test "lib/doctor.sh exists" "[ -f '$PROJECT_DIR/src/lib/doctor.sh' ]"
run_test "lib/help.sh exists" "[ -f '$PROJECT_DIR/src/lib/help.sh' ]"
run_test "lib/setup.sh exists" "[ -f '$PROJECT_DIR/src/lib/setup.sh' ]"
run_test "lib/init.sh exists" "[ -f '$PROJECT_DIR/src/lib/init.sh' ]"

# Main entry point
run_test "src/crabterm exists" "[ -f '$PROJECT_DIR/src/crabterm' ]"
run_test "src/crabterm is executable" "[ -x '$PROJECT_DIR/src/crabterm' ]"

# All lib files have bash shebang
section "Lib File Integrity Tests"

for lib_file in "$PROJECT_DIR"/src/lib/*.sh; do
  local_name=$(basename "$lib_file")
  run_test "$local_name has bash shebang" "head -1 '$lib_file' | grep -q '#!/usr/bin/env bash'"
done

# Example configs exist
run_test "examples/minimal.yaml exists" "[ -f '$PROJECT_DIR/examples/minimal.yaml' ]"

# Docs
run_test "README.md exists" "[ -f '$PROJECT_DIR/README.md' ]"
run_test "Makefile exists" "[ -f '$PROJECT_DIR/Makefile' ]"
