#!/bin/bash
# Downloads the official librime release for macOS and lays it out under
# Frameworks/:
#
#   Frameworks/librime.xcframework   librime.1.dylib, its headers and a module map
#   Frameworks/rime-plugins/         librime-lua, librime-octagram, librime-predict
#   Frameworks/opencc/               OpenCC dictionaries and configs
#
# Safe to run repeatedly: it does nothing when Frameworks/ already holds this
# release, and downloads are kept in build/downloads (override with
# SCRIBE_DOWNLOAD_CACHE) so they are fetched only once.

set -euo pipefail

LIBRIME_VERSION=1.17.0
LIBRIME_COMMIT=33e7814
RIME_ARCHIVE="rime-${LIBRIME_COMMIT}-macOS-universal.tar.bz2"
RIME_SHA256=11d8dc663c6ec06d5ccb6111ba664a9e7b631b703ac6acd07cffbac664021850
DEPS_ARCHIVE="rime-deps-${LIBRIME_COMMIT}-macOS-universal.tar.bz2"
DEPS_SHA256=dfe6047e87be271963d7466bd1a6e3d9e660c30e5e73e4bb94e8782c0a6ac8df
BASE_URL="https://github.com/rime/librime/releases/download/${LIBRIME_VERSION}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORKS="${ROOT}/Frameworks"
CACHE="${SCRIBE_DOWNLOAD_CACHE:-${ROOT}/build/downloads}"
STAMP="${FRAMEWORKS}/.librime-stamp"
# Bump the trailing layout number whenever this script changes what it writes.
STAMP_CONTENT="librime ${LIBRIME_VERSION} ${RIME_SHA256} ${DEPS_SHA256} layout 1"

if [[ -f "${STAMP}" && "$(cat "${STAMP}")" == "${STAMP_CONTENT}" &&
      -d "${FRAMEWORKS}/librime.xcframework" &&
      -d "${FRAMEWORKS}/rime-plugins" &&
      -d "${FRAMEWORKS}/opencc" ]]; then
  echo "librime ${LIBRIME_VERSION} is already in ${FRAMEWORKS}"
  exit 0
fi

# Downloads $1 into the cache unless a copy with checksum $2 is already there.
fetch() {
  local name="$1" sha256="$2"
  local file="${CACHE}/${name}"
  if [[ -f "${file}" ]] && echo "${sha256}  ${file}" | shasum -a 256 -c --status; then
    return
  fi
  echo "Downloading ${name}"
  mkdir -p "${CACHE}"
  curl --fail --location --silent --show-error --retry 3 \
    --output "${file}.part" "${BASE_URL}/${name}"
  if ! echo "${sha256}  ${file}.part" | shasum -a 256 -c --status; then
    rm -f "${file}.part"
    echo "error: checksum mismatch for ${name}" >&2
    exit 1
  fi
  mv "${file}.part" "${file}"
}

fetch "${RIME_ARCHIVE}" "${RIME_SHA256}"
fetch "${DEPS_ARCHIVE}" "${DEPS_SHA256}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

mkdir -p "${WORK}/rime" "${WORK}/deps"
tar -xjf "${CACHE}/${RIME_ARCHIVE}" -C "${WORK}/rime"
tar -xjf "${CACHE}/${DEPS_ARCHIVE}" -C "${WORK}/deps"
DIST="${WORK}/rime/dist"

# librime.1.dylib keeps its install name (@rpath/librime.1.dylib), which the
# plugins link against, so it must not be renamed.
mkdir -p "${WORK}/stage/lib" "${WORK}/stage/Headers"
cp -L "${DIST}/lib/librime.1.dylib" "${WORK}/stage/lib/"
cp "${DIST}/include/"*.h "${WORK}/stage/Headers/"

# rime_api_stdbool.h only defines macros; it must come before rime_api.h to
# select the stdbool flavor of the API.
cat > "${WORK}/stage/Headers/librime.h" <<'EOF'
#include "rime_api_stdbool.h"
#include "rime_api.h"
#include "rime_levers_api.h"
EOF
cat > "${WORK}/stage/Headers/module.modulemap" <<'EOF'
module librime [system] {
    header "librime.h"
    export *
}
EOF

xcodebuild -create-xcframework \
  -library "${WORK}/stage/lib/librime.1.dylib" \
  -headers "${WORK}/stage/Headers" \
  -output "${WORK}/librime.xcframework" >/dev/null

mkdir -p "${FRAMEWORKS}"
rm -rf "${FRAMEWORKS}/librime.xcframework" "${FRAMEWORKS}/rime-plugins" "${FRAMEWORKS}/opencc" "${STAMP}"
mv "${WORK}/librime.xcframework" "${FRAMEWORKS}/"
cp -pR "${DIST}/lib/rime-plugins" "${FRAMEWORKS}/rime-plugins"
cp -pR "${WORK}/deps/share/opencc" "${FRAMEWORKS}/opencc"
cp "${WORK}/rime/version-info.txt" "${FRAMEWORKS}/librime-version-info.txt"
echo "${STAMP_CONTENT}" > "${STAMP}"

echo "Installed librime ${LIBRIME_VERSION} into ${FRAMEWORKS}"
