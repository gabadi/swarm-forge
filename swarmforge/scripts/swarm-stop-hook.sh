#!/usr/bin/env zsh
set -euo pipefail

# Fired by Claude Code's Stop hook when a role agent finishes responding.
# Checks if a pending handoff message was queued (because the agent was busy
# when notify-agent.sh ran) and delivers it: /clear + bundle re-inject + message.
#
# Usage: swarm-stop-hook.sh <role> <working_dir>

ROLE="${1:-}"
WORKING_DIR="${2:-}"

[[ -z "$ROLE" || -z "$WORKING_DIR" ]] && exit 0

STATE_DIR="$WORKING_DIR/.swarmforge"
SESSIONS_FILE="$STATE_DIR/sessions.tsv"
PROMPTS_DIR="$STATE_DIR/prompts"
MUX_BACKEND_FILE="$STATE_DIR/mux-backend"

[[ ! -f "$SESSIONS_FILE" ]] && exit 0

# Resolve own worktree path and mux target from sessions.tsv
OWN_WORKTREE=""
TARGET_SESSION=""
while IFS=$'\t' read -r index role session display agent worktree_path; do
  if [[ "${role:l}" == "${ROLE:l}" ]]; then
    OWN_WORKTREE="${worktree_path:-$WORKING_DIR}"
    TARGET_SESSION="$session"
    break
  fi
done < "$SESSIONS_FILE"

[[ -z "$OWN_WORKTREE" ]] && exit 0

OWN_LOGBOOK="$OWN_WORKTREE/logbook.json"

# Check that the agent just completed a job (last status == "executed")
LAST_OWN_STATUS="$(jq -r '.status // "none"' "$OWN_LOGBOOK" 2>/dev/null | tail -1 || echo "none")"
[[ "$LAST_OWN_STATUS" != "executed" ]] && exit 0

# Count how many jobs this role has started ("executing" entries in own logbook)
EXECUTING_COUNT=0
if [[ -f "$OWN_LOGBOOK" ]]; then
  EXECUTING_COUNT="$(jq -r 'select(.status == "executing") | .status' "$OWN_LOGBOOK" 2>/dev/null | wc -l | tr -d ' ')"
fi

# Search all role logbooks for the most recent undelivered "sent" entry targeting this role.
# "Undelivered" = total sent_count across all senders exceeds own executing_count.
TOTAL_SENT=0
PENDING_MESSAGE=""
PENDING_COMMIT=""

while IFS=$'\t' read -r index role session display agent worktree_path; do
  [[ "${role:l}" == "${ROLE:l}" ]] && continue  # skip own logbook
  local_logbook="${worktree_path:-$WORKING_DIR}/logbook.json"
  [[ ! -f "$local_logbook" ]] && continue

  # Count "sent" entries targeting this role
  sent_here="$(jq -r --arg role "$ROLE" 'select(.status == "sent" and .target == $role) | .status' \
    "$local_logbook" 2>/dev/null | wc -l | tr -d ' ')"
  TOTAL_SENT=$((TOTAL_SENT + sent_here))

  # Extract message from most recent "sent" entry targeting this role
  if [[ $sent_here -gt 0 ]]; then
    msg="$(jq -r --arg role "$ROLE" 'select(.status == "sent" and .target == $role) | .message' \
      "$local_logbook" 2>/dev/null | tail -1)"
    commit="$(jq -r --arg role "$ROLE" 'select(.status == "sent" and .target == $role) | .commit // ""' \
      "$local_logbook" 2>/dev/null | tail -1)"
    [[ -n "$msg" ]] && PENDING_MESSAGE="$msg" PENDING_COMMIT="$commit"
  fi
done < "$SESSIONS_FILE"

# No pending messages if sent count doesn't exceed job count
[[ $TOTAL_SENT -le $EXECUTING_COUNT ]] && exit 0
[[ -z "$PENDING_MESSAGE" ]] && exit 0

MUX_BACKEND="$(< "$MUX_BACKEND_FILE" 2>/dev/null || echo tmux)"
BUNDLE_FILE="$PROMPTS_DIR/${ROLE}.md"

deliver_cmux() {
  cmux send --workspace "$TARGET_SESSION" -- "/clear"
  sleep 0.15
  cmux send-key --workspace "$TARGET_SESSION" enter
  sleep 1
  if [[ -f "$BUNDLE_FILE" ]]; then
    cmux send --workspace "$TARGET_SESSION" -- "$(< "$BUNDLE_FILE")"
    sleep 0.15
    cmux send-key --workspace "$TARGET_SESSION" enter
    sleep 0.5
  fi
  cmux send --workspace "$TARGET_SESSION" -- "$PENDING_MESSAGE"
  sleep 0.15
  cmux send-key --workspace "$TARGET_SESSION" enter
}

deliver_tmux() {
  local socket_file="$STATE_DIR/tmux-socket"
  [[ ! -f "$socket_file" ]] && return 1
  local socket
  socket="$(< "$socket_file")"
  local tw tp
  tw="$(tmux -S "$socket" show-options -gqv base-index 2>/dev/null || echo 0)"
  tp="$(tmux -S "$socket" show-window-options -gqv pane-base-index 2>/dev/null || echo 0)"
  [[ ! "$tw" =~ ^[0-9]+$ ]] && tw=0
  [[ ! "$tp" =~ ^[0-9]+$ ]] && tp=0
  local pane="${TARGET_SESSION}:${tw}.${tp}"
  tmux -S "$socket" send-keys -t "$pane" -l -- "/clear"
  tmux -S "$socket" send-keys -t "$pane" C-m
  sleep 1
  if [[ -f "$BUNDLE_FILE" ]]; then
    tmux -S "$socket" send-keys -t "$pane" -l -- "$(< "$BUNDLE_FILE")"
    tmux -S "$socket" send-keys -t "$pane" C-m
    sleep 0.5
  fi
  tmux -S "$socket" send-keys -t "$pane" -l -- "$PENDING_MESSAGE"
  tmux -S "$socket" send-keys -t "$pane" C-m
}

if [[ "$MUX_BACKEND" == "cmux" ]]; then
  deliver_cmux
else
  deliver_tmux
fi
