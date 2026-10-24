#!/bin/bash
# Removes the apps a CI job built from LaunchServices, which Xcode registers
# as it builds them, so the Mac mini running CI keeps knowing only Max's
# installed Scribe. Touches nothing outside the job's workspace otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[[ -d "${ROOT}/build" ]] || exit 0
find "${ROOT}/build" -type d -name '*.app' -prune -print | while IFS= read -r app; do
  "${LSREGISTER}" -u "${app}" 2>/dev/null || true
  echo "forgot ${app#"${ROOT}/"}"
done
