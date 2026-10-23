#!/bin/bash
# Verifies a package built by build-release.sh without installing it.
#
#   Scripts/check-release.sh path/to/Scribe.pkg              signed and notarized
#   Scripts/check-release.sh --unsigned path/to/Scribe.pkg   from build-release.sh --unsigned

set -euo pipefail

TEAM_ID="AW54C93V4H"
BUNDLE_ID="io.github.itvx.inputmethod.Scribe"

SIGNED=1
if [[ "${1:-}" == "--unsigned" ]]; then
  SIGNED=0
  shift
fi
if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: $0 [--unsigned] path/to/Scribe.pkg" >&2
  exit 2
fi
PACKAGE="$1"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() {
  echo "ok: $*"
}

if [[ "${SIGNED}" == 1 ]]; then
  signature="$(pkgutil --check-signature "${PACKAGE}")" || fail "package is not signed"
  grep -q "signed by a developer certificate issued by Apple for distribution" <<< "${signature}" ||
    fail "package is not signed for distribution"
  if ! grep -qF "Developer ID Installer:" <<< "${signature}" || ! grep -qF "(${TEAM_ID})" <<< "${signature}"; then
    fail "package is not signed with Developer ID Installer (${TEAM_ID})"
  fi
  pass "package signed with Developer ID Installer (${TEAM_ID})"

  xcrun stapler validate "${PACKAGE}" >/dev/null || fail "no notarization ticket stapled"
  pass "notarization ticket stapled"

  assessment="$(spctl --assess -vv --type install "${PACKAGE}" 2>&1)" ||
    fail "Gatekeeper rejects the package: ${assessment}"
  grep -q "source=Notarized Developer ID" <<< "${assessment}" ||
    fail "Gatekeeper does not see a notarized Developer ID package: ${assessment}"
  pass "Gatekeeper accepts the package (Notarized Developer ID)"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
pkgutil --expand-full "${PACKAGE}" "${WORK}/expanded"

component="${WORK}/expanded/Scribe-component.pkg"
grep -qF "install-location=\"/Library/Input Methods\"" "${component}/PackageInfo" ||
  fail "package does not install into /Library/Input Methods"
for script in preinstall postinstall; do
  [[ -x "${component}/Scripts/${script}" ]] || fail "package has no ${script} script"
done
pass "installs into /Library/Input Methods with preinstall and postinstall"

APP="${component}/Payload/Scribe.app"
[[ -d "${APP}" ]] || fail "package has no Scribe.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Contents/Info.plist")" == "${BUNDLE_ID}" ]] ||
  fail "unexpected bundle identifier"
for arch in arm64 x86_64; do
  lipo "${APP}/Contents/MacOS/Scribe" -verify_arch "${arch}" || fail "executable lacks ${arch}"
done
[[ -f "${APP}/Contents/Frameworks/librime.1.dylib" ]] || fail "librime.1.dylib is not embedded"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Contents/Info.plist")"
pass "Scribe.app ${version} (${build}) is universal and embeds librime.1.dylib"

codesign --verify --strict --deep "${APP}" || fail "Scribe.app signature does not verify"
for code in "${APP}" "${APP}/Contents/Frameworks/librime.1.dylib"; do
  details="$(codesign --display --verbose=2 "${code}" 2>&1)"
  grep -q "flags=.*runtime" <<< "${details}" || fail "${code##*/} lacks the hardened runtime"
  if [[ "${SIGNED}" == 1 ]]; then
    grep -qF "TeamIdentifier=${TEAM_ID}" <<< "${details}" || fail "${code##*/} is not signed by team ${TEAM_ID}"
    grep -qF "Authority=Developer ID Application:" <<< "${details}" || fail "${code##*/} is not signed with Developer ID Application"
    grep -q "Timestamp=" <<< "${details}" || fail "${code##*/} has no secure timestamp"
  fi
done
entitlements="$(codesign --display --entitlements - --xml "${APP}" 2>/dev/null)"
grep -q "com.apple.security.cs.disable-library-validation" <<< "${entitlements}" ||
  fail "missing the disable-library-validation entitlement"
! grep -q "com.apple.security.get-task-allow" <<< "${entitlements}" ||
  fail "release build carries get-task-allow"
if [[ "${SIGNED}" == 1 ]]; then
  pass "Scribe.app and librime.1.dylib signed by ${TEAM_ID} with hardened runtime and timestamp"
else
  pass "Scribe.app and librime.1.dylib signed ad hoc with hardened runtime"
fi

"${APP}/Contents/MacOS/Scribe" --help >/dev/null || fail "Scribe.app does not launch"
pass "Scribe.app launches and loads librime"

echo "All checks passed for ${PACKAGE##*/}"
