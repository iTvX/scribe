#!/bin/bash
# Builds Scribe's release package: Scribe.app signed with Developer ID and the
# hardened runtime, in a .pkg that installs into /Library/Input Methods,
# signed with Developer ID Installer, notarized and stapled.
#
#   Scripts/build-release.sh              signed and notarized package
#   Scripts/build-release.sh --unsigned   ad hoc signed app in an unsigned
#                                         package, to check packaging without
#                                         credentials (CI uses this)
#
# The package is written to build/release/Scribe-<version>-<build>.pkg.
#
# Signing settings come from the environment, as in mac-switch's release
# script; on the release Mac the runner provides them:
#   KEYCHAIN_DB             keychain holding the Developer ID identities (required)
#   KEYCHAIN_PASSWORD_FILE  file holding that keychain's password; read at
#                           run time and never printed
#   SIGN_IDENTITY           default: Developer ID Application: Zijie Yu (AW54C93V4H)
#   INSTALLER_IDENTITY      default: Developer ID Installer: Zijie Yu (AW54C93V4H)
#   NOTARY_PROFILE          notarytool keychain profile (required unless
#                           SKIP_NOTARIZATION=1)
#   NOTARY_KEYCHAIN         keychain holding that profile (default: the search list)
#   SKIP_NOTARIZATION=1     sign without notarizing, for local checks only
#   BUILD_NUMBER            CFBundleVersion (default: UTC timestamp)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${ROOT}/build/release"
DERIVED_DATA="${ROOT}/build/DerivedData-release"
BUNDLE_ID="io.github.itvx.inputmethod.Scribe"
INSTALL_LOCATION="/Library/Input Methods"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"

SIGNED=1
case "${1:-}" in
  --unsigned) SIGNED=0 ;;
  "") ;;
  *) echo "usage: $0 [--unsigned]" >&2; exit 2 ;;
esac

if [[ "${SIGNED}" == 1 ]]; then
  : "${KEYCHAIN_DB:?set KEYCHAIN_DB to the keychain holding the Developer ID identities}"
  SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Zijie Yu (AW54C93V4H)}"
  INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-Developer ID Installer: Zijie Yu (AW54C93V4H)}"
  if [[ "${SKIP_NOTARIZATION:-0}" != 1 ]]; then
    : "${NOTARY_PROFILE:?set NOTARY_PROFILE to the notarytool keychain profile, or SKIP_NOTARIZATION=1}"
  fi
  NOTARY_KEYCHAIN="${NOTARY_KEYCHAIN:-}"

  if [[ -n "${KEYCHAIN_PASSWORD_FILE:-}" ]]; then
    if [[ ! -f "${KEYCHAIN_PASSWORD_FILE}" || -L "${KEYCHAIN_PASSWORD_FILE}" ]]; then
      echo "error: the keychain password file is missing or is a symlink" >&2
      exit 1
    fi
    security unlock-keychain -p "$(<"${KEYCHAIN_PASSWORD_FILE}")" "${KEYCHAIN_DB}"
    if [[ -n "${NOTARY_KEYCHAIN}" && "${NOTARY_KEYCHAIN}" != "${KEYCHAIN_DB}" ]]; then
      security unlock-keychain -p "$(<"${KEYCHAIN_PASSWORD_FILE}")" "${NOTARY_KEYCHAIN}"
    fi
  fi

  if ! security find-identity -v -p codesigning "${KEYCHAIN_DB}" | grep -qF "\"${SIGN_IDENTITY}\""; then
    echo "error: signing identity \"${SIGN_IDENTITY}\" is not in ${KEYCHAIN_DB}" >&2
    exit 1
  fi
  # Not -v: the Developer ID G2 intermediate that issued the installer
  # certificate is only in KEYCHAIN_DB, which is not on the search list, so
  # find-identity cannot complete the chain and reports it as untrusted.
  # check-release.sh verifies the finished package signature instead.
  if ! security find-identity "${KEYCHAIN_DB}" | grep -qF "\"${INSTALLER_IDENTITY}\""; then
    echo "error: installer identity \"${INSTALLER_IDENTITY}\" is not in ${KEYCHAIN_DB}" >&2
    exit 1
  fi
  CODESIGN_ARGS=(--sign "${SIGN_IDENTITY}" --keychain "${KEYCHAIN_DB}" --timestamp)
