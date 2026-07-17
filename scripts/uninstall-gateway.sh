#!/usr/bin/env bash
# uninstall-gateway.sh — best-effort teardown of the Mac local OpenClaw/TClaw gateway.
#
# Product behavior aligned with Windows NativeGatewayCleanup + docs/MAC_PORT_HANDOFF.md §2:
#   1. openclaw gateway stop / uninstall (if CLI still on PATH)
#   2. launchctl bootout + delete LaunchAgent plists (gateway + app)
#   3. kill leftover gateway / node listeners on port 18789
#   4. optional: wipe App Support / ~/.openclaw (opt-in flags only)
#
# Default does NOT delete ~/.openclaw (workspace/skills may still be needed) or
# external/remote gateway records. Safe to re-run (idempotent).
#
# Usage:
#   ./scripts/uninstall-gateway.sh
#   ./scripts/uninstall-gateway.sh --wipe-app-data
#   ./scripts/uninstall-gateway.sh --wipe-state          # deletes ~/.openclaw
#   ./scripts/uninstall-gateway.sh --wipe-all            # app data + state
#   ./scripts/uninstall-gateway.sh --port 18789
#
set -u

PORT=18789
WIPE_APP_DATA=0
WIPE_STATE=0
GATEWAY_LABEL="ai.openclaw.gateway"
APP_LABEL="ai.openclaw.mac"
UID_NUM="$(id -u)"
LAUNCH_AGENTS="${HOME}/Library/LaunchAgents"
APP_SUPPORT="${HOME}/Library/Application Support/OpenClaw"
APP_SUPPORT_TRAY="${HOME}/Library/Application Support/OpenClawTray"
STATE_DIR="${HOME}/.openclaw"
LOG_PREFIX="[uninstall]"

log()  { printf '%s %s\n' "$LOG_PREFIX" "$*"; }
warn() { printf '%s WARN: %s\n' "$LOG_PREFIX" "$*" >&2; }

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="${2:-}"; shift 2 ;;
    --wipe-app-data) WIPE_APP_DATA=1; shift ;;
    --wipe-state) WIPE_STATE=1; shift ;;
    --wipe-all) WIPE_APP_DATA=1; WIPE_STATE=1; shift ;;
    -h|--help) usage ;;
    *) warn "unknown arg: $1"; usage ;;
  esac
done

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 || "$PORT" -gt 65535 ]]; then
  warn "invalid port: $PORT"
  exit 2
fi

log "Native gateway cleanup starting (port=$PORT)"

# ── 1) Prefer official CLI path while openclaw is still resolvable ──────────
resolve_openclaw() {
  if command -v openclaw >/dev/null 2>&1; then
    command -v openclaw
    return 0
  fi
  local candidates=(
    "${HOME}/.openclaw/bin/openclaw"
    "/usr/local/bin/openclaw"
    "/opt/homebrew/bin/openclaw"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -x "$c" ]]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

if OC="$(resolve_openclaw)"; then
  log "using openclaw at $OC"
  if "$OC" gateway stop >/dev/null 2>&1; then
    log "openclaw gateway stop succeeded"
  else
    warn "openclaw gateway stop failed (continuing)"
  fi
  if "$OC" gateway uninstall >/dev/null 2>&1; then
    log "openclaw gateway uninstall succeeded"
  else
    warn "openclaw gateway uninstall failed (continuing)"
  fi
else
  warn "openclaw CLI not found; skipping CLI stop/uninstall"
fi

# ── 2) launchctl bootout + delete plists ────────────────────────────────────
bootout_label() {
  local label="$1"
  local domain="gui/${UID_NUM}/${label}"
  if launchctl print "$domain" >/dev/null 2>&1; then
    if launchctl bootout "gui/${UID_NUM}" "$domain" >/dev/null 2>&1 \
      || launchctl bootout "$domain" >/dev/null 2>&1; then
      log "bootout $domain"
    else
      # Older systems: unload by plist path if present
      local plist="${LAUNCH_AGENTS}/${label}.plist"
      if [[ -f "$plist" ]]; then
        launchctl unload "$plist" >/dev/null 2>&1 || true
        log "unload $plist"
      else
        warn "bootout failed for $domain"
      fi
    fi
  else
    log "launchd job not loaded: $label"
  fi
}

