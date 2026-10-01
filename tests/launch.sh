#!/usr/bin/env bash
set -euo pipefail

LAUNCHER="${LAUNCHER:-$(dirname "$0")/../bnet-launch.sh}"
scratch="$(mktemp -d)"

cleanup() {
  local pid_file
  for pid_file in "$scratch"/*/primary.pid; do
    [[ -f "$pid_file" ]] || continue
    kill "$(cat "$pid_file")" 2>/dev/null || true
  done
  rm -rf "$scratch"
}
trap cleanup EXIT

cat > "$scratch/runner" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail

count_file="$BNET_LOG_DIR/count"
count=0
[[ ! -f "$count_file" ]] || count="$(cat "$count_file")"
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"
log="$BNET_LOG_DIR/battle.net-test.log"

case "$SIM_CASE" in
  client)
    printf '%s\n' 'IPC ShMem mode=client' >> "$log"
    ;;
  rotation)
    printf '%s\n' 'IPC ShMem mode=client' > "$BNET_LOG_DIR/new.log"
    head -c 8192 /dev/zero | tr '\0' X >> "$BNET_LOG_DIR/new.log"
    mv "$BNET_LOG_DIR/new.log" "$log"
    ;;
  server_failure)
    printf '%s\n' 'IPC ShMem mode=server' >> "$log"
    exit 42
    ;;
  server_handoff)
    if ((count == 1)); then
      printf '%s\n' 'IPC ShMem mode=server' >> "$log"
      (sleep 0.2; printf '%s\n' 'Logged into Battle.net successfully.' \
        'GameController initialization complete' >> "$log") &
    fi
    ;;
  server_other | server_target)
    if ((count == 1)); then
      printf '%s\n' 'IPC ShMem mode=server' \
        'Logged into Battle.net successfully.' \
        'GameController initialization complete' >> "$log"
      if [[ "$SIM_CASE" == server_other ]]; then
        printf '%s\n' 'InstallState (other): GameLaunching=1' >> "$log"
      else
        printf '%s\n' 'InstallState (wow): GameLaunching=1' >> "$log"
      fi
      printf '%s\n' "$$" > "$BNET_LOG_DIR/primary.pid"
      while [[ ! -f "$BNET_LOG_DIR/done" ]]; do sleep 0.1; done
    else
      printf '%s\n' 'IPC ShMem mode=client' >> "$log"
    fi
    ;;
esac
RUNNER
chmod +x "$scratch/runner"

run_case() {
  local name="$1" expected_status="$2" expected_calls="$3"
  local case_dir="$scratch/$name"
  local status calls
  mkdir -p "$case_dir"

  if [[ "$name" == rotation ]]; then
    head -c 4096 /dev/zero | tr '\0' O > "$case_dir/battle.net-test.log"
  fi

  if BNET_RUNNER="$scratch/runner" BNET_LOG_DIR="$case_dir" SIM_CASE="$name" \
    BNET_CLASSIFY_TIMEOUT=2 BNET_LAUNCH_TIMEOUT=2 \
    timeout 8 "$LAUNCHER" WoW > "$case_dir/output" 2>&1; then
    status=0
  else
    status=$?
  fi

  touch "$case_dir/done"
  calls="$(cat "$case_dir/count" 2>/dev/null || printf '0')"
  if [[ "$status" != "$expected_status" || "$calls" != "$expected_calls" ]]; then
    printf '%s: expected status %s and %s calls, got status %s and %s calls\n' \
      "$name" "$expected_status" "$expected_calls" "$status" "$calls" >&2
    cat "$case_dir/output" >&2
    exit 1
  fi
  printf '%s: passed\n' "$name"
}

case "${1:-all}" in
  all)
    run_case client 0 1
    run_case rotation 0 1
    run_case server_failure 42 1
    run_case server_handoff 0 2
    run_case server_other 0 2
    run_case server_target 0 1
    ;;
  client | rotation | server_failure | server_handoff | server_other | server_target)
    case "$1" in
      server_failure) run_case "$1" 42 1 ;;
      server_handoff | server_other) run_case "$1" 0 2 ;;
      *) run_case "$1" 0 1 ;;
    esac
    ;;
  *) printf 'Unknown test: %s\n' "$1" >&2; exit 2 ;;
esac
