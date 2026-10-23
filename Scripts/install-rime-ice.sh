#!/bin/bash
# Installs 雾凇拼音 (rime-ice) into Scribe's user directory from its pinned
# upstream release, then asks the running Scribe to redeploy. Only adds or
# replaces rime-ice's own files; never touches Squirrel's ~/Library/Rime.
#
# Set SCRIBE_USER_DIR to install somewhere other than ~/Library/Scribe.

set -euo pipefail

RIME_ICE_VERSION=2026.06.30
RIME_ICE_SHA256=675d23b070be00e1b800f9a6db033ef98f4493cd5b568ed8aa3b3541769c46ac
RIME_ICE_URL="https://github.com/iDvel/rime-ice/releases/download/${RIME_ICE_VERSION}/full.zip"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${SCRIBE_DOWNLOAD_CACHE:-${ROOT}/build/downloads}"
USER_DIR="${SCRIBE_USER_DIR:-${HOME}/Library/Scribe}"
ARCHIVE="${CACHE}/rime-ice-${RIME_ICE_VERSION}-full.zip"
EXECUTABLE="${HOME}/Library/Input Methods/Scribe.app/Contents/MacOS/Scribe"

if ! { [[ -f "${ARCHIVE}" ]] && echo "${RIME_ICE_SHA256}  ${ARCHIVE}" | shasum -a 256 -c --status; }; then
  echo "Downloading rime-ice ${RIME_ICE_VERSION}"
  mkdir -p "${CACHE}"
  curl --fail --location --silent --show-error --retry 3 --output "${ARCHIVE}.part" "${RIME_ICE_URL}"
  if ! echo "${RIME_ICE_SHA256}  ${ARCHIVE}.part" | shasum -a 256 -c --status; then
    rm -f "${ARCHIVE}.part"
    echo "error: checksum mismatch for rime-ice ${RIME_ICE_VERSION}" >&2
    exit 1
  fi
  mv "${ARCHIVE}.part" "${ARCHIVE}"
fi

mkdir -p "${USER_DIR}"
unzip -o -q "${ARCHIVE}" -d "${USER_DIR}"
echo "Installed rime-ice ${RIME_ICE_VERSION} into ${USER_DIR}"

if [[ -z "${SCRIBE_USER_DIR:-}" && -x "${EXECUTABLE}" ]]; then
  "${EXECUTABLE}" --reload
  echo "Asked Scribe to redeploy"
fi
