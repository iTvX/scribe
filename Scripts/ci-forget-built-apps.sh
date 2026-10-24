#!/bin/bash
# Removes the apps a CI job built from LaunchServices, which registers them as
# Xcode and the packaging scripts make them, so the Mac mini running CI keeps
# knowing only Max's installed Scribe. Every registered path under the job's
# workspace goes, nested bundles such as ScribeSettings.app and Sparkle's
# Updater.app included, and paths already deleted, such as build/release/root.
# Touches nothing outside the job's workspace otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Deepest first, so a bundle goes before the one that contains it.
"${LSREGISTER}" -dump 2>/dev/null |
  sed -n -E 's/^path: +(.*) \(0x[0-9a-f]+\)$/\1/p' |
  grep -F "${ROOT}/" |
  sort -u |
  awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2- |
  while IFS= read -r app; do
    "${LSREGISTER}" -u "${app}" 2>/dev/null || true
    echo "forgot ${app#"${ROOT}/"}"
  done
