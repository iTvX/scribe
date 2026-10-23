#!/bin/bash
# Writes what a release publishes: the package, the signed Sparkle appcast and
# the GitHub release description.
#
#   Scripts/make-appcast.sh path/to/Scribe.pkg output-dir
#
#   output-dir/Scribe-<version>.pkg   the package, under the name users download
#   output-dir/appcast.xml            this release first, then the published
#                                     feed's items; signed
#   output-dir/release-notes.md       the GitHub release description: the
#                                     CHANGELOG section and the package's SHA-256
#
# Settings come from the environment:
#   SPARKLE_KEY_FILE        file holding the base64 private key, for throwaway
#                           keys. Without it the key comes from the release
#                           keychain:
#   KEYCHAIN_DB             the release keychain, as in build-release.sh
#   KEYCHAIN_PASSWORD_FILE  its password, read at run time and never printed
#   SPARKLE_KEY_ACCOUNT     account of the key's generic password (service
#                           https://sparkle-project.org)
#   RELEASE_TAG             the tag being published; empty for validation, which
#                           builds the feed as if v<version> were published
#   APPCAST_EXISTING        the feed to extend: a URL (default: the app's
#                           SUFeedURL), a file, or "none" for a new feed
#   GITHUB_REPOSITORY       owner/repo for download URLs (default: iTvX/scribe)
#
# The private key is only ever piped into sign_update and the release tool; it
# is never kept in a variable, a file or the log.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="${ROOT}/Scripts/release-tool.sh"
SIGN_UPDATE="${ROOT}/Frameworks/sparkle-bin/sign_update"
REPO="${GITHUB_REPOSITORY:-iTvX/scribe}"

if [[ $# -ne 2 || ! -f "$1" ]]; then
  echo "usage: $0 path/to/Scribe.pkg output-dir" >&2
  exit 2
fi
PACKAGE="$1"
OUTPUT="$2"

fail() {
  echo "error: $*" >&2
  exit 1
}

if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
  [[ -f "${SPARKLE_KEY_FILE}" ]] || fail "SPARKLE_KEY_FILE ${SPARKLE_KEY_FILE} does not exist"
else
  : "${KEYCHAIN_DB:?set KEYCHAIN_DB to the release keychain, or SPARKLE_KEY_FILE to a key file}"
  : "${SPARKLE_KEY_ACCOUNT:?set SPARKLE_KEY_ACCOUNT to the account of the update signing key}"
  if [[ -n "${KEYCHAIN_PASSWORD_FILE:-}" ]]; then
    if [[ ! -f "${KEYCHAIN_PASSWORD_FILE}" || -L "${KEYCHAIN_PASSWORD_FILE}" ]]; then
      fail "the keychain password file is missing or is a symlink"
    fi
    security unlock-keychain -p "$(<"${KEYCHAIN_PASSWORD_FILE}")" "${KEYCHAIN_DB}"
  fi
fi

# Writes the private key to standard output, for a pipe.
private_key() {
  if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
    cat "${SPARKLE_KEY_FILE}"
  else
    security find-generic-password -s https://sparkle-project.org -a "${SPARKLE_KEY_ACCOUNT}" -w "${KEYCHAIN_DB}"
  fi
}

"${ROOT}/Scripts/fetch-sparkle.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# 1. What the package installs.
pkgutil --expand-full "${PACKAGE}" "${WORK}/expanded"
PLIST="${WORK}/expanded/Scribe-component.pkg/Payload/Scribe.app/Contents/Info.plist"
[[ -f "${PLIST}" ]] || fail "the package has no Scribe.app"
plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "${PLIST}" 2>/dev/null || true
}
VERSION="$(plist_value CFBundleShortVersionString)"
BUILD="$(plist_value CFBundleVersion)"
MINIMUM_SYSTEM="$(plist_value LSMinimumSystemVersion)"
FEED_URL="$(plist_value SUFeedURL)"
PUBLIC_KEY="$(plist_value SUPublicEDKey)"
if [[ -z "${FEED_URL}" || -z "${PUBLIC_KEY}" ]]; then
  fail "the package's Scribe.app has no SUFeedURL or SUPublicEDKey; build it with SPARKLE_FEED_URL and SPARKLE_PUBLIC_KEY"
fi
echo "Scribe.app ${VERSION} (${BUILD}), checks ${FEED_URL}"

# 2. The tag, real or as if v<version> were published.
TAG="${RELEASE_TAG:-v${VERSION}}"
tag_info="$("${TOOL}" tag "${TAG}")" || fail "${TAG} is not a release tag"
TAG_VERSION="$(sed -n 's/^version=//p' <<< "${tag_info}")"
CHANNEL="$(sed -n 's/^channel=//p' <<< "${tag_info}")"
[[ "${TAG_VERSION}" == "${VERSION}" ]] || fail "${TAG} is version ${TAG_VERSION}, but the app is ${VERSION}"

# 3. Release notes.
NOTES="${WORK}/notes.md"
status=0
"${TOOL}" notes "${VERSION}" "${ROOT}/CHANGELOG.md" > "${NOTES}" || status=$?
if [[ "${status}" == 1 && -z "${RELEASE_TAG:-}" ]]; then
  echo "warning: CHANGELOG.md has no section for ${VERSION}; using placeholder notes for this validation build" >&2
  echo "Validation build, not published." > "${NOTES}"
elif [[ "${status}" != 0 ]]; then
  fail "CHANGELOG.md needs a \"## ${VERSION}\" section before ${TAG} can be published"
fi

# 4. The key must be the one installed copies trust, before anything is signed.
signing_key="$(private_key | "${TOOL}" key public)" || fail "could not read the update signing key"
if [[ "${signing_key}" != "${PUBLIC_KEY}" ]]; then
  fail "the signing key's public key ${signing_key} is not the app's SUPublicEDKey ${PUBLIC_KEY}"
fi

# 5. The package, under its download name, and its signature.
mkdir -p "${OUTPUT}"
RELEASE_PACKAGE="${OUTPUT}/Scribe-${VERSION}.pkg"
rm -f "${RELEASE_PACKAGE}" "${OUTPUT}/appcast.xml" "${OUTPUT}/release-notes.md"
cp "${PACKAGE}" "${RELEASE_PACKAGE}"
# sign_update's errors go to standard output; they are not repeated here, in
# case one quotes the key.
signature="$(private_key | "${SIGN_UPDATE}" --ed-key-file - -p "${RELEASE_PACKAGE}")" ||
  fail "sign_update could not sign the package"

# 6. The feed to extend.
EXISTING="${APPCAST_EXISTING:-${FEED_URL}}"
existing_args=()
case "${EXISTING}" in
  none)
    echo "Starting a new feed"
    ;;
  http://* | https://*)
    http_code="$(curl --silent --show-error --location --retry 3 \
      -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
      --output "${WORK}/published.xml" --write-out '%{http_code}' "${EXISTING}")"
    case "${http_code}" in
      200)
        echo "Extending the feed published at ${EXISTING}"
        existing_args=(--existing "${WORK}/published.xml")
        ;;
      404)
        echo "Nothing is published at ${EXISTING} yet; starting a new feed for the first release"
        ;;
      *)
        fail "fetching ${EXISTING} returned HTTP ${http_code}"
        ;;
    esac
    ;;
  *)
    [[ -f "${EXISTING}" ]] || fail "no feed at ${EXISTING}"
    echo "Extending ${EXISTING}"
    existing_args=(--existing "${EXISTING}")
    ;;
