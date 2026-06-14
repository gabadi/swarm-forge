#!/usr/bin/env zsh
set -euo pipefail

if [[ "${1:-}" == "--mux" && "${2:-}" == "cmux" ]]; then
  shift 2
  _cmux_group=""
  if [[ "${1:-}" == "--group" ]]; then
    _cmux_group="$2"
    shift 2
  fi
  if [[ -n "$_cmux_group" ]]; then
    cmux workspace-group delete "$_cmux_group" 2>/dev/null || {
      for _cmux_ws in "$@"; do
        cmux workspace close --workspace "$_cmux_ws" 2>/dev/null || true
      done
    }
  else
    for _cmux_ws in "$@"; do
      cmux workspace close --workspace "$_cmux_ws" 2>/dev/null || true
    done
  fi
  exit 0
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: swarm-cleanup.sh <tmux-socket> <window-ids-file> [session ...]" >&2
  exit 1
fi

TMUX_SOCKET="$1"
WINDOW_IDS_FILE="$2"
TERMINAL_BACKEND="${SWARMFORGE_TERMINAL_BACKEND:-terminal-app}"
WORKING_DIR="$(cd "$(dirname "$WINDOW_IDS_FILE")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
shift
shift

has_command() {
  command -v "$1" &>/dev/null
}

source "$SCRIPT_DIR/swarm-terminal-adapter.sh"
load_terminal_backend "$TERMINAL_BACKEND"

for session in "$@"; do
  tmux -S "$TMUX_SOCKET" kill-session -t "$session" 2>/dev/null || true
done

sleep 1

if [[ -f "$WINDOW_IDS_FILE" ]]; then
  while IFS= read -r window_id; do
    [[ -n "$window_id" ]] || continue
    terminal_close_window "$window_id"
  done < "$WINDOW_IDS_FILE"
fi
