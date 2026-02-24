#!/usr/bin/env bash
# Tests for info bar metadata, rendering, ticket/URL extraction

# =============================================================================
# Setup
# =============================================================================

source "$LIB/common.sh"

INFOBAR_TEST_DIR=$(mktemp -d)
WORKSPACE_BASE="$INFOBAR_TEST_DIR"
WORKSPACE_PREFIX="test-ws"
CONFIG_FILE="/dev/null"

mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-1"
mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-2"
mkdir -p "$WORKSPACE_BASE/$WORKSPACE_PREFIX-3"

source "$LIB/infobar.sh"

# =============================================================================
# write_workspace_meta Tests
# =============================================================================

section "Info Bar Meta Tests"

run_test "lib/infobar.sh exists" "[ -f '$PROJECT_DIR/src/lib/infobar.sh' ]"

# PR metadata
write_workspace_meta 1 "pr" "pr_number" "42" "pr_url" "https://github.com/owner/repo/pull/42" "pr_title" "Fix login" "name" "PR #42: Fix login"
run_test "write_workspace_meta creates .crabterm-meta" "[ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta' ]"
run_test "Meta file has correct type" "[ \"\$(jq -r '.type' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'pr' ]"
run_test "Meta file has PR number" "[ \"\$(jq -r '.pr_number' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = '42' ]"
run_test "Meta file has PR URL" "[ \"\$(jq -r '.pr_url' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'https://github.com/owner/repo/pull/42' ]"
run_test "Meta file has PR title" "[ \"\$(jq -r '.pr_title' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'Fix login' ]"
run_test "Meta file has name" "[ \"\$(jq -r '.name' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'PR #42: Fix login' ]"

# Ticket metadata
write_workspace_meta 2 "ticket" "ticket" "ENG-456" "name" "ENG-456"
run_test "Ticket meta has correct type" "[ \"\$(jq -r '.type' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-2/.crabterm-meta')\" = 'ticket' ]"
run_test "Ticket meta has ticket ID" "[ \"\$(jq -r '.ticket' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-2/.crabterm-meta')\" = 'ENG-456' ]"
run_test "Ticket meta has name" "[ \"\$(jq -r '.name' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-2/.crabterm-meta')\" = 'ENG-456' ]"

# Overwrite metadata
write_workspace_meta 1 "ticket" "ticket" "PROJ-789" "name" "PROJ-789"
run_test "Overwritten meta has new type" "[ \"\$(jq -r '.type' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'ticket' ]"
run_test "Overwritten meta has new ticket" "[ \"\$(jq -r '.ticket' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'PROJ-789' ]"
run_test "Overwritten meta lost old PR field" "[ \"\$(jq -r '.pr_number // \"none\"' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'none' ]"

# PR + ticket metadata
write_workspace_meta 1 "pr" "pr_number" "99" "pr_url" "https://github.com/o/r/pull/99" "pr_title" "Fix" "ticket" "ENG-555" "ticket_url" "https://linear.app/team/issue/ENG-555"
run_test "Meta includes ticket" "[ \"\$(jq -r '.ticket' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'ENG-555' ]"
run_test "Meta includes ticket_url" "[ \"\$(jq -r '.ticket_url' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = 'https://linear.app/team/issue/ENG-555' ]"
run_test "Meta includes pr_number" "[ \"\$(jq -r '.pr_number' '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta')\" = '99' ]"

# =============================================================================
# render_infobar Tests
# =============================================================================

section "Info Bar Rendering Tests"

run_test "render_infobar produces output" "[ -n \"\$(render_infobar '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1')\" ]"
run_test "render_infobar shows PR number" "render_infobar '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1' | grep -q '99'"
run_test "render_infobar shows ticket" "render_infobar '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1' | grep -q 'ENG-555'"
run_test "render_infobar with no meta shows default" "render_infobar '$WORKSPACE_BASE/$WORKSPACE_PREFIX-3' | grep -q 'crabterm'"

# Render ticket-only workspace
run_test "render_infobar for ticket workspace" "render_infobar '$WORKSPACE_BASE/$WORKSPACE_PREFIX-2' | grep -q 'ENG-456'"

# =============================================================================
# clear_workspace_meta Tests
# =============================================================================

section "Info Bar Clear Tests"

clear_workspace_meta 1
run_test "clear_workspace_meta removes .crabterm-meta" "! [ -f '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1/.crabterm-meta' ]"
run_test "clear_workspace_meta on missing file is no-op" "clear_workspace_meta 99"
run_test "render_infobar after clear shows default" "render_infobar '$WORKSPACE_BASE/$WORKSPACE_PREFIX-1' | grep -q 'crabterm'"

# =============================================================================
# extract_ticket_from_branch Tests
# =============================================================================

section "Ticket Extraction Tests"

run_test "Extract ticket from user/ENG-123-fix" "[ '$(extract_ticket_from_branch 'user/ENG-123-fix-bug')' = 'ENG-123' ]"
run_test "Extract ticket from ENG-456-desc" "[ '$(extract_ticket_from_branch 'ENG-456-description')' = 'ENG-456' ]"
run_test "Extract ticket from lowercase" "[ '$(extract_ticket_from_branch 'eng-789-thing')' = 'ENG-789' ]"
run_test "Extract ticket from plain branch" "[ -z '$(extract_ticket_from_branch 'main')' ]"
run_test "Extract ticket from feature branch" "[ -z '$(extract_ticket_from_branch 'feature/add-login')' ]"
run_test "Extract ticket from PROJ-42-branch" "[ '$(extract_ticket_from_branch 'PROJ-42-some-feature')' = 'PROJ-42' ]"
run_test "Extract ticket from nested prefix" "[ '$(extract_ticket_from_branch 'fix/team/ABC-1-desc')' = 'ABC-1' ]"
run_test "No ticket from numeric-only branch" "[ -z '$(extract_ticket_from_branch '123-fix')' ]"
run_test "No ticket from release branch" "[ -z '$(extract_ticket_from_branch 'release/v2.0')' ]"

# =============================================================================
# extract_linear_url_from_body Tests
# =============================================================================

section "Linear URL Extraction Tests"

run_test "Extract Linear URL from body" "[ '$(extract_linear_url_from_body 'Fixes https://linear.app/myteam/issue/ENG-123/fix-bug done')' = 'https://linear.app/myteam/issue/ENG-123/fix-bug' ]"
run_test "Extract Linear URL without slug" "[ '$(extract_linear_url_from_body 'See https://linear.app/team/issue/PROJ-42')' = 'https://linear.app/team/issue/PROJ-42' ]"
run_test "Extract Linear URL from HTML href" "[ '$(extract_linear_url_from_body '<a href="https://linear.app/team/issue/ENG-456/some-title">ENG-456</a>')' = 'https://linear.app/team/issue/ENG-456/some-title' ]"
run_test "No Linear URL returns empty" "[ -z '$(extract_linear_url_from_body 'No ticket here')' ]"
run_test "No Linear URL from github" "[ -z '$(extract_linear_url_from_body 'https://github.com/owner/repo')' ]"
run_test "Extract URL from multiline body" "[ '$(extract_linear_url_from_body 'Line 1
https://linear.app/t/issue/X-1/foo
Line 3')' = 'https://linear.app/t/issue/X-1/foo' ]"

# =============================================================================
# Cleanup
# =============================================================================

rm -rf "$INFOBAR_TEST_DIR"
