#!/bin/bash
# Downloads the official librime release for macOS and the default Rime data,
# and lays them out under Frameworks/:
#
#   Frameworks/librime.xcframework   librime.1.dylib, its headers and a module map
#   Frameworks/rime-plugins/         librime-lua, librime-octagram, librime-predict
#   Frameworks/opencc/               OpenCC dictionaries and configs
#   Frameworks/rime-data/            the schemas plum installs by default (as
#                                    Squirrel ships them), as shared data
#   Frameworks/bin/                  rime_deployer and rime_dict_manager, which
#                                    find librime in ../Frameworks, and plum's
#                                    rime-install, as Squirrel ships them
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

# plum, for its rime-install script.
PLUM_COMMIT=b1be1969f914cc005add4090631b855db00c2591
PLUM_SHA256=4ebc2bec937766184546f9c0598f90a692a2e0ef1a50c0c2e594dbb3e131f61e

# Default data, pinned to commits: repository, commit, sha256 of the archive.
RIME_DATA=(
  "rime-prelude 082425ea0684bca36474415d4a0e8db9b016487e 66239ba4745d54471e5ce5540b45e86ec663ff5dba004cb23c95531a3bdec00f"
  "rime-essay 054920de4f54c9e5994276a96a4fc2a35cb51aa3 3339b40aae91b0216d393aeccc6a8f7daad56a1f3a5e1ffcf464c80690d1b6ce"
  "rime-luna-pinyin 56b934b099dfbeab842320f13aa8b461a6ab3e42 876c7ba559794f476abf7195a255aea29000cee281e6f5ec664928dce018bd90"
  "rime-stroke 1e8fff9b9494ddec23b0cbc526bcfd8171a6fd48 1347a57ab4cf269be9b1c49ce50facfe60617207f2780604fe82914070da8a80"
  "rime-terra-pinyin 723e51bc266cf9464530c1ddedb856aa18e3da34 34dd53684366f2e6b6598fa019ab68171aaa738da064768fab0d4349530f5841"
  "rime-bopomofo 6085c9a38a4a728047862b33d67eee18aa86f3b9 5fc0719e8fe9b2eb8aa05c505ffb2b39d972e637951531182dd7d745a83bda51"
  "rime-cangjie 52d90a1b1312e74042b38c1cbc8142defbc53171 18d989bf21d0bb86b402f18be4dd060bf2653896c95448afb01d4da2e6be5464"
  "rime-quick 5dcdb9e353d314239e9c8cddc0f42d52da4837bb 2f2ae291b1ebd17ad5bfccfabbeb3aba2a466589628f15172da5fc76b24b9f7e"
)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORKS="${ROOT}/Frameworks"
CACHE="${SCRIBE_DOWNLOAD_CACHE:-${ROOT}/build/downloads}"
STAMP="${FRAMEWORKS}/.librime-stamp"
# Bump the trailing layout number whenever this script changes what it writes.
STAMP_CONTENT="librime ${LIBRIME_VERSION} ${RIME_SHA256} ${DEPS_SHA256} ${RIME_DATA[*]} plum ${PLUM_SHA256} layout 3"

if [[ -f "${STAMP}" && "$(cat "${STAMP}")" == "${STAMP_CONTENT}" &&
      -d "${FRAMEWORKS}/librime.xcframework" &&
      -d "${FRAMEWORKS}/rime-plugins" &&
      -d "${FRAMEWORKS}/opencc" &&
      -d "${FRAMEWORKS}/rime-data" &&
      -d "${FRAMEWORKS}/bin" ]]; then
  echo "librime ${LIBRIME_VERSION} is already in ${FRAMEWORKS}"
  exit 0
fi

# Downloads $1 into the cache unless a copy with checksum $2 is already there.
# $3 is the URL, by default the librime release asset named $1.
fetch() {
  local name="$1" sha256="$2" url="${3:-${BASE_URL}/$1}"
  local file="${CACHE}/${name}"
  if [[ -f "${file}" ]] && echo "${sha256}  ${file}" | shasum -a 256 -c --status; then
    return
  fi
  echo "Downloading ${name}"
  mkdir -p "${CACHE}"
  curl --fail --location --silent --show-error --retry 3 \
    --output "${file}.part" "${url}"
  if ! echo "${sha256}  ${file}.part" | shasum -a 256 -c --status; then
    rm -f "${file}.part"
    echo "error: checksum mismatch for ${name}" >&2
    exit 1
  fi
  mv "${file}.part" "${file}"
}

fetch "${RIME_ARCHIVE}" "${RIME_SHA256}"
fetch "${DEPS_ARCHIVE}" "${DEPS_SHA256}"
for entry in "${RIME_DATA[@]}"; do
  read -r repository commit sha256 <<< "${entry}"
  fetch "${repository}-${commit}.tar.gz" "${sha256}" "https://github.com/rime/${repository}/archive/${commit}.tar.gz"
done
fetch "plum-${PLUM_COMMIT}.tar.gz" "${PLUM_SHA256}" "https://github.com/rime/plum/archive/${PLUM_COMMIT}.tar.gz"

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

# Only the data files; the archives also hold READMEs, licenses and tooling.
mkdir -p "${WORK}/rime-data"
for entry in "${RIME_DATA[@]}"; do
  read -r repository commit _ <<< "${entry}"
  mkdir -p "${WORK}/data/${repository}"
  tar -xzf "${CACHE}/${repository}-${commit}.tar.gz" -C "${WORK}/data/${repository}" --strip-components 1
  find "${WORK}/data/${repository}" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.txt' \) \
    -exec cp {} "${WORK}/rime-data/" \;
done

# The command line tools look for librime next to the app's executables, in
# ../Frameworks. Changing them invalidates their signature, so sign them
# again ad hoc; releases sign them properly.
mkdir -p "${WORK}/bin" "${WORK}/plum"
for tool in rime_deployer rime_dict_manager; do
  cp "${DIST}/bin/${tool}" "${WORK}/bin/"
  install_name_tool -add_rpath "@loader_path/../Frameworks" "${WORK}/bin/${tool}" 2>/dev/null
  codesign --force --sign - "${WORK}/bin/${tool}" 2>/dev/null
done
tar -xzf "${CACHE}/plum-${PLUM_COMMIT}.tar.gz" -C "${WORK}/plum" --strip-components 1
cp "${WORK}/plum/rime-install" "${WORK}/bin/"
chmod +x "${WORK}/bin/rime-install"

mkdir -p "${FRAMEWORKS}"
rm -rf "${FRAMEWORKS:?}/librime.xcframework" "${FRAMEWORKS:?}/rime-plugins" "${FRAMEWORKS:?}/opencc" \
  "${FRAMEWORKS:?}/rime-data" "${FRAMEWORKS:?}/bin" "${STAMP}"
mv "${WORK}/librime.xcframework" "${FRAMEWORKS}/"
cp -pR "${DIST}/lib/rime-plugins" "${FRAMEWORKS}/rime-plugins"
cp -pR "${WORK}/deps/share/opencc" "${FRAMEWORKS}/opencc"
mv "${WORK}/rime-data" "${FRAMEWORKS}/rime-data"
mv "${WORK}/bin" "${FRAMEWORKS}/bin"
cp "${WORK}/rime/version-info.txt" "${FRAMEWORKS}/librime-version-info.txt"
echo "${STAMP_CONTENT}" > "${STAMP}"

echo "Installed librime ${LIBRIME_VERSION} into ${FRAMEWORKS}"
