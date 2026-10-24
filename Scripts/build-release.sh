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
#
# Software updates (docs/decisions/0011-releases-and-updates.md), both or
# neither; without them the app never checks for updates:
#   SPARKLE_FEED_URL        the appcast installed copies check (https)
#   SPARKLE_PUBLIC_KEY      the public half of the update signing key, base64

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

# Software updates: the feed and its key go into the app together, or not at all.
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
if [[ -n "${SPARKLE_FEED_URL}" || -n "${SPARKLE_PUBLIC_KEY}" ]]; then
  if [[ -z "${SPARKLE_FEED_URL}" || -z "${SPARKLE_PUBLIC_KEY}" ]]; then
    echo "error: set both SPARKLE_FEED_URL and SPARKLE_PUBLIC_KEY, or neither" >&2
    exit 2
  fi
  if [[ "${SPARKLE_FEED_URL}" != https://* ]]; then
    echo "error: SPARKLE_FEED_URL must be an https URL" >&2
    exit 2
  fi
  # 32 bytes are 43 base64 characters and one "=".
  if [[ ! "${SPARKLE_PUBLIC_KEY}" =~ ^[A-Za-z0-9+/]{43}=$ ]] ||
     [[ "$(base64 -D <<< "${SPARKLE_PUBLIC_KEY}" | wc -c | tr -d ' ')" != 32 ]]; then
    echo "error: SPARKLE_PUBLIC_KEY must be a base64 Ed25519 public key (32 bytes)" >&2
    exit 2
  fi
fi

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
  if ! security find-identity "${KEYCHAIN_DB}" | grep -qF "\"${INSTALLER_IDENTITY}\""; then
    echo "error: installer identity \"${INSTALLER_IDENTITY}\" is not in ${KEYCHAIN_DB}" >&2
    exit 1
  fi
  # productsign only accepts an identity whose chain it can build from the
  # keychain search list, and the system roots lack the Developer ID G2
  # intermediate that issues installer certificates.
  if ! security find-identity -v "${KEYCHAIN_DB}" | grep -qF "\"${INSTALLER_IDENTITY}\""; then
    echo "error: \"${INSTALLER_IDENTITY}\" has no trusted certificate chain." >&2
    echo "Import the Developer ID G2 intermediate into the login keychain:" >&2
    echo "  https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer" >&2
    exit 1
  fi
  CODESIGN_ARGS=(--sign "${SIGN_IDENTITY}" --keychain "${KEYCHAIN_DB}" --timestamp)
else
  CODESIGN_ARGS=(--sign - --timestamp=none)
fi

"${ROOT}/Scripts/fetch-librime.sh"
"${ROOT}/Scripts/fetch-sparkle.sh"
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

# Software updates: only release builds carry the feed and its key.
if [[ -n "${SPARKLE_FEED_URL}" ]]; then
  for entry in "SUFeedURL ${SPARKLE_FEED_URL}" "SUPublicEDKey ${SPARKLE_PUBLIC_KEY}"; do
    read -r key value <<< "${entry}"
    /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "${APP}/Contents/Info.plist" 2>/dev/null ||
      /usr/libexec/PlistBuddy -c "Add :${key} string ${value}" "${APP}/Contents/Info.plist"
  done
fi

# Sign inside out: embedded libraries first, then the command line tools next
# to Scribe, then the app. The tools load librime, so they get the app's
# entitlements; rime-install is a shell script, signed in extended attributes.
while IFS= read -r -d '' library; do
  codesign --force --options runtime "${CODESIGN_ARGS[@]}" "${library}"
done < <(find "${APP}/Contents/Frameworks" -depth -type f -name '*.dylib' -print0)
# Sparkle, inside out, as its documentation describes; none of it needs
# entitlements.
SPARKLE="${APP}/Contents/Frameworks/Sparkle.framework"
for code in "${SPARKLE}/Versions/B/Autoupdate" "${SPARKLE}/Versions/B/Updater.app" "${SPARKLE}"; do
  codesign --force --options runtime "${CODESIGN_ARGS[@]}" "${code}"
done
for tool in rime_deployer rime_dict_manager; do
  codesign --force --options runtime "${CODESIGN_ARGS[@]}" \
    --entitlements "${ROOT}/App/Scribe.entitlements" "${APP}/Contents/MacOS/${tool}"
done
codesign --force --options runtime "${CODESIGN_ARGS[@]}" "${APP}/Contents/MacOS/rime-install"
# Scribe Settings, inside Scribe.app. It loads Scribe.app's librime, so it
# carries the same library validation exemption as the app.
codesign --force --options runtime "${CODESIGN_ARGS[@]}" \
  --entitlements "${ROOT}/Settings/ScribeSettings.entitlements" "${APP}/Contents/Helpers/ScribeSettings.app"
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
