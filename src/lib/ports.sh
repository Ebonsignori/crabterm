#!/usr/bin/env bash
# crabterm - port management

# Find an available port starting from a base
find_available_port() {
  local base_port=$1
  local port=$base_port
  while lsof -i ":$port" &>/dev/null; do
    port=$((port + 1))
    if [ $port -gt $((base_port + 100)) ]; then
      echo "$base_port"
      return
    fi
  done
  echo "$port"
}

# Get workspace ports (api and app) for workspace N
# Returns: api_port:app_port:need_override:env_api:env_app
get_workspace_ports() {
  local num=$1
  local dir=$2

  local port_spacing=$(yq -r '.env_sync.port_spacing // 10' "$CONFIG_FILE" 2>/dev/null)
  [ "$port_spacing" = "null" ] && port_spacing=10

  local default_api=$((API_PORT_BASE + (num * port_spacing)))
  local default_app=$((APP_PORT_BASE + (num * port_spacing)))

  local env_api=$(read_env_port "$dir" "api")
  local env_app=$(read_env_port "$dir" "app")

  [ -z "$env_api" ] && env_api="$default_api"
  [ -z "$env_app" ] && env_app="$default_app"

  local actual_api=$(find_available_port "$env_api")
  local actual_app=$(find_available_port "$env_app")

  local need_override="false"
  if [ "$actual_api" != "$env_api" ] || [ "$actual_app" != "$env_app" ]; then
    need_override="true"
  fi

  echo "$actual_api:$actual_app:$need_override:$env_api:$env_app"
}