bootout_label "$GATEWAY_LABEL"
bootout_label "$APP_LABEL"

for label in "$GATEWAY_LABEL" "$APP_LABEL"; do
  plist="${LAUNCH_AGENTS}/${label}.plist"
  if [[ -f "$plist" ]]; then
    rm -f "$plist" && log "removed $plist" || warn "could not remove $plist"
  fi
done

# Also catch any residual openclaw/tclaw plists
if [[ -d "$LAUNCH_AGENTS" ]]; then
  shopt -s nullglob
  for plist in "$LAUNCH_AGENTS"/*openclaw*.plist "$LAUNCH_AGENTS"/*tclaw*.plist; do
    base="$(basename "$plist" .plist)"
    bootout_label "$base"
    rm -f "$plist" && log "removed residual $plist" || true
  done
  shopt -u nullglob
fi

# ── 3) Kill leftover listeners on gateway port ──────────────────────────────
kill_port_listeners() {
  local port="$1"
  local pids
  pids="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)"
  if [[ -z "$pids" ]]; then
    log "no listeners on :$port"
    return 0
  fi
  local pid cmd
  for pid in $pids; do
    cmd="$(ps -p "$pid" -o comm= 2>/dev/null || echo '?')"
    log "killing pid $pid ($cmd) listening on :$port"
    kill "$pid" 2>/dev/null || true
  done
  sleep 0.5
  pids="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    for pid in $pids; do
      warn "force-killing pid $pid on :$port"
      kill -9 "$pid" 2>/dev/null || true
    done
  fi
}

kill_port_listeners "$PORT"

# Best-effort: gateway node host processes that may not hold the port momentarily
pkill -f "openclaw.*gateway" 2>/dev/null || true
pkill -f "ai.openclaw.gateway" 2>/dev/null || true

# ── 4) Optional data wipes ──────────────────────────────────────────────────
if [[ "$WIPE_APP_DATA" -eq 1 ]]; then
  for dir in "$APP_SUPPORT" "$APP_SUPPORT_TRAY" \
    "${HOME}/Library/Caches/ai.openclaw.mac" \
    "${HOME}/Library/Logs/OpenClaw" \
    "${HOME}/Library/Logs/ai.openclaw"; do
    if [[ -e "$dir" ]]; then
      rm -rf "$dir" && log "removed $dir" || warn "could not remove $dir"
    fi
  done
  # Login item / user defaults suite (best-effort)
  defaults delete ai.openclaw.mac >/dev/null 2>&1 && log "cleared defaults ai.openclaw.mac" || true
else
  log "kept app data (pass --wipe-app-data to remove Application Support / caches)"
fi

if [[ "$WIPE_STATE" -eq 1 ]]; then
  if [[ -e "$STATE_DIR" ]]; then
    rm -rf "$STATE_DIR" && log "removed $STATE_DIR" || warn "could not remove $STATE_DIR"
  fi
else
  log "kept $STATE_DIR (pass --wipe-state to remove config/workspace/skills)"
fi

# ── 5) Verification hints ───────────────────────────────────────────────────
log "cleanup finished. Quick checks:"
log "  launchctl list | grep -i openclaw   # expect empty"
log "  lsof -i :${PORT}                   # expect empty"
log "  ls ~/Library/LaunchAgents | grep -i openclaw"
if [[ "$WIPE_STATE" -eq 0 ]]; then
  log "  ~/.openclaw retained — reinstall can reuse workspace/skills"
fi

exit 0
