#!/usr/bin/env bash
# crabterm - PR workspace command handler

# Find an existing workspace whose current branch matches the given branch name
# Returns: workspace number, or empty string if none found
find_workspace_for_branch() {
  local target_branch="$1"

  for dir in "$WORKSPACE_BASE/$WORKSPACE_PREFIX-"*; do
    [ -d "$dir" ] || continue
    local num
    num=$(basename "$dir" | sed "s/${WORKSPACE_PREFIX}-//")
    [[ "$num" =~ ^[0-9]+$ ]] || continue

    local branch
    branch=$(cd "$dir" && git branch --show-current 2>/dev/null)
    if [ "$branch" = "$target_branch" ]; then
      echo "$num"
      return
    fi
  done

  echo ""
}

# Fetch PR metadata using gh CLI
# Sets globals: PR_BRANCH, PR_TITLE, PR_URL, PR_BODY, PR_COMMENTS_TEXT
fetch_pr_metadata() {
  local owner="$1"
  local repo="$2"
  local number="$3"
  local full_repo="$owner/$repo"

  if ! command_exists gh; then
    error "gh CLI required for PR workspaces"
    echo "Install: brew install gh"
    return 1
  fi

  local pr_json
  pr_json=$(gh pr view "$number" --repo "$full_repo" --json title,headRefName,url 2>/dev/null)
  if [ -z "$pr_json" ]; then
    error "Could not fetch PR #$number from $full_repo"
    return 1
  fi

  PR_BRANCH=$(echo "$pr_json" | jq -r '.headRefName')
  PR_TITLE=$(echo "$pr_json" | jq -r '.title')
  PR_URL=$(echo "$pr_json" | jq -r '.url')

  # Fetch body and comments separately using gh's --jq flag to avoid
  # control character issues that break external jq parsing
  PR_BODY=$(gh pr view "$number" --repo "$full_repo" --json body --jq '.body // ""' 2>/dev/null)
  PR_COMMENTS_TEXT=$(gh pr view "$number" --repo "$full_repo" --json comments --jq '[.comments[].body // empty] | join("\n")' 2>/dev/null)
}

