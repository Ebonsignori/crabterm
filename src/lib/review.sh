#!/usr/bin/env bash
# crabterm - PR review and court review commands

# =============================================================================
# Review Commands (Sugar for Sessions)
# =============================================================================

# Parse PR identifier: number, repo#number, or full URL
# Returns: owner repo number
parse_pr_identifier() {
  local pr_id="$1"
  local owner=""
  local repo=""
  local number=""

  if [[ "$pr_id" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    # Full URL
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    number="${BASH_REMATCH[3]}"
  elif [[ "$pr_id" =~ ^([^#]+)#([0-9]+)$ ]]; then
    # repo#number format (submodule)
    repo="${BASH_REMATCH[1]}"
    number="${BASH_REMATCH[2]}"
    # Try to get owner from git remote
    owner=$(git remote get-url origin 2>/dev/null | sed -n 's|.*github\.com[:/]\([^/]*\)/.*|\1|p')
  elif [[ "$pr_id" =~ ^[0-9]+$ ]]; then
    # Just a number - use current project's main repo
    number="$pr_id"
    if [ -n "$MAIN_REPO" ]; then
      local remote_url=$(cd "$MAIN_REPO" && git remote get-url origin 2>/dev/null)
      if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
      fi
    fi
  fi

  echo "$owner $repo $number"
}

# Get court review instructions for the judge pattern
get_court_instructions() {
  cat << 'COURT_EOF'

## Court Review Protocol

You are the **JUDGE** in a code review court. You will orchestrate a Claude reviewer and collect testimony from the Codex reviewer running in the adjacent pane, then deliver a final verdict.

### Your Role as Judge:
- **Orchestrate** the review process
- **Verify** all findings by tracing to actual code
- **Investigate** when reviewers disagree
- **Synthesize** a final verdict with zero false positives

### Phase 1: Empanel the Reviewers

**Reviewer A (Claude):** Spawn a Claude reviewer agent:
```
Use Task tool:
  subagent_type: "general-purpose"
  prompt: "You are Reviewer A. Review this PR for bugs, security issues, and code quality. Be thorough but avoid false positives. Structure findings as Critical/Warning/Suggestion with file:line references. Here is the context: [include PR diff]"
```

**Reviewer B (Codex):** Already running in the adjacent pane. It will save its findings to `codex-review.md` in the current directory when done. If Codex is not available, proceed with Reviewer A only.

Wait for Reviewer A to complete. Then check if `codex-review.md` exists (poll with the Read tool every ~30 seconds, up to 5 minutes). If it appears, read it. If it doesn't appear in time, proceed with Reviewer A's findings only.

### Phase 2: Collect Testimony

Document what each reviewer found:
- List Reviewer A's findings
- List Reviewer B's findings (from `codex-review.md`, if available)
- Note agreements and disagreements

### Phase 3: Verify & Investigate

For EACH finding from either reviewer:

1. **Trace to code**: Use Read tool to examine the actual file and line
2. **Verify the issue**: Is this a real problem or false positive?
3. **Check context**: Does surrounding code explain/mitigate it?
4. **When reviewers disagree**: Investigate deeper, examine edge cases

**Critical Rule**: Do NOT include any finding you haven't personally verified in the code.

### Phase 4: Deliberate

For each potential issue, document:
- What was claimed
- What you found when you traced the code
- Your ruling: CONFIRMED / DISMISSED / NEEDS-INVESTIGATION
- Reasoning

### Phase 5: Final Verdict

Write `review-output.md` with:

```markdown
# Court Review: PR #XXXX

## Verdict Summary
[1-2 sentence overall assessment]

## Confirmed Issues
[Issues verified by tracing code - include file:line and evidence]

## Dismissed Claims
[What reviewers flagged but you determined were false positives - explain why]

## Recommendations
[Actionable next steps]

## Court Record
[Summary of the review process, who found what, how disagreements were resolved]
```

### Rules of the Court:
1. **No false positives**: Only confirm what you've verified in the code
2. **Show your work**: Document how you verified each finding
3. **Be thorough**: Check edge cases, error paths, security implications
4. **Cite evidence**: Every confirmed issue needs file:line proof
5. **Explain dismissals**: If you reject a reviewer's finding, say why
COURT_EOF
}

# Filter a file list by review.ignore_files patterns
# Reads patterns from config, removes matching files
# Returns: filtered file list on stdout, sets _IGNORED_COUNT
_filter_file_list() {
  local file_list="$1"
  _IGNORED_COUNT=0

  # Read ignore patterns from config
  local patterns=()
  if [ -f "${CONFIG_FILE:-}" ]; then
    while IFS= read -r pattern; do
      [ -n "$pattern" ] && patterns+=("$pattern")
    done < <(yq -r '.review.ignore_files // [] | .[]' "$CONFIG_FILE" 2>/dev/null)
  fi

  # No patterns? Return as-is
  if [ ${#patterns[@]} -eq 0 ]; then
    echo "$file_list"
    return
  fi

  local filtered=""
  while IFS= read -r filepath; do
    [ -z "$filepath" ] && continue
    local basename="${filepath##*/}"
    local skip=false
    for pattern in "${patterns[@]}"; do
      # shellcheck disable=SC2254
      if [[ "$basename" == $pattern ]]; then
        skip=true
        break
      fi
    done
    if [ "$skip" = true ]; then
      _IGNORED_COUNT=$((_IGNORED_COUNT + 1))
    else
      filtered+="$filepath"$'\n'
    fi
  done <<< "$file_list"

  # Remove trailing newline
  echo -n "$filtered"
}

# Filter a unified diff by review.ignore_files patterns
# Removes entire file sections where the path matches an ignore pattern
_filter_diff() {
  local diff="$1"

  # Read ignore patterns from config
  local patterns=()
  if [ -f "${CONFIG_FILE:-}" ]; then
    while IFS= read -r pattern; do
      [ -n "$pattern" ] && patterns+=("$pattern")
    done < <(yq -r '.review.ignore_files // [] | .[]' "$CONFIG_FILE" 2>/dev/null)
  fi

  # No patterns? Return as-is
  if [ ${#patterns[@]} -eq 0 ]; then
    echo "$diff"
    return
  fi

  local output=""
  local skip=false
  while IFS= read -r line; do
    # Check for new file section
    if [[ "$line" == diff\ --git\ * ]]; then
      # Extract file path from "diff --git a/path b/path"
      local filepath="${line#diff --git a/}"
      filepath="${filepath%% b/*}"
      local basename="${filepath##*/}"
      skip=false
      for pattern in "${patterns[@]}"; do
        # shellcheck disable=SC2254
        if [[ "$basename" == $pattern ]]; then
          skip=true
          break
        fi
      done
    fi
    if [ "$skip" = false ]; then
      output+="$line"$'\n'
    fi
  done <<< "$diff"

  # Remove trailing newline
  echo -n "$output"
}

# Fetch PR data using gh CLI
# mode: "standard" (default) or "court"
fetch_pr_data() {
  local owner="$1"
  local repo="$2"
  local number="$3"
  local mode="${4:-standard}"

  if ! command_exists gh; then
    error "gh CLI required for PR reviews"
    echo "Install: brew install gh"
    return 1
  fi

  local full_repo="$owner/$repo"

  echo -e "${CYAN}Fetching PR #$number from $full_repo...${NC}"

  # Get PR metadata
  local pr_json=$(gh pr view "$number" --repo "$full_repo" --json title,body,headRefName,baseRefName,additions,deletions,changedFiles,url 2>/dev/null)
  if [ -z "$pr_json" ]; then
    error "Could not fetch PR #$number from $full_repo"
    return 1
  fi

  local title=$(echo "$pr_json" | jq -r '.title')
  local additions=$(echo "$pr_json" | jq -r '.additions')
  local deletions=$(echo "$pr_json" | jq -r '.deletions')
  local files=$(echo "$pr_json" | jq -r '.changedFiles')
  local url=$(echo "$pr_json" | jq -r '.url')

  echo -e "  Title: ${BOLD}$title${NC}"
  echo -e "  Files: $files (+$additions / -$deletions)"
  echo ""

  # Get diff and file list
  local diff=$(gh pr diff "$number" --repo "$full_repo" 2>/dev/null)
  local file_list=$(gh pr diff "$number" --repo "$full_repo" --name-only 2>/dev/null)

  # Filter ignored files from review
  _IGNORED_COUNT=0
  file_list=$(_filter_file_list "$file_list")
  local ignored_count=$_IGNORED_COUNT
  diff=$(_filter_diff "$diff")

  if [ "$ignored_count" -gt 0 ]; then
    echo -e "  ${GRAY}Filtered $ignored_count ignored file(s) from review${NC}"
  fi

  # Get instructions based on mode
  local instructions=""
  if [ "$mode" = "court" ]; then
    instructions=$(get_court_instructions)
  else
    instructions="## Instructions
Review this PR. Analyze the changes and:
1. First, propose logical review areas (group related files)
2. Wait for my approval on the areas
3. Then review each area, providing specific findings with file paths and line numbers
4. Generate a summary with actionable feedback
5. **IMPORTANT:** When done, save your complete review findings to \`review-output.md\` in the current directory. Include all issues found, suggestions, and your overall assessment."
  fi

  # Build ignored files note
  local ignored_note=""
  if [ "$ignored_count" -gt 0 ]; then
    ignored_note="- **Filtered:** $ignored_count file(s) excluded by review.ignore_files"
  fi

  # Return as structured output
  cat << EOF
# PR Review Context

## PR Information
- **Number:** #$number
- **Repository:** $full_repo
- **Title:** $title
- **URL:** $url
- **Changes:** $files files (+$additions / -$deletions)
${ignored_note:+$ignored_note}

## Files Changed
\`\`\`
$file_list
\`\`\`

$instructions

## Diff
\`\`\`diff
$diff
\`\`\`
EOF
}

# Extract ticket info from a PR (branch name, body, comments)
# Sets globals: _TICKET_ID, _TICKET_URL
_extract_pr_ticket_info() {
  local owner="$1"
  local repo="$2"
  local number="$3"
  local full_repo="$owner/$repo"

  _TICKET_ID=""
  _TICKET_URL=""

  local pr_extra
  pr_extra=$(gh pr view "$number" --repo "$full_repo" --json headRefName,body,comments 2>/dev/null)
  [ -n "$pr_extra" ] || return 0

  local branch
  branch=$(echo "$pr_extra" | jq -r '.headRefName // ""')
  [ -n "$branch" ] && _TICKET_ID=$(extract_ticket_from_branch "$branch")

  _TICKET_URL=$(extract_linear_url_from_body "$(echo "$pr_extra" | jq -r '.body // ""')")

  # Fall back to PR comments (Linear bot often comments with ticket link)
  if [ -z "$_TICKET_URL" ]; then
    local comments
    comments=$(echo "$pr_extra" | jq -r '[.comments[].body // empty] | join("\n")')
    [ -n "$comments" ] && _TICKET_URL=$(extract_linear_url_from_body "$comments")
  fi

  # If we found a URL but no ticket ID from branch, extract from the URL
  if [ -z "$_TICKET_ID" ] && [ -n "$_TICKET_URL" ]; then
    _TICKET_ID=$(echo "$_TICKET_URL" | grep -oE '/[A-Z][A-Z0-9_]*-[0-9]+' | head -1 | tr -d '/')
  fi
}

# Start a new review - interactive mode
review_new_interactive() {
  echo -e "${BOLD}Creating new review session${NC}"
  echo ""

  # Get session name
  local name=""
  read -p "Session name: " name
  [ -z "$name" ] && { error "Name required"; return 1; }

  # Collect PRs
  local prs=()
  echo ""
  echo "Add PRs (empty line when done):"
  while true; do
    read -p "> " pr_input
    [ -z "$pr_input" ] && break
    prs+=("$pr_input")
  done

  if [ ${#prs[@]} -eq 0 ]; then
    error "At least one PR required"
    return 1
  fi

  # Collect context
  echo ""
  echo "Context (optional, empty line when done):"
  local context_lines=()
  while true; do
    read -p "> " context_line
    [ -z "$context_line" ] && break
    context_lines+=("$context_line")
  done

  # Build context document
  local context="# Review Session: $name"$'\n\n'

  # Add user context if provided
  if [ ${#context_lines[@]} -gt 0 ]; then
    context+="## Context"$'\n'
    for line in "${context_lines[@]}"; do
      context+="$line"$'\n'
    done
    context+=$'\n'
  fi

  # Fetch and append PR data
  context+="## Pull Requests"$'\n\n'

  for pr_id in "${prs[@]}"; do
    local parsed=($(parse_pr_identifier "$pr_id"))
    local owner="${parsed[0]}"
    local repo="${parsed[1]}"
    local number="${parsed[2]}"

    if [ -z "$number" ]; then
      warn "Could not parse PR: $pr_id"
      continue
    fi

    local pr_data=$(fetch_pr_data "$owner" "$repo" "$number")
    context+="$pr_data"$'\n\n'
    context+="---"$'\n\n'
  done

  # Create session
  local sessions_dir=$(get_sessions_dir)
  local session_dir="$sessions_dir/$name"
  mkdir -p "$session_dir"

  # Write session metadata
  cat > "$session_dir/session.yaml" << EOF
name: $name
project: ${PROJECT_ALIAS:-default}
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
last_accessed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
claude_session_id: ""
summary: ""
type: review
prs:
$(for pr in "${prs[@]}"; do echo "  - $pr"; done)
EOF

  # Write context
  echo "$context" > "$session_dir/context.md"

  echo ""
  echo -e "${GREEN}Review session created: $name${NC}"
  echo -e "Context written to: $session_dir/context.md"
  echo ""

  # Write metadata for info bar
  _write_session_meta "$session_dir" "$name" "review"

  # Start Claude in iTerm2 layout
  read -p "Start Claude now? [Y/n] " start_now
  if [[ ! "$start_now" =~ ^[Nn]$ ]]; then
    session_update "$name" "last_accessed" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    _open_session_layout "$name" "$session_dir" "claude --dangerously-skip-permissions --chrome 'context.md'"
  fi

  echo ""
  echo -e "  ${GRAY}Resume:${NC}  crab review resume $name"
  echo -e "  ${GRAY}Output:${NC}  crab review show $name"
  echo -e "  ${GRAY}Delete:${NC}  crab review delete $name"
}

# Prompt for review summary with auto-generate option
_prompt_review_summary() {
  local name="$1"
  echo ""
  echo "Save a summary for this review?"
  echo "  [a] Auto-generate (Claude summarizes)"
  echo "  [m] Manual (type your own)"
  echo "  [s] Skip"
  read -p "Choice [a/m/s]: " choice

  case "$choice" in
    a|A|"")
      echo -e "${CYAN}Generating summary...${NC}"
      local summary=$(claude --continue --print -p "Summarize this review session in ONE short line (under 60 chars). Format: '<main finding/status> - <key detail>'. Example: 'Found 3 issues - N+1 query, missing index, race condition'. Just output the summary, nothing else." 2>/dev/null | tail -1)
      if [ -n "$summary" ]; then
        # Clean up the summary (remove quotes if present)
        summary="${summary#\"}"
        summary="${summary%\"}"
        session_update "$name" "summary" "$summary"
        echo -e "Summary: ${GREEN}$summary${NC}"
      else
        echo -e "${YELLOW}Could not generate summary${NC}"
      fi
      ;;
    m|M)
      read -p "Summary: " summary
      if [ -n "$summary" ]; then
        session_update "$name" "summary" "$summary"
        success "Summary saved"
      fi
      ;;
    *)
      echo "Skipped"
      ;;
  esac
}

# Quick review - single PR (standard single-agent review)
review_quick() {
  local pr_id="$1"

  local parsed=($(parse_pr_identifier "$pr_id"))
  local owner="${parsed[0]}"
  local repo="${parsed[1]}"
  local number="${parsed[2]}"

  if [ -z "$number" ]; then
    error "Could not parse PR identifier: $pr_id"
    echo "Formats: 3230, repo#456, https://github.com/.../pull/123"
    return 1
  fi

  local name="review-${repo:-pr}-$number"

  # Check if session already exists
  local sessions_dir=$(get_sessions_dir)
  if [ -d "$sessions_dir/$name" ]; then
    echo -e "${YELLOW}Review session already exists: $name${NC}"
    echo "  [r] Resume   [d] Delete & recreate   [q] Quit"
    read -p "Choice [r/d/q]: " choice
    case "$choice" in
      d|D)
        rm -rf "$sessions_dir/$name"
        echo -e "${GREEN}Deleted: $name${NC}"
        echo ""
        ;;
      q|Q|n|N)
        return 1
        ;;
      *)
        session_resume "$name"
        return
        ;;
    esac
  fi

  # Fetch PR data
  local context=$(fetch_pr_data "$owner" "$repo" "$number" "standard")
  [ $? -eq 0 ] || return 1

  # Create session
  local session_dir="$sessions_dir/$name"
  mkdir -p "$session_dir"

  cat > "$session_dir/session.yaml" << EOF
name: $name
project: ${PROJECT_ALIAS:-default}
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
last_accessed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
claude_session_id: ""
summary: ""
type: review
prs:
  - $pr_id
EOF

  echo "$context" > "$session_dir/context.md"

  echo -e "${GREEN}Review session created: $name${NC}"
  echo ""

  # Write metadata for info bar (including ticket info from PR)
  local pr_title=$(echo "$context" | grep -m1 '\*\*Title:\*\*' | sed 's/.*\*\*Title:\*\* //')
  local pr_url=$(echo "$context" | grep -m1 '\*\*URL:\*\*' | sed 's/.*\*\*URL:\*\* //')
  _extract_pr_ticket_info "$owner" "$repo" "$number"
  local meta_args=("$session_dir" "$name" "review" \
    "pr_number" "$number" \
    "pr_url" "$pr_url" \
    "pr_title" "$pr_title")
  [ -n "$_TICKET_ID" ] && meta_args+=("ticket" "$_TICKET_ID")
  [ -n "$_TICKET_URL" ] && meta_args+=("ticket_url" "$_TICKET_URL")
  _write_session_meta "${meta_args[@]}"

  # Start Claude in iTerm2 layout
  session_update "$name" "last_accessed" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  _open_session_layout "$name" "$session_dir" "claude --dangerously-skip-permissions --chrome 'context.md'"

  echo ""
  echo -e "  ${GRAY}Resume:${NC}  crab review resume $name"
  echo -e "  ${GRAY}Output:${NC}  crab review show $name"
  echo -e "  ${GRAY}Delete:${NC}  crab review delete $name"
}

# Show fun court intro animation
_show_court_intro() {
  # 256-color orange/coral gradient tones
  local C1='\033[38;5;209m'  # coral
  local C2='\033[38;5;208m'  # orange
  local C3='\033[38;5;214m'  # light orange
  local C4='\033[38;5;215m'  # peach
  local DIM='\033[2m'
  local RST='\033[0m'

  echo ""
  # FIGlet-style banner - "CRAB COURT" (no box - cleaner look)
  echo -e "${C1}    ██████╗██████╗  █████╗ ██████╗      ██████╗ ██████╗ ██╗   ██╗██████╗ ████████╗${RST}"
  echo -e "${C2}   ██╔════╝██╔══██╗██╔══██╗██╔══██╗    ██╔════╝██╔═══██╗██║   ██║██╔══██╗╚══██╔══╝${RST}"
  echo -e "${C2}   ██║     ██████╔╝███████║██████╔╝    ██║     ██║   ██║██║   ██║██████╔╝   ██║   ${RST}"
  echo -e "${C3}   ██║     ██╔══██╗██╔══██║██╔══██╗    ██║     ██║   ██║██║   ██║██╔══██╗   ██║   ${RST}"
  echo -e "${C3}   ╚██████╗██║  ██║██║  ██║██████╔╝    ╚██████╗╚██████╔╝╚██████╔╝██║  ██║   ██║   ${RST}"
  echo -e "${C4}    ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝      ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ${RST}"
  echo ""
  # Crab judge with scales
  echo -e "                                      ${C2}\\___/${RST}"
  echo -e "                                     ${C2}( °_°)${RST}"
  echo -e "                                    ${C3}/)" " "${C1}⚖️" " "${C3}(\\\\${RST}"
  echo -e "                                   ${C4}<       >${RST}"
  echo ""
  echo -e "                              ${DIM}\"Order in the court!\"${RST}"
  echo ""
  echo -e "                  ${C2}┌─────────────┐${RST}           ${C3}┌─────────────┐${RST}"
  echo -e "                  ${C2}│   Claude    │${RST}    vs     ${C3}│    Codex    │${RST}"
  echo -e "                  ${C2}│  Reviewer A │${RST}           ${C3}│  Reviewer B │${RST}"
  echo -e "                  ${C2}└─────────────┘${RST}           ${C3}└─────────────┘${RST}"
  echo ""
  echo -e "  ${DIM}How this works:${RST}"
  echo ""
  echo -e "    ${C1}1.${RST} Empanel      ${DIM}Judge spawns two independent reviewers${RST}"
  echo -e "    ${C2}2.${RST} Review       ${DIM}Both reviewers analyze the PR separately${RST}"
  echo -e "    ${C3}3.${RST} Collect      ${DIM}Judge gathers findings from both${RST}"
  echo -e "    ${C4}4.${RST} Verify       ${DIM}Judge traces each claim to actual code${RST}"
  echo -e "    ${C1}5.${RST} Deliberate   ${DIM}Resolve disagreements, rule on each issue${RST}"
  echo -e "    ${C2}6.${RST} Verdict      ${DIM}Final ruling with zero false positives${RST}"
  echo ""
  echo -e "  ${CYAN}Fetching PR data...${NC}"
  echo ""
}

# Court review - Judge pattern with Claude + Codex reviewers
review_court() {
  local pr_id="$1"

  # Immediate feedback
  echo -e "${CYAN}Preparing court review for: $pr_id${NC}"
  echo ""

  # Check if codex CLI is available
  if ! command_exists codex; then
    warn "Codex CLI not found. Install with: npm install -g @openai/codex"
    echo "Court review will proceed with Claude teammate only."
    echo ""
  fi

  local parsed=($(parse_pr_identifier "$pr_id"))
  local owner="${parsed[0]}"
  local repo="${parsed[1]}"
  local number="${parsed[2]}"

  if [ -z "$number" ]; then
    error "Could not parse PR identifier: $pr_id"
    echo "Formats: 3230, repo#456, https://github.com/.../pull/123"
    return 1
  fi

  local name="court-${repo:-pr}-$number"

  # Check if session already exists
  local sessions_dir=$(get_sessions_dir)
  if [ -d "$sessions_dir/$name" ]; then
    echo -e "${YELLOW}Court review session already exists: $name${NC}"
    echo "  [r] Resume   [d] Delete & recreate   [q] Quit"
    read -p "Choice [r/d/q]: " choice
    case "$choice" in
      d|D)
        rm -rf "$sessions_dir/$name"
        echo -e "${GREEN}Deleted: $name${NC}"
        echo ""
        ;;
      q|Q|n|N)
        return 1
        ;;
      *)
        session_resume "$name"
        return
        ;;
    esac
  fi

  # Show the court intro while fetching
  _show_court_intro

  # Fetch PR data with court instructions (this can take a moment for large PRs)
  local context=$(fetch_pr_data "$owner" "$repo" "$number" "court")
  [ $? -eq 0 ] || return 1

  # Create session
  local session_dir="$sessions_dir/$name"
  mkdir -p "$session_dir"

  cat > "$session_dir/session.yaml" << EOF
name: $name
project: ${PROJECT_ALIAS:-default}
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
last_accessed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
claude_session_id: ""
summary: ""
type: court
prs:
  - $pr_id
EOF

  echo "$context" > "$session_dir/context.md"

  echo -e "${GREEN}Court review session created: $name${NC}"
  echo ""

  # Write metadata for info bar (including ticket info from PR)
  local pr_title=$(echo "$context" | grep -m1 '\*\*Title:\*\*' | sed 's/.*\*\*Title:\*\* //')
  local pr_url=$(echo "$context" | grep -m1 '\*\*URL:\*\*' | sed 's/.*\*\*URL:\*\* //')
  _extract_pr_ticket_info "$owner" "$repo" "$number"
  local meta_args=("$session_dir" "$name" "court" \
    "pr_number" "$number" \
    "pr_url" "$pr_url" \
    "pr_title" "$pr_title")
  [ -n "$_TICKET_ID" ] && meta_args+=("ticket" "$_TICKET_ID")
  [ -n "$_TICKET_URL" ] && meta_args+=("ticket_url" "$_TICKET_URL")
  _write_session_meta "${meta_args[@]}"

  # Build codex command for server pane (Reviewer B)
  local codex_cmd=""
  if command_exists codex; then
    codex_cmd="codex exec --full-auto --skip-git-repo-check 'You are Reviewer B in a code review court. Read context.md for the full PR diff. Review independently for bugs, security issues, and code quality. Structure findings as Critical/Warning/Suggestion with file:line references. Save your complete findings to codex-review.md when done.'"
  fi

  # Start Claude as the judge in iTerm2 layout (with Codex in server pane)
  session_update "$name" "last_accessed" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  _open_session_layout "$name" "$session_dir" "claude --dangerously-skip-permissions --chrome 'context.md'" "$codex_cmd"

  echo ""
  echo -e "  ${GRAY}Resume:${NC}  crab court resume $name"
  echo -e "  ${GRAY}Output:${NC}  crab court show $name"
  echo -e "  ${GRAY}Delete:${NC}  crab court delete $name"
}

# Handle review commands
handle_review_command() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    "")
      error "Usage: crab review <PR> or crab court <PR>"
      echo ""
      echo "Commands:"
      echo "  crab review <PR>       Quick single-agent review"
      echo "  crab court <PR>        Court review (Judge + 2 reviewers, thorough)"
      echo "  crab review new        Interactive mode (multiple PRs + context)"
      echo "  crab review ls         List review sessions"
      echo "  crab review resume     Resume a review"
      echo "  crab review show       View saved review output"
      echo "  crab review delete     Delete a review session"
      return 1
      ;;
    "new")
      review_new_interactive
      ;;
    "ls"|"list")
      session_list "review"
      ;;
    "resume"|"continue")
      local name="${1:-}"
      if [ -z "$name" ]; then
        error "Specify review to resume"
        echo "Use 'crab review ls' to see reviews"
        return 1
      fi
      # Handle both "review-xxx" and just the PR number/name
      if [[ ! "$name" == review-* ]]; then
        local parsed=($(parse_pr_identifier "$name"))
        local repo="${parsed[1]}"
        local number="${parsed[2]}"
        name="review-${repo:-pr}-$number"
      fi
      session_resume "$name"
      ;;
    "delete"|"rm")
      local name="${1:-}"
      if [ -z "$name" ]; then
        error "Specify review to delete (or 'all' to delete all)"
        return 1
      fi
      if [ "$name" = "all" ]; then
        _delete_all_sessions "review"
      else
        if [[ ! "$name" == review-* ]] && [[ ! "$name" == court-* ]]; then
          local parsed=($(parse_pr_identifier "$name"))
          local repo="${parsed[1]}"
          local number="${parsed[2]}"
          name="review-${repo:-pr}-$number"
        fi
        session_delete "$name"
      fi
      ;;
    "show"|"view"|"output")
      local name="${1:-}"
      if [ -z "$name" ]; then
        error "Specify review to view"
        echo "Usage: crab review show <name>"
        return 1
      fi
      if [[ ! "$name" == review-* ]]; then
        local parsed=($(parse_pr_identifier "$name"))
        local repo="${parsed[1]}"
        local number="${parsed[2]}"
        name="review-${repo:-pr}-$number"
      fi
      local sessions_dir=$(get_sessions_dir)
      local output_file="$sessions_dir/$name/review-output.md"
      if [ -f "$output_file" ]; then
        echo -e "${BOLD}Review output for: $name${NC}"
        echo ""
        cat "$output_file"
      else
        error "No saved review output for '$name'"
        echo "The review hasn't been saved yet. Resume the review and ask Claude to save findings."
      fi
      ;;
    *)
      # Assume it's a PR identifier
      review_quick "$cmd"
      ;;
  esac
}

# Handle court command (shortcut for crab court <PR>)
# Court review - interactive mode for multiple PRs
court_new_interactive() {
  echo "Creating new court review session"
  echo ""

  # Get session name
  local name=""
  read -p "Session name: " name
  [ -z "$name" ] && { error "Name required"; return 1; }
  name="court-$name"

  # Check if codex CLI is available
  if ! command_exists codex; then
    warn "Codex CLI not found. Install with: npm install -g @openai/codex"
    echo "Court review will proceed with Claude teammate only."
    echo ""
  fi

  # Collect PRs
  local prs=()
  echo ""
  echo "Add PRs (empty line when done):"
  while true; do
    read -p "> " pr_input
    [ -z "$pr_input" ] && break
    prs+=("$pr_input")
  done

  if [ ${#prs[@]} -eq 0 ]; then
    error "At least one PR required"
    return 1
  fi

  # Collect context
  echo ""
  echo "Additional context (optional, empty line when done):"
  local context_lines=()
  while true; do
    read -p "> " context_line
    [ -z "$context_line" ] && break
    context_lines+=("$context_line")
  done

  # Show the court intro
  _show_court_intro

  # Build context document with court instructions
  local court_instructions=$(get_court_instructions)
  local context="# Court Review Session: $name"$'\n\n'
  context+="$court_instructions"$'\n\n'

  # Add user context if provided
  if [ ${#context_lines[@]} -gt 0 ]; then
    context+="## Additional Context"$'\n'
    for line in "${context_lines[@]}"; do
      context+="$line"$'\n'
    done
    context+=$'\n'
  fi

  # Fetch and append PR data
  context+="## Pull Requests"$'\n\n'

  for pr_id in "${prs[@]}"; do
    local parsed=($(parse_pr_identifier "$pr_id"))
    local owner="${parsed[0]}"
    local repo="${parsed[1]}"
    local number="${parsed[2]}"

    if [ -z "$number" ]; then
      warn "Could not parse PR: $pr_id"
      continue
    fi

    # Fetch PR data without court instructions (we already added them above)
    local pr_data=$(fetch_pr_data "$owner" "$repo" "$number" "standard")
    context+="$pr_data"$'\n\n'
    context+="---"$'\n\n'
  done

  # Create session
  local sessions_dir=$(get_sessions_dir)
  local session_dir="$sessions_dir/$name"
  mkdir -p "$session_dir"

  # Write session metadata
  cat > "$session_dir/session.yaml" << EOF
name: $name
project: ${PROJECT_ALIAS:-default}
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
last_accessed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
claude_session_id: ""
summary: ""
type: court
prs:
$(for pr in "${prs[@]}"; do echo "  - $pr"; done)
EOF

  # Write context
  echo "$context" > "$session_dir/context.md"

  echo ""
  echo -e "${GREEN}Court review session created: $name${NC}"
  echo ""

  # Write metadata for info bar
  _write_session_meta "$session_dir" "$name" "court"

  # Build codex command for server pane (Reviewer B)
  local codex_cmd=""
  if command_exists codex; then
    codex_cmd="codex exec --full-auto --skip-git-repo-check 'You are Reviewer B in a code review court. Read context.md for the full PR diff. Review independently for bugs, security issues, and code quality. Structure findings as Critical/Warning/Suggestion with file:line references. Save your complete findings to codex-review.md when done.'"
  fi

  # Start Claude in iTerm2 layout (with Codex in server pane)
  read -p "Start court session now? [Y/n] " start_now
  if [[ ! "$start_now" =~ ^[Nn]$ ]]; then
    session_update "$name" "last_accessed" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    _open_session_layout "$name" "$session_dir" "claude --dangerously-skip-permissions --chrome 'context.md'" "$codex_cmd"
  fi

  echo ""
  echo -e "  ${GRAY}Resume:${NC}  crab court resume $name"
  echo -e "  ${GRAY}Output:${NC}  crab court show $name"
  echo -e "  ${GRAY}Delete:${NC}  crab court delete $name"
}

# Handle court command
handle_court_command() {
  local cmd="${1:-}"
  shift 2>/dev/null || true

  case "$cmd" in
    "")
      error "Usage: crab court <PR> or crab court new"
      echo ""
      echo "Court review: thorough multi-agent review with:"
      echo "  - Judge (Claude) - orchestrates, verifies, delivers verdict"
      echo "  - Reviewer A (Claude teammate) - independent review"
      echo "  - Reviewer B (Codex) - independent review"
      echo ""
      echo "Commands:"
      echo "  crab court <PR>        Quick court review for single PR"
      echo "  crab court new         Interactive mode (multiple PRs + context)"
      echo "  crab court ls          List court sessions"
      echo "  crab court resume      Resume a court session"
      echo "  crab court show        View saved court output"
      echo "  crab court delete      Delete a court session"
      return 1
      ;;
    "new")
      court_new_interactive
      ;;
    "ls"|"list")
      session_list "court"
      ;;
    "resume"|"continue")
      local name="${1:-}"
      if [ -z "$name" ]; then
        error "Specify court session to resume"
        echo "Use 'crab court ls' to see sessions"
        return 1
      fi
      # Handle both "court-xxx" and just the name
      if [[ ! "$name" == court-* ]]; then
        name="court-$name"
      fi
      session_resume "$name"
      ;;
    "show"|"view"|"output")
      local name="${1:-}"
      if [ -z "$name" ]; then
        error "Specify court session to view"
        echo "Usage: crab court show <name>"
        return 1
      fi
      if [[ ! "$name" == court-* ]]; then
        name="court-$name"
      fi
      local sessions_dir=$(get_sessions_dir)
      local output_file="$sessions_dir/$name/review-output.md"
      if [ -f "$output_file" ]; then
        echo "Court verdict for: $name"
        echo ""
        cat "$output_file"
      else
        error "No saved verdict for '$name'"
        echo "Resume the court session and have the judge deliver a verdict."
      fi
      ;;
    "delete"|"rm")
      local name="${1:-}"
      if [ -z "$name" ]; then
        error "Specify court session to delete (or 'all' to delete all)"
        return 1
      fi
      if [ "$name" = "all" ]; then
        _delete_all_sessions "court"
      else
        if [[ ! "$name" == court-* ]]; then
          name="court-$name"
        fi
        session_delete "$name"
      fi
      ;;
    *)
      # Assume it's a PR identifier
      review_court "$cmd"
      ;;
  esac
}
