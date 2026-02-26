#!/usr/bin/env bash
# crabterm - workspace info bar (bottom status pane with clickable links)

# Ensure .crabterm-* files are git-excluded so git clean -fd won't remove them
ensure_crabterm_git_excludes() {
  local dir="$1"
  local git_dir
  git_dir=$(cd "$dir" && git rev-parse --git-dir 2>/dev/null) || return 0

  # For worktrees, git-dir is absolute; for regular repos it's relative
  if [[ "$git_dir" != /* ]]; then
    git_dir="$dir/$git_dir"
  fi

  local exclude_file="$git_dir/info/exclude"
  mkdir -p "$(dirname "$exclude_file")"

  if ! grep -q '\.crabterm-' "$exclude_file" 2>/dev/null; then
    echo "" >> "$exclude_file"
    echo "# crabterm workspace files" >> "$exclude_file"
    echo ".crabterm-*" >> "$exclude_file"
  fi
}

# Write workspace metadata to .crabterm-meta JSON file
# Usage: write_workspace_meta <num> <type> [key value ...]
write_workspace_meta() {
  local num="$1"
  local type="$2"
  shift 2

  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  local meta_file="$dir/.crabterm-meta"

  # Build JSON with jq
  local json
  json=$(jq -n --arg type "$type" '{"type": $type}')

  while [ $# -ge 2 ]; do
    local key="$1"
    local value="$2"
    shift 2
    json=$(echo "$json" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
  done

  # Add configured infobar links if present
  local links_count
  links_count=$(yq -r '.infobar.links | length // 0' "$CONFIG_FILE" 2>/dev/null)
  if [ "$links_count" -gt 0 ] 2>/dev/null; then
    local links_json="[]"
    for ((i=0; i<links_count; i++)); do
      local label url
      label=$(yq -r ".infobar.links[$i].label // \"\"" "$CONFIG_FILE" 2>/dev/null)
      url=$(yq -r ".infobar.links[$i].url // \"\"" "$CONFIG_FILE" 2>/dev/null)
      if [ -n "$label" ] && [ -n "$url" ]; then
        links_json=$(echo "$links_json" | jq --arg l "$label" --arg u "$url" '. + [{"label": $l, "url": $u}]')
      fi
    done
    json=$(echo "$json" | jq --argjson links "$links_json" '. + {links: $links}')
  else
    json=$(echo "$json" | jq '. + {links: []}')
  fi

  echo "$json" > "$meta_file"

  # Protect .crabterm-* files from git clean
  ensure_crabterm_git_excludes "$dir"

  # Update tab title to reflect new metadata
  update_tab_title "$num"
}

# Extract a ticket identifier (e.g. ENG-123) from a branch name
# Matches patterns like: user/ENG-123-fix-bug, ENG-123-description, eng-123
# Returns: ticket ID or empty string
extract_ticket_from_branch() {
  local branch="$1"
  if [[ "$branch" =~ ([A-Za-z][A-Za-z0-9_]*-[0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'
  fi
}

# Extract a Linear ticket URL from text (PR body, comments, etc.)
# Handles both bare URLs and HTML href attributes from Linear bot comments
# Returns: URL or empty string
extract_linear_url_from_body() {
  local body="$1"
  echo "$body" | grep -oE 'https://linear\.app/[^"[:space:]>)]+/issue/[^"[:space:]>)]+' | head -1
}

# Remove .crabterm-meta file
clear_workspace_meta() {
  local num="$1"
  local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$num"
  rm -f "$dir/.crabterm-meta"
}

# Check if a PR exists for the current branch and update metadata
# Note: This function must be safe to call under set -e from the info bar render loop.
# All external commands (jq, gh) are guarded so failures don't kill the render.
sync_workspace_pr() {
  local dir="$1"
  local meta_file="$dir/.crabterm-meta"

  [ -f "$meta_file" ] || return 0

  local type pr_url
  type=$(jq -r '.type // ""' "$meta_file" 2>/dev/null) || return 0
  pr_url=$(jq -r '.pr_url // ""' "$meta_file" 2>/dev/null) || return 0

  # Only sync if type is ticket and no PR discovered yet
  [ "$type" = "ticket" ] || return 0
  [ -z "$pr_url" ] || return 0

  local branch
  branch=$(cd "$dir" && git branch --show-current 2>/dev/null) || return 0
  [ -n "$branch" ] || return 0

  local pr_json
  pr_json=$(cd "$dir" && gh pr list --head "$branch" --json number,url,title --limit 1 2>/dev/null) || return 0
  [ -n "$pr_json" ] || return 0

  local pr_number pr_title pr_found_url
  pr_number=$(echo "$pr_json" | jq -r '.[0].number // empty' 2>/dev/null) || return 0
  [ -n "$pr_number" ] || return 0

  pr_title=$(echo "$pr_json" | jq -r '.[0].title // ""' 2>/dev/null) || true
  pr_found_url=$(echo "$pr_json" | jq -r '.[0].url // ""' 2>/dev/null) || true

  # Update the metadata file with PR info
  local updated
  updated=$(jq \
    --arg num "$pr_number" \
    --arg url "$pr_found_url" \
    --arg title "$pr_title" \
    '. + {pr_number: $num, pr_url: $url, pr_title: $title}' \
    "$meta_file") || return 0
  echo "$updated" > "$meta_file"

  # Update tab title to include PR title
  local ws_num
  ws_num=$(basename "$dir" | sed "s/${WORKSPACE_PREFIX}-//")
  if [[ "$ws_num" =~ ^[0-9]+$ ]] && [ -n "${SESSION_NAME:-}" ]; then
    update_tab_title "$ws_num" 2>/dev/null || true
  fi
}

# Render a single info bar line with OSC 8 clickable links
render_infobar() {
  local dir="$1"
  local meta_file="$dir/.crabterm-meta"

  # Lock/unlock indicator
  local lock_icon
  if [ -f "$dir/.crabterm-lock" ]; then
    lock_icon="\xF0\x9F\x94\x92"  # 🔒
  else
    lock_icon="\xF0\x9F\x9F\xA2"  # 🟢
  fi

  if [ ! -f "$meta_file" ]; then
    echo -e "${lock_icon} \033[2mcrabterm\033[0m"
    return
  fi

  # Guard each jq call with || true so set -e doesn't kill the render
  local type name pr_number pr_url pr_title ticket ticket_url port
  type=$(jq -r '.type // ""' "$meta_file" 2>/dev/null) || true
  name=$(jq -r '.name // ""' "$meta_file" 2>/dev/null) || true
  pr_number=$(jq -r '.pr_number // ""' "$meta_file" 2>/dev/null) || true
  pr_url=$(jq -r '.pr_url // ""' "$meta_file" 2>/dev/null) || true
  pr_title=$(jq -r '.pr_title // ""' "$meta_file" 2>/dev/null) || true
  ticket=$(jq -r '.ticket // ""' "$meta_file" 2>/dev/null) || true
  ticket_url=$(jq -r '.ticket_url // ""' "$meta_file" 2>/dev/null) || true
  port=$(jq -r '.port // ""' "$meta_file" 2>/dev/null) || true

  # Line 1: title
  local title="${lock_icon}"
  if [ -n "$PROJECT_ALIAS" ]; then
    title="$title @${PROJECT_ALIAS}"
  fi
  if [ -n "$pr_number" ] && [ -n "$pr_title" ]; then
    title="$title PR #${pr_number}: ${pr_title}"
  elif [ -n "$name" ]; then
    title="$title $name"
  fi
  echo -e "$title"

  # Line 2: links
  local links=()

  # GitHub PR link (OSC 8)
  if [ -n "$pr_url" ]; then
    links+=("\033]8;;${pr_url}\a\xF0\x9F\x94\x97 GitHub PR\033]8;;\a")
  fi

  # Ticket link
  if [ -n "$ticket" ]; then
    if [ -n "$ticket_url" ]; then
      links+=("\033]8;;${ticket_url}\a\xF0\x9F\x93\x8B ${ticket}\033]8;;\a")
    else
      links+=("\xF0\x9F\x93\x8B ${ticket}")
    fi
  fi

  # Localhost port
  if [ -n "$port" ]; then
    local localhost_url="http://localhost:${port}"
    links+=("\033]8;;${localhost_url}\a\xF0\x9F\x8C\x90 localhost:${port}\033]8;;\a")
  fi

  # Custom links from config (read all at once)
  local links_data
  links_data=$(jq -r '(.links // [])[] | "\(.label // "")\t\(.url // "")"' "$meta_file" 2>/dev/null) || true
  if [ -n "$links_data" ]; then
    while IFS=$'\t' read -r label url; do
      if [ -n "$label" ] && [ -n "$url" ]; then
        links+=("\033]8;;${url}\a${label}\033]8;;\a")
      fi
    done <<< "$links_data"
  fi

  if [ ${#links[@]} -gt 0 ]; then
    local links_output="  "
    for ((i=0; i<${#links[@]}; i++)); do
      if [ $i -gt 0 ]; then
        links_output="$links_output  \033[2m|\033[0m  "
      fi
      links_output="$links_output${links[$i]}"
    done
    echo -e "$links_output"
  fi
}

# Render the interactive actions line (line 2 of info bar)
# Optional $2: override pull label (e.g. "Pulling..." or "✓ Pulled")
render_infobar_actions() {
  local dir="$1"
  local pull_label="${2:-Pull}"

  local lock_label
  if [ -f "$dir/.crabterm-lock" ]; then
    lock_label="Unlock"
  else
    lock_label="Lock"
  fi

  # Dim for brackets/separators, default text for action names
  local dim="\033[2m"
  local bold="\033[1m"
  local reset="\033[0m"

  echo -e "  ${dim}[${reset}${bold}c${reset}${dim}]${reset} Cleanup  ${dim}|${reset}  ${dim}[${reset}${bold}u${reset}${dim}]${reset} ${lock_label}  ${dim}|${reset}  ${dim}[${reset}${bold}p${reset}${dim}]${reset} ${pull_label}  ${dim}|${reset}  ${dim}[${reset}${bold}k${reset}${dim}]${reset} Kill  ${dim}|${reset}  ${dim}[${reset}${bold}q${reset}${dim}]${reset} Quit"
}

# Return the shell command to run in the info bar pane (interactive loop)
# Writes a bash script to ensure consistent `read -n 1` behavior (zsh uses -k)
get_infobar_command() {
  local dir="$1"
  local crabterm_bin
  crabterm_bin=$(realpath "$CRABTERM_DIR/crabterm" 2>/dev/null || echo "$CRABTERM_DIR/crabterm")

  local script_file="$dir/.crabterm-infobar.sh"
  cat > "$script_file" << CRABTERM_INFOBAR
#!/usr/bin/env bash
while true; do
  _out=\$('$crabterm_bin' _infobar-render '$dir' 2>/dev/null)
  printf '\e[H\e[J%s' "\$_out"
  read -t 60 -n 1 -s _k 2>/dev/null || _k=''
  case \$_k in
    c|C)
      printf '\nCleanup workspace? (reset to origin/main, unlock) [y/N] '
      read -n 1 -s _confirm
      echo
      if [ "\$_confirm" = 'y' ] || [ "\$_confirm" = 'Y' ]; then
        '$crabterm_bin' _cleanup-workspace '$dir' 2>/dev/null
        cd "\$HOME" && clear
        exec "\${SHELL:-/bin/zsh}" -l
      fi
      ;;
    u|U)
      if [ -f '$dir/.crabterm-lock' ]; then
        rm -f '$dir/.crabterm-lock'
        printf '\n\033[32m✓ Unlocked\033[0m'
      else
        touch '$dir/.crabterm-lock'
        printf '\n\033[32m✓ Locked\033[0m'
      fi
      sleep 1
      ;;
    p|P)
      _out=\$('$crabterm_bin' _infobar-render '$dir' 'Pulling...' 2>/dev/null)
      printf '\e[H\e[J%s' "\$_out"
      cd '$dir' && git pull 2>/dev/null
      _out=\$('$crabterm_bin' _infobar-render '$dir' '✓ Pulled' 2>/dev/null)
      printf '\e[H\e[J%s' "\$_out"
      sleep 2
      ;;
    k|K)
      printf '\nKilling ports...\n'
      '$crabterm_bin' _kill-ports '$dir' 2>/dev/null
      sleep 2
      ;;
    q|Q)
      printf '\nQuit workspace? [y/N] '
      read -n 1 -s _confirm
      echo
      if [ "\$_confirm" = 'y' ] || [ "\$_confirm" = 'Y' ]; then
        '$crabterm_bin' _quit-workspace '$dir' 2>/dev/null
        cd "\$HOME" && clear
        exec "\${SHELL:-/bin/zsh}" -l
      fi
      ;;
  esac
done
CRABTERM_INFOBAR
  chmod +x "$script_file"

  echo "bash '$script_file'"
}
