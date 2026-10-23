#!/bin/bash
# Builds and installs Scribe on this Mac, then checks it end to end without
# switching the current input source:
#
#   1. both input modes are registered, and Scribe is enabled
#   2. the input method process starts
#   3. it logs the librime version and listens for clients
#   4. a full redeploy succeeds, and librime logs no errors while doing it
#
# Set DEPLOY_TIMEOUT (seconds, default 600) for large configurations.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${HOME}/Library/Input Methods/Scribe.app"
EXECUTABLE="${APP}/Contents/MacOS/Scribe"
LOG_DIR="${HOME}/Library/Logs/Scribe"
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-600}"
SUBSYSTEM="io.github.itvx.inputmethod.Scribe"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() {
  echo "ok: $*"
}
indent() {
  while IFS= read -r line; do
    echo "   ${line}"
  done
}

START="$(date '+%Y-%m-%d %H:%M:%S')"
"${ROOT}/Scripts/install-local.sh"

# 1. Registration.
status="$(xcrun swift "${ROOT}/Scripts/tis-status.swift")" || fail "input sources are not registered: ${status}"
indent <<< "${status}"
grep -q "^${SUBSYSTEM} .*enabled" <<< "${status}" ||
  fail "Scribe is registered but not enabled; add it in System Settings > Keyboard > Input Sources"
pass "both input modes are registered and Scribe is enabled"

# 2. The process, started the way LaunchServices starts it for the system.
open -g "${APP}"
for _ in {1..50}; do
  pid="$(pgrep -f "^${EXECUTABLE}$" | head -1 || true)"
  [[ -n "${pid}" ]] && break
  sleep 0.2
done
[[ -n "${pid:-}" ]] || fail "Scribe did not start"
pass "Scribe is running (pid ${pid})"

# Messages from the running process since the install started.
app_log() {
  /usr/bin/log show --start "${START}" --style compact \
    --predicate "subsystem == \"${SUBSYSTEM}\" AND category == \"app\" AND processID == ${pid}" 2>/dev/null
}

# 3. librime is linked and the server is up.
for _ in {1..50}; do
  app_log | grep -q "Input method server listening" && break
  sleep 0.2
done
version_line="$(app_log | grep -o 'with librime [0-9.]*' | head -1)"
[[ -n "${version_line}" ]] || fail "no librime version in the log"
app_log | grep -q "Input method server listening" || fail "the input method server did not start listening"
pass "Scribe started ${version_line} and is listening"

# 4. A full redeploy, waiting for the deploy that follows the request.
"${EXECUTABLE}" --reload
deadline=$((SECONDS + DEPLOY_TIMEOUT))
result=""
while (( SECONDS < deadline )); do
  result="$(app_log | awk '/Redeploying/ { seen = 1; next } seen && /Deploy (succeeded|failed)/ { print; exit }')"
  [[ -n "${result}" ]] && break
  sleep 2
done
[[ -n "${result}" ]] || fail "no deploy result within ${DEPLOY_TIMEOUT} seconds"
grep -q "Deploy succeeded" <<< "${result}" || fail "deploy failed; see ${LOG_DIR}"

errors="$(find "${LOG_DIR}" -name "rime.scribe.*.log.ERROR.*.${pid}.log" -exec cat {} + 2>/dev/null | grep -E '^E' || true)"
warnings="$(find "${LOG_DIR}" -name "rime.scribe.*.log.WARNING.*.${pid}.log" -exec cat {} + 2>/dev/null | grep -cE '^W' || true)"
if [[ -n "${errors}" ]]; then
  indent <<< "${errors}" >&2
  fail "librime logged errors while deploying"
fi
pass "full redeploy succeeded with no librime errors (${warnings:-0} warnings in ${LOG_DIR})"

echo "Scribe is installed and working; switch to it in any app to type."
