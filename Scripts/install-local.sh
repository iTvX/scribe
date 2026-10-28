#!/bin/bash
# Builds Scribe and installs it into ~/Library/Input Methods for local testing,
# then registers its input sources. Registering does not enable or select
# them: add Scribe in System Settings > Keyboard > Input Sources.
#
# Set CONFIGURATION=Debug to install a debug build (default: Release).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${ROOT}/build/DerivedData.noindex"
BUILT_APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/Scribe.app"
INSTALL_DIR="${HOME}/Library/Input Methods"
INSTALLED_APP="${INSTALL_DIR}/Scribe.app"
EXECUTABLE="Contents/MacOS/Scribe"

if ! command -v xcodegen >/dev/null; then
  echo "error: xcodegen not found; install it with: brew install xcodegen" >&2
  exit 1
fi

"${ROOT}/Scripts/fetch-librime.sh"
"${ROOT}/Scripts/fetch-sparkle.sh"
xcodegen generate --quiet --spec "${ROOT}/project.yml"
xcodebuild -quiet \
  -project "${ROOT}/Scribe.xcodeproj" \
  -scheme Scribe \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -destination "generic/platform=macOS" \
  build

# Stop the installed copy before replacing it.
if [[ -x "${INSTALLED_APP}/${EXECUTABLE}" ]]; then
  "${INSTALLED_APP}/${EXECUTABLE}" --quit || true
fi
for _ in {1..50}; do
  pgrep -f "^${INSTALLED_APP}/${EXECUTABLE}" >/dev/null || break
  sleep 0.1
done
pkill -f "^${INSTALLED_APP}/${EXECUTABLE}" || true

mkdir -p "${INSTALL_DIR}"
rm -rf "${INSTALLED_APP}"
ditto "${BUILT_APP}" "${INSTALLED_APP}"
"${INSTALLED_APP}/${EXECUTABLE}" --install

echo "Installed ${INSTALLED_APP}"
