#!/usr/bin/env bash
# crabterm - iTerm2 terminal setup (keyboard shortcuts, preferences)

# iTerm2 key binding action IDs (from iTermKeyBindingMgr.h)
_ITERM_ACTION_SELECT_PANE_LEFT=18
_ITERM_ACTION_SELECT_PANE_RIGHT=19
_ITERM_ACTION_SELECT_PANE_ABOVE=20
_ITERM_ACTION_SELECT_PANE_BELOW=21

# Modifier flags
_ITERM_MOD_CONTROL="0x40000"

# Virtual keycodes for HJKL (macOS kVK_ANSI_* values)
_ITERM_VK_H="0x4"
_ITERM_VK_J="0x26"
_ITERM_VK_K="0x28"
_ITERM_VK_L="0x25"

# Set an iTerm2 key binding in both GlobalKeyMap and all profiles
# Usage: _iterm_set_keybinding <hex_char> <hex_modifier> <virtual_keycode> <action_id>
_iterm_set_keybinding() {
  local hex_char="$1"
  local hex_modifier="$2"
  local virtual_keycode="$3"
  local action="$4"
  local plist="$HOME/Library/Preferences/com.googlecode.iterm2.plist"

  # --- Global key map (legacy format: char-modifier) ---
  local global_key="$hex_char-$hex_modifier"
  /usr/libexec/PlistBuddy -c "Add :GlobalKeyMap dict" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :GlobalKeyMap:'$global_key'" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:'$global_key' dict" "$plist"
  /usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:'$global_key':Action integer $action" "$plist"
  /usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:'$global_key':Text string ''" "$plist"

  # --- Profile key maps (v2 format: char-modifier-keycode) ---
  local profile_key="$hex_char-$hex_modifier-$virtual_keycode"
  local i=0
  while /usr/libexec/PlistBuddy -c "Print :New\ Bookmarks:$i:Guid" "$plist" &>/dev/null; do
    local kb_path=":New Bookmarks:$i:Keyboard Map"

    # Ensure Keyboard Map exists
    /usr/libexec/PlistBuddy -c "Add '$kb_path' dict" "$plist" 2>/dev/null || true

    # Remove existing binding if present
    /usr/libexec/PlistBuddy -c "Delete '$kb_path':'$profile_key'" "$plist" 2>/dev/null || true

    # Add the v2 binding
    /usr/libexec/PlistBuddy -c "Add '$kb_path':'$profile_key' dict" "$plist"
    /usr/libexec/PlistBuddy -c "Add '$kb_path':'$profile_key':Action integer $action" "$plist"
    /usr/libexec/PlistBuddy -c "Add '$kb_path':'$profile_key':Text string ''" "$plist"
    /usr/libexec/PlistBuddy -c "Add '$kb_path':'$profile_key':Version integer 2" "$plist"
    /usr/libexec/PlistBuddy -c "Add '$kb_path':'$profile_key':Apply\ Mode integer 0" "$plist"
    /usr/libexec/PlistBuddy -c "Add '$kb_path':'$profile_key':Escaping integer 2" "$plist"

    i=$((i + 1))
  done
}

_setup_paste_image_script() {
  local scripts_dir="$HOME/Library/Application Support/iTerm2/Scripts/AutoLaunch"
  local script_src="$CRABTERM_DIR/lib/scripts/paste_image.py"
  local script_dst="$scripts_dir/paste_image.py"

  if [ ! -f "$script_src" ]; then
    warn "paste_image.py not found in crabterm installation"
    return 1
  fi

  mkdir -p "$scripts_dir"
  cp "$script_src" "$script_dst"
  echo -e "  ${GREEN}✓${NC} Installed paste_image.py to iTerm2 AutoLaunch"

  # Enable the Python API if not already enabled
  defaults write com.googlecode.iterm2 EnableAPIServer -bool true 2>/dev/null || true
  echo -e "  ${GREEN}✓${NC} iTerm2 Python API enabled"
}

