#!/usr/bin/env zsh
set -euo pipefail

WORKING_DIR="${1:-$PWD}"
WORKING_DIR="$(cd "$WORKING_DIR" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$WORKING_DIR/.swarmforge"

if [[ ! -d "$STATE_DIR" ]]; then
  echo "No swarm state found at $STATE_DIR" >&2
  exit 1
fi

MUX_BACKEND=""
if [[ -f "$STATE_DIR/mux-backend" ]]; then
  MUX_BACKEND="$(< "$STATE_DIR/mux-backend")"
fi

if [[ "$MUX_BACKEND" == "cmux" ]]; then
  _group=""
  if [[ -f "$STATE_DIR/cmux-group" ]]; then
    _group="$(< "$STATE_DIR/cmux-group")"
  fi
  _ws_args=()
  if [[ -f "$STATE_DIR/cmux-workspaces" ]]; then
    while IFS= read -r _ws; do
      [[ -n "$_ws" ]] || continue
      _ws_args+=("$_ws")
    done < "$STATE_DIR/cmux-workspaces"
  fi
  exec "$SCRIPT_DIR/swarm-cleanup.sh" --mux cmux --group "$_group" "${_ws_args[@]}"
else
  _tmux_socket=""
  if [[ -f "$STATE_DIR/tmux-socket" ]]; then
    _tmux_socket="$(< "$STATE_DIR/tmux-socket")"
  fi
  _session_args=()
  if [[ -f "$STATE_DIR/sessions.tsv" ]]; then
    while IFS=$'\t' read -r _idx _role _session _display _agent; do
      [[ -n "$_session" ]] || continue
      _session_args+=("$_session")
    done < "$STATE_DIR/sessions.tsv"
  fi
  exec "$SCRIPT_DIR/swarm-cleanup.sh" "$_tmux_socket" "$STATE_DIR/window-ids" "${_session_args[@]}"
fi