# Read port from .env file based on env_sync config
read_env_port() {
  local dir=$1
  local port_type=$2

  local env_files_count=$(yq -r '.env_sync.files | length // 0' "$CONFIG_FILE" 2>/dev/null)

  for ((i=0; i<env_files_count; i++)); do
    local env_path=$(yq -r ".env_sync.files[$i].path" "$CONFIG_FILE" 2>/dev/null)
    local port_var=$(yq -r ".env_sync.files[$i].port_var" "$CONFIG_FILE" 2>/dev/null)

    [ -z "$env_path" ] || [ "$env_path" = "null" ] && continue

    local full_path="$dir/$env_path"
    if [ -f "$full_path" ] && [ -n "$port_var" ] && [ "$port_var" != "null" ]; then
      local value=$(grep "^${port_var}=" "$full_path" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')
      if [ -n "$value" ]; then
        if [[ "$value" =~ :([0-9]+) ]]; then
          echo "${BASH_REMATCH[1]}"
          return
        elif [[ "$value" =~ ^[0-9]+$ ]]; then
          echo "$value"
          return
        fi
      fi
    fi
  done
}

# Sync .env files for a workspace
sync_env_files() {
  local dir=$1
  local workspace_num=$2
  local quiet=${3:-false}

  local env_files_count=$(yq -r '.env_sync.files | length // 0' "$CONFIG_FILE" 2>/dev/null)
  [ "$env_files_count" = "0" ] && return

  local ports_file=$(mktemp)
  trap "rm -f '$ports_file'" RETURN

  # First pass: resolve all managed ports
  for ((i=0; i<env_files_count; i++)); do
    local env_path=$(yq -r ".env_sync.files[$i].path" "$CONFIG_FILE" 2>/dev/null)
    local copy_from=$(yq -r ".env_sync.files[$i].copy_from // \"\"" "$CONFIG_FILE" 2>/dev/null)

    [ -z "$env_path" ] || [ "$env_path" = "null" ] && continue

    local full_path="$dir/$env_path"
    local source_path=""

    # Determine source: explicit copy_from (relative to main repo), or default to same path in main repo
    if [ -n "$copy_from" ] && [ "$copy_from" != "null" ]; then
      source_path="$MAIN_REPO/$copy_from"
    else
      source_path="$MAIN_REPO/$env_path"
    fi

    # Copy from main repo if workspace .env doesn't exist yet
    if [ ! -f "$full_path" ] && [ -f "$source_path" ]; then
      mkdir -p "$(dirname "$full_path")"
      cp "$source_path" "$full_path"
      [ "$quiet" != "true" ] && echo -e "  ${YELLOW}Created $env_path from main repo${NC}"
    fi

    # Apply overrides from config
    if [ -f "$full_path" ]; then
      local override_keys=$(yq -r ".env_sync.files[$i].overrides // {} | keys | .[]" "$CONFIG_FILE" 2>/dev/null)
      if [ -n "$override_keys" ]; then
        echo "$override_keys" | while read -r key; do
          [ -z "$key" ] && continue
          local value=$(yq -r ".env_sync.files[$i].overrides[\"$key\"]" "$CONFIG_FILE" 2>/dev/null)
          [ -z "$value" ] || [ "$value" = "null" ] && continue
          if grep -q "^${key}=" "$full_path" 2>/dev/null; then
            sed -i '' "s|^${key}=.*|${key}=$value|" "$full_path"
          else
            echo "${key}=$value" >> "$full_path"
          fi
          [ "$quiet" != "true" ] && echo -e "  ${GREEN}$env_path: override $key=$value${NC}"
        done
      fi
    fi

    [ ! -f "$full_path" ] && continue

    local ports_json=$(yq -r ".env_sync.files[$i].ports // []" "$CONFIG_FILE" 2>/dev/null)
    local old_port_var=$(yq -r ".env_sync.files[$i].port_var // \"\"" "$CONFIG_FILE" 2>/dev/null)

    if [ -n "$old_port_var" ] && [ "$old_port_var" != "null" ]; then
      ports_json="[\"$old_port_var\"]"
    fi

    local ports_count=$(echo "$ports_json" | yq -r 'length // 0' 2>/dev/null)
    for ((p=0; p<ports_count; p++)); do
      local port_var=$(echo "$ports_json" | yq -r ".[$p]" 2>/dev/null)
      [ -z "$port_var" ] || [ "$port_var" = "null" ] && continue

      local base_value=""
      local main_env="$MAIN_REPO/$env_path"
      [ -f "$main_env" ] && base_value=$(grep "^${port_var}=" "$main_env" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'"'")

      if [ -z "$base_value" ]; then
        base_value=$(grep "^${port_var}=" "$full_path" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'"'")
      fi

      local current_value=$(grep "^${port_var}=" "$full_path" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'"'")
      [ -z "$current_value" ] && current_value="$base_value"

      local base_port=""
      if echo "$base_value" | grep -qE '^[0-9]+$'; then
        base_port="$base_value"
      elif echo "$base_value" | grep -qE ':[0-9]+'; then
        base_port=$(echo "$base_value" | grep -oE ':[0-9]+' | tail -1 | tr -d ':')
      fi

      [ -z "$base_port" ] && continue

      local port_spacing=$(yq -r '.env_sync.port_spacing // 10' "$CONFIG_FILE" 2>/dev/null)
      [ "$port_spacing" = "null" ] && port_spacing=10

      local new_port=$((base_port + (workspace_num * port_spacing)))

      while lsof -i ":$new_port" &>/dev/null; do
        new_port=$((new_port + 1))
        if [ $new_port -gt $((base_port + (workspace_num * port_spacing) + port_spacing - 1)) ]; then
          new_port=$((base_port + (workspace_num * port_spacing)))
          break
        fi
      done

      echo "$port_var=$new_port" >> "$ports_file"

      local new_value
      if echo "$current_value" | grep -qE '^[0-9]+$'; then
        new_value="$new_port"
      else
        new_value=$(echo "$current_value" | sed "s/:${base_port}/:${new_port}/g")
      fi

      if [ "$current_value" != "$new_value" ]; then
        sed -i '' "s|^${port_var}=.*|${port_var}=$new_value|" "$full_path"
        [ "$quiet" != "true" ] && echo -e "  ${GREEN}$env_path: $port_var → $new_port${NC}"
      fi
    done
  done

  # Second pass: process refs
  for ((i=0; i<env_files_count; i++)); do
    local env_path=$(yq -r ".env_sync.files[$i].path" "$CONFIG_FILE" 2>/dev/null)
    [ -z "$env_path" ] || [ "$env_path" = "null" ] && continue

    local full_path="$dir/$env_path"
    [ ! -f "$full_path" ] && continue

    local refs_keys=$(yq -r ".env_sync.files[$i].refs // {} | keys | .[]" "$CONFIG_FILE" 2>/dev/null)
    [ -z "$refs_keys" ] && continue

    echo "$refs_keys" | while read -r ref_var; do
      [ -z "$ref_var" ] && continue

      local ref_source=$(yq -r ".env_sync.files[$i].refs[\"$ref_var\"]" "$CONFIG_FILE" 2>/dev/null)
      [ -z "$ref_source" ] || [ "$ref_source" = "null" ] && continue

      local extract_port_only=false
      local ref_port_var="$ref_source"
      if [[ "$ref_source" == *":port" ]]; then
        extract_port_only=true
        ref_port_var="${ref_source%:port}"
      fi

      local resolved_port=$(grep "^${ref_port_var}=" "$ports_file" 2>/dev/null | cut -d= -f2)
      [ -z "$resolved_port" ] && continue

      local current_value=$(grep "^${ref_var}=" "$full_path" 2>/dev/null | cut -d= -f2-)

      if [ "$extract_port_only" = true ]; then
        if [ "$current_value" != "$resolved_port" ]; then
          sed -i '' "s|^${ref_var}=.*|${ref_var}=$resolved_port|" "$full_path"
          [ "$quiet" != "true" ] && echo -e "  ${GREEN}$env_path: $ref_var → $resolved_port${NC}"
        fi
      else
        [ -z "$current_value" ] && continue
        local current_port=$(echo "$current_value" | grep -oE ':[0-9]+' | tail -1 | tr -d ':')
        [ -z "$current_port" ] && continue

        if [ "$current_port" != "$resolved_port" ]; then
          local new_value=$(echo "$current_value" | sed "s/:${current_port}/:${resolved_port}/g")
          sed -i '' "s|^${ref_var}=.*|${ref_var}=$new_value|" "$full_path"
          [ "$quiet" != "true" ] && echo -e "  ${GREEN}$env_path: $ref_var → :$resolved_port${NC}"
        fi
      fi
    done
  done
}

# Helper: add a port to _kill_ports array if not already present
_add_port() {
  local port="$1"
  [ -z "$port" ] && return
  for existing in "${_kill_ports[@]:-}"; do
    [ "$existing" = "$port" ] && return
  done
  _kill_ports+=("$port")
}

# Helper: extract port number from a value (plain number or URL like http://localhost:3200)
_extract_port() {
  local value="$1"
  if echo "$value" | grep -qE '^[0-9]+$'; then
    echo "$value"
  elif echo "$value" | grep -qE ':[0-9]+'; then
    echo "$value" | grep -oE ':[0-9]+' | tail -1 | tr -d ':'
  fi
}

# Kill processes running in a workspace
# Two-phase approach:
#   Phase 1: Use cleanup.kill_pattern to find processes by workspace directory name
#            (most reliable — same approach used by cleanup/destroy)
#   Phase 2: Kill any remaining listeners on managed ports from .env files or config
#
# For port-based kills, uses -sTCP:LISTEN to find only server processes (not browser
# client connections), then kills the entire process group so parent dev tools
# (pnpm, npm, etc.) can't respawn children.
kill_workspace_ports() {
  local dir="$1"
  local quiet="${2:-false}"

  local killed=0
  local pgids_killed=()

  # Extract workspace number from directory name
  local num=""
  if [[ "$(basename "$dir")" =~ -([0-9]+)$ ]]; then
    num="${BASH_REMATCH[1]}"
  fi

  # --- Phase 1: kill_pattern (process name matching) ---
  local kill_pattern=$(config_get "cleanup.kill_pattern" "")
  if [ -n "$kill_pattern" ] && [ -n "$num" ]; then
    kill_pattern="${kill_pattern//\{N\}/$num}"
    kill_pattern="${kill_pattern//\{PREFIX\}/$WORKSPACE_PREFIX}"

    local pattern_pids=$(pgrep -f "$kill_pattern" 2>/dev/null)
    if [ -n "$pattern_pids" ]; then
      # Kill by process group to get parent + children
      for pid in $pattern_pids; do
        local pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
        if [ -n "$pgid" ] && [ "$pgid" -gt 1 ] 2>/dev/null; then
          local already_killed=false
          for kpg in "${pgids_killed[@]:-}"; do
            [ "$kpg" = "$pgid" ] && already_killed=true && break
          done
          [ "$already_killed" = true ] && continue

          [ "$quiet" != "true" ] && echo -e "  ${YELLOW}Killing process group $pgid${NC}"
          kill -9 -"$pgid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
          pgids_killed+=("$pgid")
          killed=$((killed + 1))
        else
          [ "$quiet" != "true" ] && echo -e "  ${YELLOW}Killing pid $pid${NC}"
          kill -9 "$pid" 2>/dev/null || true
          killed=$((killed + 1))
        fi
      done
    fi
  fi

  # --- Phase 2: port-based kill for any remaining listeners ---
  _kill_ports=()

  # Strategy A: env_sync managed ports from workspace .env files
  local env_files_count=$(yq -r '.env_sync.files | length // 0' "$CONFIG_FILE" 2>/dev/null)
  for ((i=0; i<env_files_count; i++)); do
    local env_path=$(yq -r ".env_sync.files[$i].path" "$CONFIG_FILE" 2>/dev/null)
    [ -z "$env_path" ] || [ "$env_path" = "null" ] && continue

    # Check workspace .env, fall back to main repo .env for base ports
    local full_path="$dir/$env_path"
    [ -f "$full_path" ] || full_path="$MAIN_REPO/$env_path"
    [ -f "$full_path" ] || continue

    local ports_json=$(yq -r ".env_sync.files[$i].ports // []" "$CONFIG_FILE" 2>/dev/null)
    local old_port_var=$(yq -r ".env_sync.files[$i].port_var // \"\"" "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$old_port_var" ] && [ "$old_port_var" != "null" ]; then
      ports_json="[\"$old_port_var\"]"
    fi

    local ports_count=$(echo "$ports_json" | yq -r 'length // 0' 2>/dev/null)
    for ((p=0; p<ports_count; p++)); do
      local port_var=$(echo "$ports_json" | yq -r ".[$p]" 2>/dev/null)
      [ -z "$port_var" ] || [ "$port_var" = "null" ] && continue

      local value=$(grep "^${port_var}=" "$full_path" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]"'"'")
      [ -z "$value" ] && continue
      _add_port "$(_extract_port "$value")"
    done
  done

  # Strategy B: scan all .env files for PORT-like variables
  if [ ${#_kill_ports[@]} -eq 0 ]; then
    local env_file
    while IFS= read -r env_file; do
      [ -f "$env_file" ] || continue
      while IFS= read -r line; do
        local value="${line#*=}"
        value=$(echo "$value" | tr -d '[:space:]"'"'")
        local port=$(_extract_port "$value")
        if [ -n "$port" ] && [ "$port" -ge 1024 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null; then
          _add_port "$port"
        fi
      done < <(grep -E '^[A-Z_]*PORT[A-Z_]*=' "$env_file" 2>/dev/null)
    done < <(find "$dir" -maxdepth 2 -name '.env' -not -path '*/node_modules/*' 2>/dev/null)
  fi

  # Strategy C: compute from ports config
  if [ ${#_kill_ports[@]} -eq 0 ]; then
    local port_spacing=$(yq -r '.env_sync.port_spacing // 10' "$CONFIG_FILE" 2>/dev/null)
    [ "$port_spacing" = "null" ] && port_spacing=10

    if [ -n "$num" ]; then
      [ -n "$API_PORT_BASE" ] && [ "$API_PORT_BASE" != "0" ] && _add_port "$((API_PORT_BASE + (num * port_spacing)))"
      [ -n "$APP_PORT_BASE" ] && [ "$APP_PORT_BASE" != "0" ] && _add_port "$((APP_PORT_BASE + (num * port_spacing)))"
    else
      [ -n "$API_PORT_BASE" ] && [ "$API_PORT_BASE" != "0" ] && _add_port "$API_PORT_BASE"
      [ -n "$APP_PORT_BASE" ] && [ "$APP_PORT_BASE" != "0" ] && _add_port "$APP_PORT_BASE"
    fi
  fi

  # Kill remaining listeners on discovered ports
  for port in "${_kill_ports[@]:-}"; do
    [ -z "$port" ] && continue

    local pids=$(lsof -ti "TCP:$port" -sTCP:LISTEN 2>/dev/null)
    if [ -z "$pids" ]; then
      [ $killed -eq 0 ] && [ "$quiet" != "true" ] && echo -e "  ${GRAY}Port $port not in use${NC}"
      continue
    fi

    for pid in $pids; do
      local pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
      if [ -n "$pgid" ] && [ "$pgid" -gt 1 ] 2>/dev/null; then
        local already_killed=false
        for kpg in "${pgids_killed[@]:-}"; do
          [ "$kpg" = "$pgid" ] && already_killed=true && break
        done
        [ "$already_killed" = true ] && continue

        [ "$quiet" != "true" ] && echo -e "  ${YELLOW}Killing port $port (process group $pgid)${NC}"
        kill -9 -"$pgid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
        pgids_killed+=("$pgid")
        killed=$((killed + 1))
      else
        [ "$quiet" != "true" ] && echo -e "  ${YELLOW}Killing port $port (pid $pid)${NC}"
        kill -9 "$pid" 2>/dev/null || true
        killed=$((killed + 1))
      fi
    done
  done

  if [ $killed -eq 0 ]; then
    [ "$quiet" != "true" ] && echo -e "  ${GRAY}No processes found to kill${NC}"
  else
    [ "$quiet" != "true" ] && echo -e "  ${GREEN}✓ Killed $killed process(es)${NC}"
  fi
}

# Show port usage across all workspaces
show_ports() {
  load_config
  validate_config

  echo -e "${CYAN}Port Usage Across Workspaces${NC}"
  echo ""
  printf "  %-20s %-8s %-8s %-20s\n" "WORKSPACE" "API" "APP" "STATUS"
  echo "  ────────────────────────────────────────────────────────"

  for ((i=1; i<=WORKSPACE_COUNT; i++)); do
    local dir="$WORKSPACE_BASE/$WORKSPACE_PREFIX-$i"
    if [ ! -d "$dir" ]; then
      continue
    fi

    local port_spacing=$(yq -r '.env_sync.port_spacing // 10' "$CONFIG_FILE" 2>/dev/null)
    [ "$port_spacing" = "null" ] && port_spacing=10
    local default_api=$((API_PORT_BASE + (i * port_spacing)))
    local default_app=$((APP_PORT_BASE + (i * port_spacing)))
    local api_port=$(read_env_port "$dir" "api")
    local app_port=$(read_env_port "$dir" "app")
    [ -z "$api_port" ] && api_port="$default_api"
    [ -z "$app_port" ] && app_port="$default_app"

    local api_status="free"
    if lsof -i ":$api_port" &>/dev/null; then
      local pid=$(lsof -t -i ":$api_port" 2>/dev/null | head -1)
      local cwd=$(lsof -p "$pid" 2>/dev/null | grep cwd | awk '{print $NF}')
      if [[ "$cwd" == *"$WORKSPACE_PREFIX-$i"* ]]; then
        api_status="running"
      elif [[ "$cwd" == *"$WORKSPACE_PREFIX-"* ]]; then
        local other_ws=$(echo "$cwd" | grep -oE "${WORKSPACE_PREFIX}-[0-9]+" | sed "s/${WORKSPACE_PREFIX}-/ws/")
        api_status="TAKEN:$other_ws"
      else
        api_status="in-use"
      fi
    fi

    local app_status="free"
    if lsof -i ":$app_port" &>/dev/null; then
      local pid=$(lsof -t -i ":$app_port" 2>/dev/null | head -1)
      local cwd=$(lsof -p "$pid" 2>/dev/null | grep cwd | awk '{print $NF}')
      if [[ "$cwd" == *"$WORKSPACE_PREFIX-$i"* ]]; then
        app_status="running"
      elif [[ "$cwd" == *"$WORKSPACE_PREFIX-"* ]]; then
        local other_ws=$(echo "$cwd" | grep -oE "${WORKSPACE_PREFIX}-[0-9]+" | sed "s/${WORKSPACE_PREFIX}-/ws/")
        app_status="TAKEN:$other_ws"
      else
        app_status="in-use"
      fi
    fi

    local api_display app_display
    case "$api_status" in
      "free") api_display="${YELLOW}free${NC}" ;;
      "running") api_display="${GREEN}●${NC}" ;;
      TAKEN:*) api_display="${RED}${api_status}${NC}" ;;
      *) api_display="${YELLOW}busy${NC}" ;;
    esac
    case "$app_status" in
      "free") app_display="${YELLOW}free${NC}" ;;
      "running") app_display="${GREEN}●${NC}" ;;
      TAKEN:*) app_display="${RED}${app_status}${NC}" ;;
      *) app_display="${YELLOW}busy${NC}" ;;
    esac

    printf "  %-20s %-8s %-8s " "$WORKSPACE_PREFIX-$i" "$api_port" "$app_port"
    echo -e "API: $api_display  APP: $app_display"
  done
  echo ""
  echo -e "  Legend: ${GREEN}●${NC}=running  ${YELLOW}free${NC}=available  ${RED}TAKEN:wsN${NC}=conflict"
}
