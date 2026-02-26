#!/usr/bin/env bash
# crabterm - common utilities
# Colors, version, config paths, utility functions

VERSION="0.1.0"
CONFIG_DIR="$HOME/.crabterm"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
WIP_BASE="$CONFIG_DIR/wip"
PROJECTS_DIR="$CONFIG_DIR/projects"
GLOBAL_CONFIG="$CONFIG_DIR/config.yaml"
PROJECT_ALIAS=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

error() {
  echo -e "${RED}Error: $*${NC}" >&2
}

warn() {
  echo -e "${YELLOW}Warning: $*${NC}" >&2
}

info() {
  echo -e "${CYAN}$*${NC}"
}

success() {
  echo -e "${GREEN}$*${NC}"
}

# Check if a command exists
command_exists() {
  command -v "$1" &>/dev/null
}

# Check required dependencies are installed
check_deps() {
  local missing=0
  if ! command_exists yq; then
    error "yq is required but not installed."
    echo "  Install with: brew install yq"
    missing=$((missing + 1))
  fi
  if ! command_exists git; then
    error "git is required but not installed."
    missing=$((missing + 1))
  fi
  if ! command_exists jq; then
    error "jq is required but not installed."
    echo "  Install with: brew install jq"
    missing=$((missing + 1))
  fi
  if [ ! -d "/Applications/iTerm.app" ] && [ ! -d "$HOME/Applications/iTerm.app" ]; then
    error "iTerm2 is required but not installed."
    echo "  Install from: https://iterm2.com"
    missing=$((missing + 1))
  fi
  if [ $missing -gt 0 ]; then
    exit 1
  fi
}
