#!/bin/bash
# Renders the candidate window snapshot cases with Squirrel's own code, as
# reference images for ScribeUI's tests:
#
#   Tools/squirrel-oracle/render.sh [case-name ...]
#
# Downloads SquirrelTheme, SquirrelView, SquirrelPanel and ReservedProperty
# from a pinned commit of rime/squirrel into build/squirrel-oracle (they are
# not committed), compiles them with the shims and driver next to this
# script, and renders every case in Tests/Fixtures/snapshots/cases.json, or
# only the named ones, into Tests/Fixtures/snapshots/squirrel/<suite>/.
#
# Needs a Metal device. Each case shows Squirrel's panel in an invisible
# window that lays out as on a Retina screen, whatever the display, then
# composites the window's layers with CARenderer, masks and shadows included.
# Also writes screen.json, the screen size Squirrel wrapped lines for, which
# ScribeUI's comparison uses too. Run it after changing cases.json or the
# configs, and commit the images.

set -euo pipefail

SQUIRREL_COMMIT=46962d2efae5be70389c778d0a6c52f669072827
SOURCES=(
  "SquirrelTheme.swift ab55a0e2462382f79fc47d9e56b7375bc3c8a6232858008ec7fb2c581855e4cd"
  "SquirrelView.swift 0fdbe5ae064342c41bb1261a5c7afd98cb3b7ec649022441a65a175b6a9ced5f"
  "SquirrelPanel.swift 7be555b3a590c93ae39a5a0b27b75c4258b7c3753b5336b73e181f4614525146"
  "ReservedProperty.swift b5fb045723a9f7cb57f31d2fa34e21babc2005853a2bf04d4d89f61a1ece6d67"
)

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="${ROOT}/Tools/squirrel-oracle"
BUILD="${ROOT}/build/squirrel-oracle"
mkdir -p "${BUILD}/squirrel"

for entry in "${SOURCES[@]}"; do
  read -r name sha256 <<< "${entry}"
  file="${BUILD}/squirrel/${name}"
  if [[ -f "${file}" ]] && echo "${sha256}  ${file}" | shasum -a 256 -c --status; then
    continue
  fi
  echo "Downloading ${name}"
  curl --fail --location --silent --show-error --retry 3 --output "${file}.part" \
    "https://raw.githubusercontent.com/rime/squirrel/${SQUIRREL_COMMIT}/sources/${name}"
  if ! echo "${sha256}  ${file}.part" | shasum -a 256 -c --status; then
    rm -f "${file}.part"
    echo "error: checksum mismatch for ${name}" >&2
    exit 1
  fi
  mv "${file}.part" "${file}"
done

# Squirrel builds in the Swift 5 language mode.
xcrun swiftc -swift-version 5 -enable-bare-slash-regex -O \
  -o "${BUILD}/squirrel-oracle" \
  "${HERE}"/Sources/*.swift "${BUILD}"/squirrel/*.swift

"${BUILD}/squirrel-oracle" \
  "${ROOT}/Tests/Fixtures/snapshots/cases.json" \
  "${ROOT}/Tests/Fixtures/snapshots/squirrel" \
  "$@"