esac

# 7. The feed, with this release first.
URL="https://github.com/${REPO}/releases/download/${TAG}/Scribe-${VERSION}.pkg"
channel_args=()
if [[ -n "${CHANNEL}" ]]; then
  channel_args=(--channel "${CHANNEL}")
fi
"${TOOL}" appcast \
  --output "${OUTPUT}/appcast.xml" \
  ${existing_args[@]+"${existing_args[@]}"} \
  --title "中书 ${VERSION}" \
  --short-version "${VERSION}" \
  --build "${BUILD}" \
  ${channel_args[@]+"${channel_args[@]}"} \
  --minimum-system "${MINIMUM_SYSTEM}" \
  --notes "${NOTES}" \
  --url "${URL}" \
  --package "${RELEASE_PACKAGE}" \
  --signature "${signature}" \
  --feed-link "https://github.com/${REPO}"

# 8. Sign the feed, check it with Sparkle's tool, then independently against
# the app's SUPublicEDKey, the key installed copies trust.
private_key | "${SIGN_UPDATE}" --ed-key-file - "${OUTPUT}/appcast.xml" >/dev/null
private_key | "${SIGN_UPDATE}" --verify --ed-key-file - "${OUTPUT}/appcast.xml"
"${TOOL}" verify \
  --feed "${OUTPUT}/appcast.xml" \
  --package "${RELEASE_PACKAGE}" \
  --url "${URL}" \
  --public-key "${PUBLIC_KEY}" \
  --build "${BUILD}" \
  --short-version "${VERSION}" \
  ${channel_args[@]+"${channel_args[@]}"}

# 9. The release description.
sha256="$(shasum -a 256 "${RELEASE_PACKAGE}" | cut -d ' ' -f 1)"
{
  cat "${NOTES}"
  echo
  echo "---"
  echo
  echo "\`Scribe-${VERSION}.pkg\` 的 SHA-256：\`${sha256}\`"
} > "${OUTPUT}/release-notes.md"

echo "Wrote, for ${TAG}${CHANNEL:+ (channel ${CHANNEL})}:"
echo "  ${RELEASE_PACKAGE}"
echo "  ${OUTPUT}/appcast.xml ($(grep -c '<item>' "${OUTPUT}/appcast.xml") items)"
echo "  ${OUTPUT}/release-notes.md"
