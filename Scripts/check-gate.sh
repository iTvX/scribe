#!/bin/bash
# Plays the gate replays in Tests/Fixtures/gate with a Scribe build's
# librime, plugins and shared data, against 雾凇拼音 (rime-ice) at the release
# Scripts/install-rime-ice.sh pins, installed in a temporary directory. Never
# reads ~/Library/Scribe, so it runs the same in CI and on any Mac.
#
#   Scripts/check-gate.sh [path/to/Scribe.app]
#
# Without an argument it uses the Release build in build/DerivedData.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-${ROOT}/build/DerivedData.noindex/Build/Products/Release/Scribe.app}"
EXECUTABLE="${APP}/Contents/MacOS/Scribe"
[[ -x "${EXECUTABLE}" ]] || { echo "error: no Scribe at ${APP}; build it first" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
USER_DIR="${WORK}/rime-ice"
SCRIBE_USER_DIR="${USER_DIR}" "${ROOT}/Scripts/install-rime-ice.sh"

# Deploy only the schemas the replays use, with what they depend on.
cat > "${USER_DIR}/default.custom.yaml" <<'YAML'
patch:
  schema_list:
    - schema: rime_ice
    - schema: double_pinyin_flypy
YAML

status=0
for replay in "${ROOT}"/Tests/Fixtures/gate/*.replay; do
  echo "== ${replay##*/}"
  # librime's info log goes to stderr; the replay reports on stdout.
  "${EXECUTABLE}" --replay "${replay}" "${USER_DIR}" 2>/dev/null || status=1
done
exit "${status}"
