#!/usr/bin/env zsh

terminal_backend_label() {
  echo "cmux"
}

terminal_backend_can_open_sessions() {
  return 0
}

terminal_backend_tracks_windows() {
  return 0
}

terminal_window_exists() {
  local ws_ref="$1"
  [[ -n "$ws_ref" ]] || return 1

  # Retry when the cmux query itself fails or returns nothing usable. While cmux
  # is busy creating/attaching several workspaces at startup, list-windows can
  # transiently fail; a bare failure here would make the watchdog count a
  # healthy workspace as "missing" and tear the whole swarm down. Only conclude
  # the workspace is gone after cmux returns a valid window list that lacks it.
  local attempt window_count window_index
  for attempt in 1 2 3; do
    window_count="$(cmux list-windows --json 2>/dev/null | jq 'length' 2>/dev/null)"
    if [[ -z "$window_count" || "$window_count" -lt 1 ]]; then
      sleep 0.3
      continue
    fi
    for (( window_index = 0; window_index < window_count; window_index++ )); do
      if cmux workspace list --json --window "$window_index" 2>/dev/null \
        | jq -e ".workspaces[] | select(.ref == \"$ws_ref\")" >/dev/null 2>&1; then
        return 0
      fi
    done
    return 1
  done
  return 1
}

_cmux_group_from_workspace() {
  local ws_ref="$1"
  cmux workspace-group list --json 2>/dev/null \
    | jq -r ".groups[] | select(.member_workspace_refs[] == \"$ws_ref\") | .ref" 2>/dev/null \
    | head -1
}

terminal_open_session() {
  local session="$1"
  local title="$2"
  local sibling_ref="${3:-}"

  # Attach with the ABSOLUTE path of the real tmux binary, never bare `tmux`.
  # Inside a cmux workspace CMUX_SOCKET_PATH is set, and the user's shell rc
  # defines a tmux() function that routes every `tmux` call to `cmux
  # __tmux-compat` (cmux ships no tmux; it is a tmux replacement). That compat
  # shim reports a fake "tmux 3.4" and treats `attach-session` as a no-op, so a
  # bare `exec tmux attach` silently exec's into nothing and the workspace
  # closes. command -v resolves in the launcher (a non-interactive shell with no
  # such function), giving the real binary that created the server; the absolute
  # path bypasses the shell function so the workspace runs a real tmux client.
  local tmux_bin tmux_cmd
  tmux_bin="$(command -v tmux)"
  tmux_cmd="exec ${(q)tmux_bin} -S ${(q)TMUX_SOCKET} attach-session -t ${(q)session}"

  local ws_ref group_ref

  ws_ref="$(cmux workspace create --name "$title" --cwd "$WORKING_DIR" --command "$tmux_cmd" --focus false | awk '{print $2}')"

  if [[ -z "$sibling_ref" ]]; then
    # Name the group after the project directory so concurrent swarms in
    # different projects are distinguishable in the sidebar. Sibling agents
    # join via _cmux_group_from_workspace (membership, not name), so each run
    # always anchors its own fresh group even if the name repeats.
    local group_name="SwarmForge · ${WORKING_DIR:t}"
    cmux workspace-group create --name "$group_name" --from "$ws_ref" >/dev/null
  else
    group_ref="$(_cmux_group_from_workspace "$sibling_ref")"
    cmux workspace-group add --group "$group_ref" --workspace "$ws_ref" >/dev/null
  fi

  echo "$ws_ref"
}

terminal_close_window() {
  local ws_ref="$1"
  [[ -n "$ws_ref" ]] || return 0
  cmux workspace close --workspace "$ws_ref" 2>/dev/null || true
}
