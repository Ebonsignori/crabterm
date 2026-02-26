#!/usr/bin/env bash
# Run all crabterm tests
# Usage: ./tests/run.sh [test_name...]
#
# Run all tests:  ./tests/run.sh
# Run specific:   ./tests/run.sh commands workspace
# List available:  ./tests/run.sh --list

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared test helpers
source "$SCRIPT_DIR/helpers.sh"

# Available test files (order matters: some source libs that affect later tests)
TEST_FILES=(
  test_commands
  test_config
  test_workspace
  test_infobar
  test_ticket
  test_ports
  test_projects
  test_state
  test_session
  test_merge
  test_structure
)

# Handle --list flag
if [ "${1:-}" = "--list" ]; then
  echo "Available test suites:"
  for t in "${TEST_FILES[@]}"; do
    echo "  $t"
  done
  exit 0
fi

echo -e "${CYAN}Running crabterm tests${NC}"

# If arguments given, run only those test files
if [ $# -gt 0 ]; then
  selected=()
  for arg in "$@"; do
    # Allow both "commands" and "test_commands"
    name="${arg#test_}"
    file="$SCRIPT_DIR/test_${name}.sh"
    if [ -f "$file" ]; then
      selected+=("test_${name}")
    else
      echo -e "${RED}Unknown test suite: $arg${NC}"
      echo "Run '$0 --list' to see available suites."
      exit 1
    fi
  done
  TEST_FILES=("${selected[@]}")
fi

# Run each test file
for test_file in "${TEST_FILES[@]}"; do
  source "$SCRIPT_DIR/${test_file}.sh"
done

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "════════════════════════════════════════"
total=$((passed + failed + skipped))
echo -e "Results: ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}, ${YELLOW}$skipped skipped${NC} ($total total)"

if [ $failed -gt 0 ]; then
  exit 1
fi

echo -e "${GREEN}All tests passed!${NC}"
