#!/usr/bin/env bash
# Crabterm installer (macOS only - requires iTerm2)

set -e

REPO="https://github.com/promptfoo/crabterm"
INSTALL_DIR="${CRABTERM_INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_NAME="crabterm"
ALIAS_NAME="crab"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}Installing crabterm...${NC}"

# Verify macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
  echo -e "${RED}Error: crabterm requires macOS (uses iTerm2 AppleScript).${NC}"
  exit 1
fi

# Verify iTerm2
if [ ! -d "/Applications/iTerm.app" ] && [ ! -d "$HOME/Applications/iTerm.app" ]; then
  echo -e "${RED}Error: iTerm2 not found.${NC}"
  echo "Install from: https://iterm2.com"
  exit 1
fi

# Install dependencies via Homebrew
install_package() {
  local package="$1"
  echo -e "${CYAN}Installing $package...${NC}"
  if command -v brew &>/dev/null; then
    brew install "$package"
  else
    echo -e "${RED}Error: Homebrew not found. Install from https://brew.sh${NC}"
    echo "Then run: brew install $package"
    return 1
  fi
}

echo "Checking dependencies..."

# Check git (required)
if ! command -v git &>/dev/null; then
  echo -e "${YELLOW}git not found. Installing...${NC}"
  install_package git || {
    echo -e "${RED}Error: Failed to install git.${NC}"
    exit 1
  }
fi

# Check yq (required)
if ! command -v yq &>/dev/null; then
  echo -e "${YELLOW}yq not found. Installing...${NC}"
  install_package yq || {
    echo -e "${RED}Error: Failed to install yq. Install manually: brew install yq${NC}"
    exit 1
  }
fi

# Check jq (required for state management)
if ! command -v jq &>/dev/null; then
  echo -e "${YELLOW}jq not found. Installing...${NC}"
  install_package jq || {
    echo -e "${RED}Error: Failed to install jq. Install manually: brew install jq${NC}"
    exit 1
  }
fi

echo -e "${GREEN}All dependencies installed.${NC}"
echo ""

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download the script and lib directory
echo "Downloading crabterm..."
local tmp_dir=$(mktemp -d)
if command -v curl &>/dev/null; then
  curl -fsSL "$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$tmp_dir"
elif command -v wget &>/dev/null; then
  wget -q "$REPO/archive/refs/heads/main.tar.gz" -O - | tar -xz -C "$tmp_dir"
else
  echo -e "${RED}Error: curl or wget required for download.${NC}"
  exit 1
fi

# Install entry point and lib
local src_dir="$tmp_dir/crabterm-main/src"
cp "$src_dir/crabterm" "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Install lib directory alongside the script
mkdir -p "$INSTALL_DIR/lib"
cp -r "$src_dir/lib/"* "$INSTALL_DIR/lib/"

rm -rf "$tmp_dir"

# Create 'crab' symlink
echo "Creating 'crab' alias..."
ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "$INSTALL_DIR/$ALIAS_NAME"

# Add to PATH if needed
add_to_path() {
  local shell_profile=""
  local export_line="export PATH=\"\$PATH:$INSTALL_DIR\""

  case "$SHELL" in
    */zsh)
      shell_profile="$HOME/.zshrc"
      ;;
    */bash)
      if [[ -f "$HOME/.bash_profile" ]]; then
        shell_profile="$HOME/.bash_profile"
      else
        shell_profile="$HOME/.bashrc"
      fi
      ;;
    *)
      shell_profile="$HOME/.profile"
      ;;
  esac

  if [[ -f "$shell_profile" ]] && grep -q "$INSTALL_DIR" "$shell_profile" 2>/dev/null; then
    echo -e "${GREEN}PATH already configured in $shell_profile${NC}"
    return 0
  fi

  echo "" >> "$shell_profile"
  echo "# Added by crabterm installer" >> "$shell_profile"
  echo "$export_line" >> "$shell_profile"

  echo -e "${GREEN}Added $INSTALL_DIR to PATH in $shell_profile${NC}"
  echo -e "${YELLOW}Run 'source $shell_profile' or open a new terminal to use crab${NC}"
}

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo ""
  echo -e "${YELLOW}$INSTALL_DIR is not in your PATH.${NC}"
  add_to_path
  echo ""
fi

echo ""
echo '    \___/'
echo '   ( *_*)  Installation complete!'
echo -e "  /)${GREEN}🦀${NC}(\\"
echo ' <      >'
echo ""
echo "You can use either 'crabterm' or 'crab' command."
echo ""
echo "Next steps:"
echo "  1. Run 'source ~/.zshrc' (or open new terminal)"
echo "  2. Run 'crab init' to create your config"
echo "  3. Run 'crab ws 1' to start your first workspace"
echo ""
echo "Run 'crab cheat' for a quick reference."
