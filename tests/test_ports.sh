#!/usr/bin/env bash
# Tests for port management helper functions

source "$LIB/common.sh"
source "$LIB/ports.sh"

section "Port Helper Tests"

# =============================================================================
# _extract_port Tests
# =============================================================================

run_test "Extract port from plain number" "[ '$(_extract_port '3200')' = '3200' ]"
run_test "Extract port from URL" "[ '$(_extract_port 'http://localhost:3200')' = '3200' ]"
run_test "Extract port from https URL" "[ '$(_extract_port 'https://localhost:8443')' = '8443' ]"
run_test "Extract port from URL with path" "[ '$(_extract_port 'http://localhost:4000/api')' = '4000' ]"
run_test "Extract port empty for no port" "[ -z '$(_extract_port 'http://localhost')' ]"
run_test "Extract port empty for text" "[ -z '$(_extract_port 'foobar')' ]"
run_test "Extract port from 0.0.0.0:5000" "[ '$(_extract_port '0.0.0.0:5000')' = '5000' ]"
run_test "Extract port handles large port" "[ '$(_extract_port '65535')' = '65535' ]"

# =============================================================================
# _add_port Tests
# =============================================================================

_kill_ports=()
_add_port "3000"
run_test "_add_port adds first port" "[ '${_kill_ports[0]}' = '3000' ]"

_add_port "4000"
run_test "_add_port adds second port" "[ '${_kill_ports[1]}' = '4000' ]"
run_test "_add_port has 2 ports" "[ ${#_kill_ports[@]} -eq 2 ]"

_add_port "3000"
run_test "_add_port skips duplicate" "[ ${#_kill_ports[@]} -eq 2 ]"

_add_port ""
run_test "_add_port skips empty" "[ ${#_kill_ports[@]} -eq 2 ]"

_add_port "5000"
run_test "_add_port adds third port" "[ ${#_kill_ports[@]} -eq 3 ]"
run_test "_add_port third port correct" "[ '${_kill_ports[2]}' = '5000' ]"

# =============================================================================
# find_available_port Tests
# =============================================================================

section "Port Availability Tests"

# find_available_port should return the base port when nothing is listening
run_test "find_available_port returns base when free" "[ '$(find_available_port 59000)' = '59000' ]"
run_test "find_available_port returns base for high port" "[ '$(find_available_port 61000)' = '61000' ]"

# =============================================================================
# read_env_port Tests (with mocked config)
# =============================================================================

section "Read Env Port Tests"

if has_yq; then
  PORT_TEST_DIR=$(mktemp -d)
  PORT_CONFIG="$PORT_TEST_DIR/config.yaml"
  PORT_WS_DIR="$PORT_TEST_DIR/workspace"
  mkdir -p "$PORT_WS_DIR"

  # Config with env_sync pointing to a .env file
  cat > "$PORT_CONFIG" << 'PORTEOF'
env_sync:
  port_spacing: 10
  files:
    - path: .env
      port_var: API_PORT
      ports:
        - API_PORT
        - APP_PORT
PORTEOF

  _saved_cf="$CONFIG_FILE"
  CONFIG_FILE="$PORT_CONFIG"

  # Test: plain number port
  cat > "$PORT_WS_DIR/.env" << 'ENVEOF'
API_PORT=3200
APP_PORT=3000
OTHER_VAR=hello
ENVEOF

  run_test "read_env_port reads plain number" "[ '$(read_env_port "$PORT_WS_DIR" "api")' = '3200' ]"

  # Test: URL-style port value
  cat > "$PORT_WS_DIR/.env" << 'ENVEOF'
API_PORT=http://localhost:4200
APP_PORT=5000
ENVEOF

  run_test "read_env_port reads URL port" "[ '$(read_env_port "$PORT_WS_DIR" "api")' = '4200' ]"

  # Test: no .env file
  rm "$PORT_WS_DIR/.env"
  run_test "read_env_port empty with no .env" "[ -z '$(read_env_port "$PORT_WS_DIR" "api")' ]"

  # Test: .env exists but port_var not present
  cat > "$PORT_WS_DIR/.env" << 'ENVEOF'
UNRELATED_VAR=foo
ENVEOF

  run_test "read_env_port empty when var missing" "[ -z '$(read_env_port "$PORT_WS_DIR" "api")' ]"

  # Test: port_var with spaces/quotes
  cat > "$PORT_WS_DIR/.env" << 'ENVEOF'
API_PORT= 3300
ENVEOF

  run_test "read_env_port strips spaces" "[ '$(read_env_port "$PORT_WS_DIR" "api")' = '3300' ]"

  CONFIG_FILE="$_saved_cf"
  rm -rf "$PORT_TEST_DIR"
else
  skip_test "read_env_port tests" "yq not installed"
fi
