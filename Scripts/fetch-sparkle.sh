#!/bin/bash
# Downloads the official Sparkle release, which Scribe uses for software
# updates, and lays it out under Frameworks/:
#
#   Frameworks/Sparkle.framework   embedded in Scribe.app; the XPC services
#                                  are removed, since only sandboxed apps use
#                                  them
#   Frameworks/sparkle-bin/        sign_update and generate_keys, release
#                                  tooling that is never bundled
#
# Safe to run repeatedly: it does nothing when Frameworks/ already holds this
# release, and the download is kept in build/downloads (override with
# SCRIBE_DOWNLOAD_CACHE) so it is fetched only once.

set -euo pipefail

SPARKLE_VERSION=2.10.0
SPARKLE_ARCHIVE="Sparkle-${SPARKLE_VERSION}.tar.xz"
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/${SPARKLE_ARCHIVE}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORKS="${ROOT}/Frameworks"
CACHE="${SCRIBE_DOWNLOAD_CACHE:-${ROOT}/build/downloads}"
STAMP="${FRAMEWORKS}/.sparkle-stamp"
# Bump the trailing layout number whenever this script changes what it writes.
STAMP_CONTENT="sparkle ${SPARKLE_VERSION} ${SPARKLE_SHA256} layout 1"

if [[ -f "${STAMP}" && "$(cat "${STAMP}")" == "${STAMP_CONTENT}" &&
      -d "${FRAMEWORKS}/Sparkle.framework" &&
      -x "${FRAMEWORKS}/sparkle-bin/sign_update" &&
      -x "${FRAMEWORKS}/sparkle-bin/generate_keys" ]]; then
  echo "Sparkle ${SPARKLE_VERSION} is already in ${FRAMEWORKS}"
  exit 0
fi

file="${CACHE}/${SPARKLE_ARCHIVE}"
if [[ ! -f "${file}" ]] || ! echo "${SPARKLE_SHA256}  ${file}" | shasum -a 256 -c --status; then
  echo "Downloading ${SPARKLE_ARCHIVE}"
  mkdir -p "${CACHE}"
  curl --fail --location --silent --show-error --retry 3 \
    --output "${file}.part" "${SPARKLE_URL}"
  if ! echo "${SPARKLE_SHA256}  ${file}.part" | shasum -a 256 -c --status; then
    rm -f "${file}.part"
    echo "error: checksum mismatch for ${SPARKLE_ARCHIVE}" >&2
    exit 1
  fi
  mv "${file}.part" "${file}"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/sparkle"
tar -xJf "${file}" -C "${WORK}/sparkle"

# ditto keeps the framework's symlinks. Downloader.xpc and Installer.xpc only
# run when SUEnableDownloaderService or SUEnableInstallerLauncherService is
# set, which only sandboxed apps need. Removing them breaks the framework's
# seal, so sign it again ad hoc; Autoupdate and Updater.app keep Sparkle's own
# signatures, and releases sign everything with Scribe's identity.
ditto "${WORK}/sparkle/Sparkle.framework" "${WORK}/Sparkle.framework"
rm -rf "${WORK}/Sparkle.framework/Versions/B/XPCServices" "${WORK}/Sparkle.framework/XPCServices"
codesign --force --sign - "${WORK}/Sparkle.framework" 2>/dev/null

mkdir -p "${WORK}/sparkle-bin"
for tool in sign_update generate_keys; do
  cp "${WORK}/sparkle/bin/${tool}" "${WORK}/sparkle-bin/"
done

mkdir -p "${FRAMEWORKS}"
rm -rf "${FRAMEWORKS:?}/Sparkle.framework" "${FRAMEWORKS:?}/sparkle-bin" "${STAMP}"
mv "${WORK}/Sparkle.framework" "${FRAMEWORKS}/"
mv "${WORK}/sparkle-bin" "${FRAMEWORKS}/"
echo "${STAMP_CONTENT}" > "${STAMP}"

echo "Installed Sparkle ${SPARKLE_VERSION} into ${FRAMEWORKS}"