else
  CODESIGN_ARGS=(--sign - --timestamp=none)
fi

"${ROOT}/Scripts/fetch-librime.sh"
xcodegen generate --quiet --spec "${ROOT}/project.yml"
# Build unsigned and sign below, so nothing from Xcode's local signing (such as
# the get-task-allow entitlement) ends up in the release.
xcodebuild -quiet \
  -project "${ROOT}/Scribe.xcodeproj" \
  -scheme Scribe \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  -destination "generic/platform=macOS" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  CODE_SIGNING_ALLOWED=NO \
  build

rm -rf "${OUTPUT}"
mkdir -p "${OUTPUT}/root"
APP="${OUTPUT}/root/Scribe.app"
ditto "${DERIVED_DATA}/Build/Products/Release/Scribe.app" "${APP}"

# Sign inside out: embedded libraries first, then the app.
while IFS= read -r -d '' library; do
  codesign --force --options runtime "${CODESIGN_ARGS[@]}" "${library}"
done < <(find "${APP}/Contents/Frameworks" -depth -type f -name '*.dylib' -print0)
codesign --force --options runtime "${CODESIGN_ARGS[@]}" \
  --entitlements "${ROOT}/App/Scribe.entitlements" "${APP}"
codesign --verify --strict --deep "${APP}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
PACKAGE="${OUTPUT}/Scribe-${VERSION}-${BUILD_NUMBER}.pkg"

pkgbuild --quiet \
  --root "${OUTPUT}/root" \
  --component-plist "${ROOT}/Scripts/pkg/Scribe-component.plist" \
  --identifier "${BUNDLE_ID}" \
  --version "${VERSION}" \
  --install-location "${INSTALL_LOCATION}" \
  --scripts "${ROOT}/Scripts/pkg/scripts" \
  "${OUTPUT}/Scribe-component.pkg"
sed "s/@VERSION@/${VERSION}/g" "${ROOT}/Scripts/pkg/Distribution.xml" > "${OUTPUT}/Distribution.xml"
productbuild --quiet \
  --distribution "${OUTPUT}/Distribution.xml" \
  --package-path "${OUTPUT}" \
  "${OUTPUT}/Scribe-unsigned.pkg"

if [[ "${SIGNED}" == 1 ]]; then
  productsign --keychain "${KEYCHAIN_DB}" --sign "${INSTALLER_IDENTITY}" --timestamp \
    "${OUTPUT}/Scribe-unsigned.pkg" "${PACKAGE}"
  rm "${OUTPUT}/Scribe-unsigned.pkg"

  if [[ "${SKIP_NOTARIZATION:-0}" != 1 ]]; then
    NOTARY_ARGS=(--keychain-profile "${NOTARY_PROFILE}")
    [[ -n "${NOTARY_KEYCHAIN}" ]] && NOTARY_ARGS+=(--keychain "${NOTARY_KEYCHAIN}")
    echo "Submitting ${PACKAGE##*/} for notarization"
    xcrun notarytool submit "${PACKAGE}" "${NOTARY_ARGS[@]}" --wait \
      --output-format json > "${OUTPUT}/notarization.json"
    status="$(plutil -extract status raw -o - "${OUTPUT}/notarization.json")"
    if [[ "${status}" != "Accepted" ]]; then
      submission="$(plutil -extract id raw -o - "${OUTPUT}/notarization.json")"
      echo "error: notarization finished with status ${status}" >&2
      xcrun notarytool log "${submission}" "${NOTARY_ARGS[@]}" >&2 || true
      exit 1
    fi
    xcrun stapler staple "${PACKAGE}"
  fi
else
  mv "${OUTPUT}/Scribe-unsigned.pkg" "${PACKAGE}"
fi

rm -rf "${OUTPUT}/root" "${OUTPUT}/Scribe-component.pkg" "${OUTPUT}/Distribution.xml"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "package=${PACKAGE}"
    echo "name=$(basename "${PACKAGE}" .pkg)"
  } >> "${GITHUB_OUTPUT}"
fi
echo "Built ${PACKAGE}"