setup_terminal() {
  if ! iterm_is_installed; then
    error "iTerm2 is not installed"
    return 1
  fi

  echo -e "${CYAN}Crabterm Terminal Setup${NC}"
  echo ""
  echo "This will configure:"
  echo ""
  echo -e "  ${BOLD}Keyboard shortcuts${NC}"
  echo -e "  ${GREEN}Ctrl+H${NC}  Move to pane left"
  echo -e "  ${GREEN}Ctrl+J${NC}  Move to pane below"
  echo -e "  ${GREEN}Ctrl+K${NC}  Move to pane above"
  echo -e "  ${GREEN}Ctrl+L${NC}  Move to pane right"
  echo ""
  echo -e "  ${BOLD}Clipboard image paste${NC}"
  echo -e "  ${GREEN}Cmd+Shift+V${NC}  Paste clipboard image as file path"
  echo -e "  ${GRAY}Useful for pasting screenshots into Claude Code${NC}"
  echo ""
  echo -e "  ${GRAY}Note: Ctrl+L (clear screen) will be overridden.${NC}"
  echo -e "  ${GRAY}Use 'clear' or Cmd+K to clear the terminal instead.${NC}"
  echo ""
  read -p "Apply these settings? [Y/n]: " confirm
  if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
    echo "Cancelled."
    return
  fi

  echo ""
  echo -e "${BOLD}Keyboard shortcuts:${NC}"

  # Ctrl+H (h=0x68, vk=0x4) → Select Pane Left
  _iterm_set_keybinding "0x68" "$_ITERM_MOD_CONTROL" "$_ITERM_VK_H" "$_ITERM_ACTION_SELECT_PANE_LEFT"
  echo -e "  ${GREEN}✓${NC} Ctrl+H → Select Pane Left"

  # Ctrl+J (j=0x6a, vk=0x26) → Select Pane Below
  _iterm_set_keybinding "0x6a" "$_ITERM_MOD_CONTROL" "$_ITERM_VK_J" "$_ITERM_ACTION_SELECT_PANE_BELOW"
  echo -e "  ${GREEN}✓${NC} Ctrl+J → Select Pane Below"

  # Ctrl+K (k=0x6b, vk=0x28) → Select Pane Above
  _iterm_set_keybinding "0x6b" "$_ITERM_MOD_CONTROL" "$_ITERM_VK_K" "$_ITERM_ACTION_SELECT_PANE_ABOVE"
  echo -e "  ${GREEN}✓${NC} Ctrl+K → Select Pane Above"

  # Ctrl+L (l=0x6c, vk=0x25) → Select Pane Right
  _iterm_set_keybinding "0x6c" "$_ITERM_MOD_CONTROL" "$_ITERM_VK_L" "$_ITERM_ACTION_SELECT_PANE_RIGHT"
  echo -e "  ${GREEN}✓${NC} Ctrl+L → Select Pane Right"

  echo ""
  echo -e "${BOLD}Clipboard image paste:${NC}"
  _setup_paste_image_script

  echo ""

  # Mark setup as completed in global config
  if [ -f "$GLOBAL_CONFIG" ]; then
    yq -i '.setup_completed = true' "$GLOBAL_CONFIG"
  else
    mkdir -p "$CONFIG_DIR"
    cat > "$GLOBAL_CONFIG" << EOF
# Crabterm Global Configuration
setup_completed: true
EOF
  fi

  if iterm_is_running; then
    echo -e "${YELLOW}Restart iTerm2 for all changes to take effect.${NC}"
  else
    success "Settings saved. They'll be active next time iTerm2 starts."
  fi
}

check_setup_reminder() {
  local setup_done=""
  if [ -f "$GLOBAL_CONFIG" ]; then
    setup_done=$(yq -r '.setup_completed // ""' "$GLOBAL_CONFIG" 2>/dev/null)
  fi
  if [ "$setup_done" != "true" ]; then
    echo -e "${YELLOW}Tip:${NC} Run ${GREEN}crab setup${NC} to configure iTerm2 shortcuts and clipboard image paste"
    echo ""
  fi
}
