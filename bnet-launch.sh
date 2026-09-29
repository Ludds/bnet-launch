#!/usr/bin/env bash
set -euo pipefail

# Launch a Battle.net product while keeping Battle.net's normal SSO flow.
# Usage: WINEPREFIX=/path/to/prefix ./bnet-launch.sh [PRODUCT]

usage() {
  cat <<'USAGE'
Usage:
  WINEPREFIX=/path/to/prefix bnet-launch.sh [PRODUCT]

PRODUCT defaults to WoW.

Environment:
  WINEPREFIX              Wine prefix. Defaults to ~/.wine.
  WINE_BIN                Wine executable. Defaults to wine.
  BNET_EXE                Windows path to Battle.net.exe.
  BNET_EXE_UNIX           Host path used to verify Battle.net is installed.
  BNET_RUNNER             Optional runner command or executable path. Receives
                          BNET_EXE followed by args.
  BNET_LOG_DIR            Optional explicit Battle.net log directory.
  BNET_LAUNCH_TIMEOUT     Readiness timeout in seconds. Defaults to 120.
  BNET_CLASSIFY_TIMEOUT   IPC client/server detection timeout. Defaults to 15.

If BNET_RUNNER uses a different prefix than WINEPREFIX, set BNET_LOG_DIR to
that prefix's Battle.net Logs directory so readiness detection can find it.
USAGE
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
esac

if (($# > 1)); then
  echo "Too many arguments." >&2
  usage >&2
  exit 2
fi

if [[ "${1:-}" == -* ]]; then
  echo "Unknown option: $1" >&2
  usage >&2
  exit 2
fi

PRODUCT="${1:-WoW}"
PREFIX="${WINEPREFIX:-$HOME/.wine}"
WINE_BIN="${WINE_BIN:-wine}"
TIMEOUT="${BNET_LAUNCH_TIMEOUT:-120}"
CLASSIFY_TIMEOUT="${BNET_CLASSIFY_TIMEOUT:-15}"

BNET_EXE="${BNET_EXE:-C:\\Program Files (x86)\\Battle.net\\Battle.net.exe}"
BNET_EXE_UNIX="${BNET_EXE_UNIX:-$PREFIX/drive_c/Program Files (x86)/Battle.net/Battle.net.exe}"
LOG_DIR_OVERRIDE="${BNET_LOG_DIR:-}"
RUNNER="${BNET_RUNNER:-}"

require_positive_integer() {
  local name="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s must be a positive integer, got: %q\n' "$name" "$value" >&2
    exit 2
  fi
}

require_positive_integer BNET_LAUNCH_TIMEOUT "$TIMEOUT"
require_positive_integer BNET_CLASSIFY_TIMEOUT "$CLASSIFY_TIMEOUT"

if [[ -z "$RUNNER" ]]; then
  if ! command -v "$WINE_BIN" >/dev/null 2>&1; then
    echo "Wine executable not found: $WINE_BIN" >&2
    exit 1
  fi

  if [[ ! -f "$BNET_EXE_UNIX" ]]; then
    echo "Battle.net.exe not found in prefix: $PREFIX" >&2
    echo "Expected: $BNET_EXE_UNIX" >&2
    exit 1
  fi
elif [[ "$RUNNER" == */* ]]; then
  if [[ ! -x "$RUNNER" ]]; then
    echo "BNET_RUNNER is not executable: $RUNNER" >&2
    exit 1
  fi
elif ! command -v "$RUNNER" >/dev/null 2>&1; then
  echo "BNET_RUNNER command not found: $RUNNER" >&2
  exit 1
fi

run_bnet() {
  if [[ -n "$RUNNER" ]]; then
    "$RUNNER" "$BNET_EXE" "$@"
  else
    WINEPREFIX="$PREFIX" "$WINE_BIN" "$BNET_EXE" "$@"
  fi
}

find_bnet_logs() {
  if [[ -n "$LOG_DIR_OVERRIDE" ]]; then
    find "$LOG_DIR_OVERRIDE" \
      -maxdepth 1 \
      -type f \
      -name 'battle.net-*.log' \
      -print0 \
      2>/dev/null
  else
    find "$PREFIX/drive_c/users" \
      -type f \
      -path '*/AppData/Local/Battle.net/Logs/battle.net-*.log' \
      -print0 \
      2>/dev/null
  fi
}

# Ignore log content written before this launch attempt.
declare -A LOG_OFFSETS=()
while IFS= read -r -d '' log; do
  LOG_OFFSETS["$log"]="$(stat -c '%s' -- "$log" 2>/dev/null || printf '0')"
done < <(find_bnet_logs)

fresh_log_contains() {
  local log="$1"
  local pattern="$2"
  local offset="${LOG_OFFSETS[$log]:-0}"
  local size

  [[ -f "$log" ]] || return 1
  size="$(stat -c '%s' -- "$log" 2>/dev/null)" || return 1

  if ((size < offset)); then
    offset=0
  fi

  ((size > offset)) || return 1
  grep -Fq -- "$pattern" < <(tail -c "+$((offset + 1))" -- "$log")
}

find_fresh_mode_log() {
  local mode="$1"
  local log

  while IFS= read -r -d '' log; do
    if fresh_log_contains "$log" "IPC ShMem mode=$mode"; then
      printf '%s\n' "$log"
      return 0
    fi
  done < <(find_bnet_logs)

  return 1
}

echo "Requesting Battle.net launch for $PRODUCT..."

run_bnet "--exec=launch $PRODUCT" </dev/null >/dev/null 2>&1 &
request_pid=$!

mode=""
mode_log=""
deadline=$((SECONDS + CLASSIFY_TIMEOUT))

while ((SECONDS < deadline)); do
  if mode_log="$(find_fresh_mode_log server)"; then
    mode="server"
    break
  fi

  if mode_log="$(find_fresh_mode_log client)"; then
    mode="client"
    break
  fi

  sleep 0.25
done

if [[ "$mode" == "client" ]]; then
  if wait "$request_pid"; then
    status=0
  else
    status=$?
  fi

  if ((status != 0)); then
    echo "Battle.net IPC client exited with status $status." >&2
    exit "$status"
  fi

  echo "Launch request forwarded to the existing Battle.net instance."
  exit 0
fi

if [[ "$mode" != "server" ]]; then
  if ! kill -0 "$request_pid" 2>/dev/null; then
    if wait "$request_pid"; then
      status=0
    else
      status=$?
    fi

    if ((status != 0)); then
      echo "Battle.net launch request exited with status $status." >&2
      exit "$status"
    fi
  fi

  echo "Could not determine whether Battle.net became an IPC client or server within ${CLASSIFY_TIMEOUT}s." >&2
  echo "Check the prefix/log path, or set BNET_LOG_DIR explicitly." >&2
  exit 1
fi

# The primary Battle.net process should outlive this launcher script.
disown "$request_pid" 2>/dev/null || true

echo "Battle.net became the primary instance; waiting for login and GameController..."

ready=0
deadline=$((SECONDS + TIMEOUT))

while ((SECONDS < deadline)); do
  if fresh_log_contains "$mode_log" 'Logged into Battle.net successfully.' &&
    fresh_log_contains "$mode_log" 'GameController initialization complete'; then
    ready=1
    break
  fi

  sleep 0.25
done

if ((ready == 0)); then
  echo "Battle.net did not become ready within ${TIMEOUT}s." >&2
  exit 1
fi

if fresh_log_contains "$mode_log" 'GameLaunching=1'; then
  echo "Battle.net already started the game."
  exit 0
fi

echo "Battle.net is ready; sending the launch command again through IPC..."
run_bnet "--exec=launch $PRODUCT" </dev/null >/dev/null 2>&1
