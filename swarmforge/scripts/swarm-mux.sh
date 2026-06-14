typeset -a MUX_TARGETS=()

mux_is_cmux() {
  if [[ -n "${SWARM_MUX:-}" ]]; then
    [[ "$SWARM_MUX" == "cmux" ]]
    return
  fi

  if [[ -n "${CMUX_SOCKET_PATH:-}" || -n "${CMUX_SOCKET:-}" || -n "${CMUX_WORKSPACE_ID:-}" || -n "${CMUX_SURFACE_ID:-}" ]]; then
    SWARM_MUX="cmux"
    return 0
  fi

  SWARM_MUX="tmux"
  return 1
}

mux_dependency() {
  if mux_is_cmux; then
    echo "cmux"
  else
    echo "tmux"
  fi
}

mux_init_targets() {
  local i
  for (( i = 1; i <= ${#ROLES[@]}; i++ )); do
    MUX_TARGETS[$i]="${SESSIONS[$i]}"
  done
}

mux_kill_existing() {
  local cmux_workspaces_file="$STATE_DIR/cmux-workspaces"
  local cmux_group_file="$STATE_DIR/cmux-group"

  if [[ -s "$cmux_workspaces_file" ]]; then
    local ws
    while IFS= read -r ws; do
      [[ -n "$ws" ]] || continue
      cmux workspace close --workspace "$ws" || true
    done < "$cmux_workspaces_file"
    : > "$cmux_workspaces_file"
  fi

  if [[ -s "$cmux_group_file" ]]; then
    local group
    group="$(< "$cmux_group_file")"
    if [[ -n "$group" ]]; then
      cmux workspace-group delete "$group" || true
    fi
    : > "$cmux_group_file"
  fi
}

mux_create_all() {
  local i ws group
  group=""

  for (( i = 1; i <= ${#ROLES[@]}; i++ )); do
    ws=$(cmux workspace create --name "SwarmForge ${DISPLAY_NAMES[$i]}" --cwd "${WORKTREE_PATHS[$i]}" --focus false | awk '/^OK/{print $2; exit}')
    [[ -n "$ws" ]] || { echo "swarm-mux: cmux workspace create failed for role ${ROLES[$i]}" >&2; return 1; }

    if (( i == 1 )); then
      group=$(cmux workspace-group create --name "SwarmForge · ${WORKING_DIR:t}" --from "$ws" | awk '/^OK/{print $2; exit}')
      [[ -n "$group" ]] || { echo "swarm-mux: cmux workspace-group create failed" >&2; return 1; }
      printf '%s\n' "$group" > "$STATE_DIR/cmux-group"
    else
      cmux workspace-group add --group "$group" --workspace "$ws"
    fi

    MUX_TARGETS[$i]="$ws"
    printf '%s\n' "$ws" >> "$STATE_DIR/cmux-workspaces"
  done

  write_sessions_file
}

mux_deliver() {
  local ws="${MUX_TARGETS[$1]}"
  cmux send --workspace "$ws" -- "$2"
  sleep 0.15
  cmux send-key --workspace "$ws" enter
}

mux_cleanup_args() {
  local cmux_group_file="$STATE_DIR/cmux-group"
  local cmux_workspaces_file="$STATE_DIR/cmux-workspaces"
  local group ws
  local -a ws_refs

  group=""
  if [[ -f "$cmux_group_file" ]]; then
    group="$(< "$cmux_group_file")"
  fi

  ws_refs=()
  if [[ -f "$cmux_workspaces_file" ]]; then
    while IFS= read -r ws; do
      [[ -n "$ws" ]] || continue
      ws_refs+=("$ws")
    done < "$cmux_workspaces_file"
  fi

  echo "--mux cmux --group $group ${ws_refs[*]}"
}

mux_open_views() {
  cmux workspace select --workspace "${MUX_TARGETS[1]}"
}

mux_notify_snippet() {
  printf 'cmux send --workspace "$TARGET_SESSION" -- "$message"\n'
  printf 'sleep 0.15\n'
  printf 'cmux send-key --workspace "$TARGET_SESSION" enter\n'
}
