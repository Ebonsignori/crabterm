#!/usr/bin/env bash
# crabterm - merge workspace branches into main

_merge_usage() {
  echo "Usage: crab merge [--dry-run] [N]"
  echo ""
  echo "Merge workspace branches that have commits ahead of main."
  echo ""
  echo "Options:"
  echo "  --dry-run    Show what would be merged without making changes"
  echo "  N            Only merge workspace N's branch"
  echo ""
  echo "Examples:"
  echo "  crab merge              Merge all workspace branches into main"
  echo "  crab merge 3            Merge only workspace 3's branch"
  echo "  crab merge --dry-run    Preview what would be merged"
}

_resolve_conflicts_with_claude() {
  local branch="$1"

  if ! command_exists claude; then
    warn "claude CLI not found — cannot auto-resolve conflicts"
    echo "  Install: https://docs.anthropic.com/en/docs/claude-code"
    return 1
  fi

  local conflicted_files
  conflicted_files=$(cd "$MAIN_REPO" && git diff --name-only --diff-filter=U)

  if [ -z "$conflicted_files" ]; then
    return 0
  fi

  local commit_log
  commit_log=$(cd "$MAIN_REPO" && git log "main..$branch" --format='%h %s' 2>/dev/null)

  local file_list
  file_list=$(echo "$conflicted_files" | sed 's/^/  - /')

  local prompt="You are resolving merge conflicts in a git repository.

Branch '$branch' is being merged into main. The following files have conflicts:
$file_list

Commits from $branch:
$commit_log

For each conflicted file:
1. Read the file
2. Resolve all conflict markers (<<<<<<< ======= >>>>>>>) by keeping the intent of BOTH sides
3. Write the resolved file

Do NOT leave any conflict markers. Preserve all functionality from both branches."

  echo -e "  ${CYAN}Asking Claude to resolve conflicts...${NC}"
  cd "$MAIN_REPO"
  echo "$prompt" | claude --dangerously-skip-permissions -p 2>/dev/null

  # Check if conflicts remain
  local remaining
  remaining=$(git diff --name-only --diff-filter=U)
  if [ -z "$remaining" ]; then
    git add -A
    git commit --no-edit
    return 0
  else
    warn "Claude could not resolve all conflicts"
    echo "  Remaining conflicts:"
    echo "$remaining" | sed 's/^/    /'
    return 1
  fi
}

handle_merge_command() {
  local dry_run=false
  local target_num=""

  # Parse args
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run|-n)
        dry_run=true
        shift
        ;;
      --help|-h)
        _merge_usage
        return 0
        ;;
      *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          target_num="$1"
        else
          error "Unknown argument: $1"
          _merge_usage
          return 1
        fi
        shift
        ;;
    esac
  done

  # Validate main repo
  if [ ! -d "$MAIN_REPO" ]; then
    error "Main repo not found at $MAIN_REPO"
    return 1
  fi

  # Check for clean working tree
  local dirty
  dirty=$(cd "$MAIN_REPO" && git status --porcelain 2>/dev/null)
  if [ -n "$dirty" ]; then
    error "Main repo has uncommitted changes — commit or stash first"
    echo "  $MAIN_REPO"
    return 1
  fi

  cd "$MAIN_REPO"

  # Enumerate workspace branches with commits ahead of main
  local branches_to_merge=()
  local branch_commits=()

  # Collect workspace directories (numbered)
  local ws_nums=()
  if [ -n "$target_num" ]; then
    ws_nums=("$target_num")
  else
    for dir in "$WORKSPACE_BASE/$WORKSPACE_PREFIX-"*; do
      [ -d "$dir" ] || continue
      local num
      num=$(basename "$dir" | sed "s/${WORKSPACE_PREFIX}-//")
      [[ "$num" =~ ^[0-9]+$ ]] || continue
      ws_nums+=("$num")
    done
  fi

  for num in "${ws_nums[@]}"; do
    local branch
    branch=$(get_branch_name "$num")

    # Check if branch exists locally
    if ! git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
      continue
    fi

    # Check if branch has commits ahead of main
    local commits
    commits=$(git log "main..$branch" --oneline 2>/dev/null)
    if [ -z "$commits" ]; then
      continue
    fi

    branches_to_merge+=("$branch")
    branch_commits+=("$commits")
  done

  if [ ${#branches_to_merge[@]} -eq 0 ]; then
    echo -e "${YELLOW}No workspace branches with commits ahead of main.${NC}"
    return 0
  fi

  # Show summary
  echo -e "${CYAN}Branches with commits ahead of main:${NC}"
  echo ""
  for i in "${!branches_to_merge[@]}"; do
    local branch="${branches_to_merge[$i]}"
    local commits="${branch_commits[$i]}"
    local count
    count=$(echo "$commits" | wc -l | tr -d ' ')
    echo -e "  ${BOLD}$branch${NC} ($count commit(s))"
    echo "$commits" | sed 's/^/    /'
    echo ""
  done

  if [ "$dry_run" = true ]; then
    echo -e "${YELLOW}Dry run — no changes made.${NC}"
    return 0
  fi

  # Confirm
  echo -n "Merge ${#branches_to_merge[@]} branch(es) into main? [y/N]: "
  read -r confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Aborted."
    return 0
  fi

  # Update main
  echo ""
  echo -e "${CYAN}Updating main...${NC}"
  git fetch origin 2>/dev/null || true
  git checkout main 2>/dev/null
  git pull origin main 2>/dev/null || true

  # Merge each branch
  local merged=0
  local merge_failed=0

  for branch in "${branches_to_merge[@]}"; do
    echo ""
    echo -e "${CYAN}Merging $branch...${NC}"

    if git merge "$branch" --no-edit 2>/dev/null; then
      echo -e "  ${GREEN}Merged successfully${NC}"
      merged=$((merged + 1))
    else
      echo -e "  ${YELLOW}Conflicts detected — attempting auto-resolve...${NC}"
      if _resolve_conflicts_with_claude "$branch"; then
        echo -e "  ${GREEN}Conflicts resolved and merged${NC}"
        merged=$((merged + 1))
      else
        echo -e "  ${RED}Could not resolve conflicts — aborting merge of $branch${NC}"
        git merge --abort 2>/dev/null || true
        merge_failed=$((merge_failed + 1))
      fi
    fi
  done

  # Summary
  echo ""
  echo "════════════════════════════════════════"
  echo -e "  Merged: ${GREEN}$merged${NC}  Failed: ${RED}$merge_failed${NC}"
  if [ $merged -gt 0 ]; then
    echo ""
    echo -e "  ${YELLOW}Changes are local only — push when ready:${NC}"
    echo "    cd $MAIN_REPO && git push origin main"
  fi
  echo "════════════════════════════════════════"
}
