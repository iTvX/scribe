#!/bin/bash
# Runs Tools/scribe-release, the release tooling for tags, release notes and
# the Sparkle appcast, building it first. Build output goes to standard error
# and the build never reads standard input, so the tool's input and output
# pass through untouched.
#
#   Scripts/release-tool.sh tag v1.2.3
#   Scripts/release-tool.sh notes 1.2.3 CHANGELOG.md
#   Scripts/release-tool.sh key new | key public | appcast … | verify …

set -euo pipefail

PACKAGE="$(cd "$(dirname "$0")/.." && pwd)/Tools/scribe-release"
swift build --quiet -c release --package-path "${PACKAGE}" </dev/null >&2
exec "${PACKAGE}/.build/release/scribe-release" "$@"
