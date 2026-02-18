#!/usr/bin/env bash
# crabterm - iTerm2 terminal setup (keyboard shortcuts, preferences)

# iTerm2 key binding action IDs (from iTermKeyBindingMgr.h)
_ITERM_ACTION_SELECT_PANE_LEFT=18
_ITERM_ACTION_SELECT_PANE_RIGHT=19
_ITERM_ACTION_SELECT_PANE_ABOVE=20
_ITERM_ACTION_SELECT_PANE_BELOW=21

# Modifier flags
_ITERM_MOD_CONTROL="0x40000"

# Set a global iTerm2 key binding via PlistBuddy
# Usage: _iterm_set_keybinding <hex_char> <hex_modifier> <action_id>
_iterm_set_keybinding() {
  local key="$1-$2"
  local action="$3"
  local plist="$HOME/Library/Preferences/com.googlecode.iterm2.plist"

  # Ensure GlobalKeyMap exists
  /usr/libexec/PlistBuddy -c "Add :GlobalKeyMap dict" "$plist" 2>/dev/null || true

  # Remove existing binding if present
  /usr/libexec/PlistBuddy -c "Delete :GlobalKeyMap:'$key'" "$plist" 2>/dev/null || true

  # Add the binding
  /usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:'$key' dict" "$plist"
  /usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:'$key':Action integer $action" "$plist"
  /usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:'$key':Text string ''" "$plist"
}

setup_terminal() {
  if ! iterm_is_installed; then
    error "iTerm2 is not installed"
    return 1
  fi

  echo -e "${CYAN}Crabterm Terminal Setup${NC}"
  echo ""
  echo "This will add global iTerm2 keyboard shortcuts:"
  echo ""
  echo -e "  ${GREEN}Ctrl+H${NC}  Move to pane left"
  echo -e "  ${GREEN}Ctrl+J${NC}  Move to pane below"
  echo -e "  ${GREEN}Ctrl+K${NC}  Move to pane above"
  echo -e "  ${GREEN}Ctrl+L${NC}  Move to pane right"
  echo ""
  echo -e "  ${GRAY}Note: Ctrl+L (clear screen) will be overridden.${NC}"
  echo -e "  ${GRAY}Use 'clear' or Cmd+K to clear the terminal instead.${NC}"
  echo ""
  read -p "Apply these shortcuts? [Y/n]: " confirm
  if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
    echo "Cancelled."
    return
  fi

  echo ""

  # Ctrl+H (h=0x68) → Select Pane Left
  _iterm_set_keybinding "0x68" "$_ITERM_MOD_CONTROL" "$_ITERM_ACTION_SELECT_PANE_LEFT"
  echo -e "  ${GREEN}✓${NC} Ctrl+H → Select Pane Left"

  # Ctrl+J (j=0x6a) → Select Pane Below
  _iterm_set_keybinding "0x6a" "$_ITERM_MOD_CONTROL" "$_ITERM_ACTION_SELECT_PANE_BELOW"
  echo -e "  ${GREEN}✓${NC} Ctrl+J → Select Pane Below"

  # Ctrl+K (k=0x6b) → Select Pane Above
  _iterm_set_keybinding "0x6b" "$_ITERM_MOD_CONTROL" "$_ITERM_ACTION_SELECT_PANE_ABOVE"
  echo -e "  ${GREEN}✓${NC} Ctrl+K → Select Pane Above"

  # Ctrl+L (l=0x6c) → Select Pane Right
  _iterm_set_keybinding "0x6c" "$_ITERM_MOD_CONTROL" "$_ITERM_ACTION_SELECT_PANE_RIGHT"
  echo -e "  ${GREEN}✓${NC} Ctrl+L → Select Pane Right"

  echo ""

  if iterm_is_running; then
    echo -e "${YELLOW}Restart iTerm2 for shortcuts to take effect.${NC}"
  else
    success "Shortcuts saved. They'll be active next time iTerm2 starts."
  fi
}
