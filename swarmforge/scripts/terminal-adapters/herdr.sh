#!/usr/bin/env zsh

terminal_backend_label() {
  echo "herdr"
}

terminal_backend_can_open_sessions() {
  # Sessions are opened directly by swarmforge.bb for herdr — adapter is not used for launch
  return 1
}

terminal_backend_tracks_windows() {
  return 1
}

terminal_window_exists() {
  local pane_id="$1"
  [[ -n "$pane_id" ]] || return 1
  herdr pane get "$pane_id" >/dev/null 2>&1
}

terminal_open_session() {
  # Not used for herdr — swarmforge.bb calls herdr directly
  return 1
}

terminal_close_window() {
  local pane_id="$1"
  [[ -n "$pane_id" ]] || return 0
  herdr pane close "$pane_id" >/dev/null 2>&1 || true
}