# Checkout the PR branch in an existing workspace directory
checkout_pr_branch() {
  local dir="$1"
  local owner="$2"
  local repo="$3"
  local number="$4"
  local full_repo="$owner/$repo"

  CHECKOUT_EXISTING_WS=""

  echo -e "${BLUE}Checking out PR #$number branch...${NC}"
  cd "$dir"
  if ! gh pr checkout "$number" --repo "$full_repo" 2>/dev/null; then
    # Fallback: fetch and checkout the branch directly
    local branch="$PR_BRANCH"
    git fetch origin "$branch" 2>/dev/null || true
    git checkout "$branch" 2>/dev/null || git checkout -b "$branch" "origin/$branch" 2>/dev/null || {
      # Check if branch is already checked out in another worktree
      local target_ref="refs/heads/$branch"
      local worktree_path
      worktree_path=$(git worktree list --porcelain 2>/dev/null | awk -v ref="$target_ref" '
        /^worktree /{ wt=substr($0,10) }
        /^branch /{ if(substr($0,8)==ref) print wt }
      ')
      if [ -n "$worktree_path" ]; then
        # Check if it's another workspace
        local ws_num
        ws_num=$(basename "$worktree_path" | sed "s/^${WORKSPACE_PREFIX}-//")
        if [[ "$ws_num" =~ ^[0-9]+$ ]]; then
          CHECKOUT_EXISTING_WS="$ws_num"
          return 2
        fi
        # Branch is checked out in a non-workspace worktree (e.g. main repo) —
        # detach HEAD there so we can use the branch here
        echo -e "${YELLOW}Branch checked out in $worktree_path, detaching it...${NC}"
        git -C "$worktree_path" checkout --detach 2>/dev/null || true
        # Retry checkout
        git checkout "$branch" 2>/dev/null || git checkout -b "$branch" "origin/$branch" 2>/dev/null || {
          error "Failed to checkout PR branch: $branch"
          return 1
        }
        echo -e "${GREEN}On branch: $(git branch --show-current)${NC}"
        return 0
      fi
      error "Failed to checkout PR branch: $branch"
      return 1
    }
  fi
  echo -e "${GREEN}On branch: $(git branch --show-current)${NC}"
}

# Build a prompt for Claude to work on a PR
build_pr_prompt() {
  local number="$1"
  local title="$2"
  local url="$3"
  local repo="$4"
  local branch="$5"

  local default_prompt='You are working on PR #{number} in {repo}.

**Title:** {title}
**URL:** {url}
**Branch:** {branch}

Fetch the PR diff using `gh pr diff {number}` and review the changes. Then:
1. Understand what the PR does
2. Check if there are any issues, failing tests, or incomplete work
3. Ask me how you can help (fix issues, add tests, continue implementation, etc.)

Start by reading the PR description with `gh pr view {number}` and the diff.'

  local template
  template=$(config_get "pr.prompt_template" "$default_prompt")

  template="${template//\{number\}/$number}"
  template="${template//\{title\}/$title}"
  template="${template//\{url\}/$url}"
  template="${template//\{repo\}/$repo}"
  template="${template//\{branch\}/$branch}"

  echo "$template"
}

# Main handler for: crab pr <identifier>
handle_pr_command() {
  local identifier="${1:-}"

  if [ -z "$identifier" ]; then
    error "PR identifier required"
    echo ""
    echo "Usage: crab pr <PR>"
    echo "       crab ws <N> pr <PR>"
    echo ""
    echo "Formats:"
    echo "  crab pr 123"
    echo "  crab pr repo#456"
    echo "  crab pr https://github.com/owner/repo/pull/789"
    exit 1
  fi

  # Parse PR identifier (reuses parse_pr_identifier from review.sh)
  local parsed
  parsed=($(parse_pr_identifier "$identifier"))
  local owner="${parsed[0]}"
  local repo="${parsed[1]}"
  local number="${parsed[2]}"

  if [ -z "$number" ]; then
    error "Could not parse PR identifier: $identifier"
    echo "Formats: 123, repo#456, https://github.com/.../pull/789"
    exit 1
  fi

  echo -e "${CYAN}Fetching PR #$number from $owner/$repo...${NC}"

  # Fetch PR metadata
  fetch_pr_metadata "$owner" "$repo" "$number" || exit 1

  echo -e "  Title: ${BOLD}$PR_TITLE${NC}"
  echo -e "  Branch: $PR_BRANCH"
  echo ""

  # Check if an existing workspace is already on this branch
  local existing_num
  existing_num=$(find_workspace_for_branch "$PR_BRANCH")

  if [ -n "$existing_num" ]; then
    echo -e "${GREEN}Found existing workspace $existing_num on branch $PR_BRANCH${NC}"

    # Extract ticket info from branch name, PR body, and comments
    local ticket_id ticket_url
    ticket_id=$(extract_ticket_from_branch "$PR_BRANCH")
    ticket_url=$(extract_linear_url_from_body "$PR_BODY")
    if [ -z "$ticket_url" ] && [ -n "$PR_COMMENTS_TEXT" ]; then
      ticket_url=$(extract_linear_url_from_body "$PR_COMMENTS_TEXT")
    fi
    if [ -z "$ticket_id" ] && [ -n "$ticket_url" ]; then
      ticket_id=$(parse_ticket_identifier "$ticket_url")
    fi

    # Write metadata so info bar has content
    local meta_args=("$existing_num" "pr" \
      "name" "$PR_BRANCH" \
      "pr_number" "$number" \
      "pr_url" "$PR_URL" \
      "pr_title" "$PR_TITLE")
    [ -n "$ticket_id" ] && meta_args+=("ticket" "$ticket_id")
    [ -n "$ticket_url" ] && meta_args+=("ticket_url" "$ticket_url")
    write_workspace_meta "${meta_args[@]}"

    set_workspace_name "$existing_num" "$PR_BRANCH"
    open_workspace "$existing_num"
    return
  fi

  # Try to reuse an unlocked workspace before creating a new one
  local num
  num=$(find_unlocked_workspace)

  if [ -n "$num" ]; then
    echo -e "${CYAN}Reusing unlocked workspace $num for PR #$number...${NC}"
    prepare_workspace_for_reuse "$num"
  else
    num=$(find_next_workspace)
    if [ -z "$num" ]; then
      error "No available workspace slots (max 100)"
      exit 1
    fi
    echo -e "${CYAN}Creating workspace $num for PR #$number...${NC}"
    create_workspace "$num"
  fi

  # Checkout the PR branch in the workspace
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  CHECKOUT_EXISTING_WS=""
  local checkout_rc=0
  checkout_pr_branch "$dir" "$owner" "$repo" "$number" || checkout_rc=$?

  if [ "$checkout_rc" -eq 2 ] && [ -n "$CHECKOUT_EXISTING_WS" ]; then
    # Branch is already checked out in another workspace — use that one
    echo -e "${YELLOW}Branch already checked out in workspace $CHECKOUT_EXISTING_WS, switching to it...${NC}"
    rm -f "$dir/.crabterm-lock"
    num="$CHECKOUT_EXISTING_WS"
    dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  elif [ "$checkout_rc" -ne 0 ]; then
    exit 1
  fi

  # Name the workspace after the PR branch
  set_workspace_name "$num" "$PR_BRANCH"

  # Extract ticket info from branch name, PR body, and comments
  local ticket_id ticket_url
  ticket_id=$(extract_ticket_from_branch "$PR_BRANCH")
  ticket_url=$(extract_linear_url_from_body "$PR_BODY")
  # Fall back to scanning PR comments (Linear bot often comments with ticket link)
  if [ -z "$ticket_url" ] && [ -n "$PR_COMMENTS_TEXT" ]; then
    ticket_url=$(extract_linear_url_from_body "$PR_COMMENTS_TEXT")
  fi
  # If we found a Linear URL but no ticket ID from the branch, extract from the URL
  if [ -z "$ticket_id" ] && [ -n "$ticket_url" ]; then
    ticket_id=$(parse_ticket_identifier "$ticket_url")
  fi

  # Write workspace metadata for info bar
  local meta_args=("$num" "pr" \
    "name" "$PR_BRANCH" \
    "pr_number" "$number" \
    "pr_url" "$PR_URL" \
    "pr_title" "$PR_TITLE")
  [ -n "$ticket_id" ] && meta_args+=("ticket" "$ticket_id")
  [ -n "$ticket_url" ] && meta_args+=("ticket_url" "$ticket_url")
  write_workspace_meta "${meta_args[@]}"

  # Build prompt and open workspace
  local prompt
  prompt=$(build_pr_prompt "$number" "$PR_TITLE" "$PR_URL" "$owner/$repo" "$PR_BRANCH")
  open_workspace "$num" "$prompt"
}

# Handle: crab ws <N> pr <PR>
handle_ws_pr_command() {
  local num="$1"
  local identifier="${2:-}"

  if [ -z "$identifier" ]; then
    error "PR identifier required: crab ws $num pr <PR>"
    exit 1
  fi

  # Parse PR identifier
  local parsed
  parsed=($(parse_pr_identifier "$identifier"))
  local owner="${parsed[0]}"
  local repo="${parsed[1]}"
  local number="${parsed[2]}"

  if [ -z "$number" ]; then
    error "Could not parse PR identifier: $identifier"
    echo "Formats: 123, repo#456, https://github.com/.../pull/789"
    exit 1
  fi

  echo -e "${CYAN}Fetching PR #$number from $owner/$repo...${NC}"

  # Fetch PR metadata
  fetch_pr_metadata "$owner" "$repo" "$number" || exit 1

  echo -e "  Title: ${BOLD}$PR_TITLE${NC}"
  echo -e "  Branch: $PR_BRANCH"
  echo ""

  # Create workspace if it doesn't exist
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  if [ ! -d "$dir" ]; then
    echo -e "${CYAN}Creating workspace $num...${NC}"
    create_workspace "$num"
  fi

  # Checkout the PR branch
  CHECKOUT_EXISTING_WS=""
  local checkout_rc=0
  checkout_pr_branch "$dir" "$owner" "$repo" "$number" || checkout_rc=$?

  if [ "$checkout_rc" -eq 2 ] && [ -n "$CHECKOUT_EXISTING_WS" ]; then
    # Branch is already checked out in another workspace — use that one
    echo -e "${YELLOW}Branch already checked out in workspace $CHECKOUT_EXISTING_WS, switching to it...${NC}"
    num="$CHECKOUT_EXISTING_WS"
    dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  elif [ "$checkout_rc" -ne 0 ]; then
    exit 1
  fi

  # Name the workspace after the PR branch
  set_workspace_name "$num" "$PR_BRANCH"

  # Extract ticket info from branch name, PR body, and comments
  local ticket_id ticket_url
  ticket_id=$(extract_ticket_from_branch "$PR_BRANCH")
  ticket_url=$(extract_linear_url_from_body "$PR_BODY")
  # Fall back to scanning PR comments (Linear bot often comments with ticket link)
  if [ -z "$ticket_url" ] && [ -n "$PR_COMMENTS_TEXT" ]; then
    ticket_url=$(extract_linear_url_from_body "$PR_COMMENTS_TEXT")
  fi
  # If we found a Linear URL but no ticket ID from the branch, extract from the URL
  if [ -z "$ticket_id" ] && [ -n "$ticket_url" ]; then
    ticket_id=$(parse_ticket_identifier "$ticket_url")
  fi

  # Write workspace metadata for info bar
  local meta_args=("$num" "pr" \
    "name" "$PR_BRANCH" \
    "pr_number" "$number" \
    "pr_url" "$PR_URL" \
    "pr_title" "$PR_TITLE")
  [ -n "$ticket_id" ] && meta_args+=("ticket" "$ticket_id")
  [ -n "$ticket_url" ] && meta_args+=("ticket_url" "$ticket_url")
  write_workspace_meta "${meta_args[@]}"

  # Build prompt and open workspace
  local prompt
  prompt=$(build_pr_prompt "$number" "$PR_TITLE" "$PR_URL" "$owner/$repo" "$PR_BRANCH")
  open_workspace "$num" "$prompt"
}
