#!/usr/bin/env bash
# Shared test utilities for crabterm tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIB="$PROJECT_DIR/src/lib"
CRABTERM="$PROJECT_DIR/src/crabterm"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

passed=0
failed=0
skipped=0

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

skip_test() {
  local test_name=$1
  local reason=${2:-"skipped"}
  echo -e "  $test_name: ${YELLOW}SKIP${NC} ($reason)"
  skipped=$((skipped + 1))
}

section() {
  echo ""
  echo -e "${YELLOW}$1${NC}"
}

has_yq() {
  command -v yq &>/dev/null
}

has_jq() {
  command -v jq &>/dev/null
}
