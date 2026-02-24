#!/usr/bin/env bash
# Tests for ticket command validation and URL parsing

# =============================================================================
# Ticket Command Validation Tests
# =============================================================================

section "Ticket Command Tests"

run_test "Ticket no args shows usage" "'$CRABTERM' ticket 2>&1 | grep -qE 'Usage.*crab ticket'"
run_test "Ticket rejects semicolon" "'$CRABTERM' ticket 'foo;bar' 2>&1 | grep -q 'Invalid ticket identifier'"
run_test "Ticket rejects spaces" "'$CRABTERM' ticket 'foo bar' 2>&1 | grep -q 'Invalid ticket identifier'"
run_test "Ticket rejects shell chars" "'$CRABTERM' ticket 'ENG\$(whoami)' 2>&1 | grep -q 'Invalid ticket identifier'"
run_test "Ticket rejects braces" "'$CRABTERM' ticket '{identifier}' 2>&1 | grep -q 'Invalid ticket identifier'"
run_test "Ticket rejects backtick" "'$CRABTERM' ticket '\`cmd\`' 2>&1 | grep -q 'Invalid ticket identifier'"
run_test "Ticket rejects pipe" "'$CRABTERM' ticket 'foo|bar' 2>&1 | grep -q 'Invalid ticket identifier'"
run_test "Ticket rejects ampersand" "'$CRABTERM' ticket 'foo&bar' 2>&1 | grep -q 'Invalid ticket identifier'"

run_test "Ticket accepts ENG-123" "'$CRABTERM' ticket ENG-123 2>&1 | grep -vq 'Invalid ticket identifier'"
run_test "Ticket accepts PROJ_42" "'$CRABTERM' ticket PROJ_42 2>&1 | grep -vq 'Invalid ticket identifier'"
run_test "Ticket accepts Linear URL" "'$CRABTERM' ticket 'https://linear.app/myteam/issue/ENG-123/some-title' 2>&1 | grep -vq 'Invalid ticket identifier'"

if has_yq; then
  run_test "ws ticket no id shows error" "'$CRABTERM' ws 1 ticket 2>&1 | grep -qE 'Ticket identifier required'"
  run_test "ws ticket rejects bad id" "'$CRABTERM' ws 1 ticket 'bad!id' 2>&1 | grep -q 'Invalid ticket identifier'"
  run_test "ws ticket accepts valid id" "'$CRABTERM' ws 1 ticket ENG-123 2>&1 | grep -vq 'Invalid ticket identifier'"
else
  skip_test "ws ticket tests" "yq not installed"
fi

# =============================================================================
# PR Command Tests
# =============================================================================

section "PR Command Tests"

run_test "PR no args shows usage" "'$CRABTERM' pr 2>&1 | grep -qE 'Usage.*crab pr'"

if has_yq; then
  run_test "ws pr no id shows error" "'$CRABTERM' ws 1 pr 2>&1 | grep -qE 'PR identifier required'"
else
  skip_test "ws pr tests" "yq not installed"
fi

# =============================================================================
# Lock/Unlock Command Tests (CLI-level, not functional)
# =============================================================================

section "Lock/Unlock CLI Tests"

run_test "Lock no workspace shows error" "'$CRABTERM' lock 2>&1 | grep -qE 'Cannot detect workspace'"
run_test "Unlock no workspace shows error" "'$CRABTERM' unlock 2>&1 | grep -qE 'Cannot detect workspace'"

# =============================================================================
# Ticket URL Parsing Tests (library-level)
# =============================================================================

section "Ticket URL Parsing Tests"

source "$LIB/common.sh"
source "$LIB/ticket.sh"

run_test "Parse plain identifier" "[ '$(parse_ticket_identifier 'ENG-123')' = 'ENG-123' ]"
run_test "Parse Linear URL" "[ '$(parse_ticket_identifier 'https://linear.app/myteam/issue/ENG-456/some-title')' = 'ENG-456' ]"
run_test "Parse Linear URL without slug" "[ '$(parse_ticket_identifier 'https://linear.app/myteam/issue/PROJ-789')' = 'PROJ-789' ]"
run_test "Non-Linear URL passes through" "[ '$(parse_ticket_identifier 'https://example.com/foo')' = 'https://example.com/foo' ]"
run_test "Parse identifier with underscore" "[ '$(parse_ticket_identifier 'PROJ_42')' = 'PROJ_42' ]"
run_test "Parse lowercase identifier" "[ '$(parse_ticket_identifier 'eng-100')' = 'eng-100' ]"
