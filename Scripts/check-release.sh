#!/bin/bash
# Verifies a package built by build-release.sh without installing it.
#
#   Scripts/check-release.sh path/to/Scribe.pkg              signed and notarized
#   Scripts/check-release.sh --unsigned path/to/Scribe.pkg   from build-release.sh --unsigned
#
# After --unsigned, --expect-feed URL fails unless the app checks for updates
# at URL.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM_ID="AW54C93V4H"
BUNDLE_ID="io.github.itvx.inputmethod.Scribe"

SIGNED=1
if [[ "${1:-}" == "--unsigned" ]]; then
  SIGNED=0
  shift
fi
# Software updates: the feed release builds must check.
EXPECT_FEED=""
if [[ "${1:-}" == "--expect-feed" && $# -ge 2 ]]; then
  EXPECT_FEED="$2"
  shift 2
fi
if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: $0 [--unsigned] [--expect-feed URL] path/to/Scribe.pkg" >&2
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
mkdir "${WORK}/artifacts.noindex"
pkgutil --expand-full "${PACKAGE}" "${WORK}/artifacts.noindex/expanded"

component="${WORK}/artifacts.noindex/expanded/Scribe-component.pkg"
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
[[ "$(/usr/libexec/PlistBuddy -c 'Print :TISInputSourceID' "${APP}/Contents/Info.plist")" == "${BUNDLE_ID}" ]] ||
  fail "unexpected input source identifier"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :InputMethodConnectionName' "${APP}/Contents/Info.plist")" == "${BUNDLE_ID}_Connection" ]] ||
  fail "unexpected input method connection"
for mode in Hans Hant; do
  [[ "$(/usr/libexec/PlistBuddy -c "Print :ComponentInputModeDict:tsInputModeListKey:${BUNDLE_ID}.${mode}:TISInputSourceID" "${APP}/Contents/Info.plist")" == "${BUNDLE_ID}.${mode}" ]] ||
    fail "unexpected ${mode} input mode identifier"
done
for arch in arm64 x86_64; do
  lipo "${APP}/Contents/MacOS/Scribe" -verify_arch "${arch}" || fail "executable lacks ${arch}"
done
[[ -f "${APP}/Contents/Frameworks/librime.1.dylib" ]] || fail "librime.1.dylib is not embedded"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Contents/Info.plist")"
pass "Scribe.app ${version} (${build}) is universal and embeds librime.1.dylib"

PLUGINS=(lua octagram predict)
for plugin in "${PLUGINS[@]}"; do
  [[ -f "${APP}/Contents/Frameworks/rime-plugins/librime-${plugin}.dylib" ]] || fail "plugin ${plugin} is not embedded"
done
for file in default.yaml squirrel.yaml scribe.yaml essay.txt luna_pinyin.schema.yaml quick5.schema.yaml \
    grammar.yaml zh-hant-t-essay-bgw.gram zh-hant-t-essay-bgc.gram opencc/s2t.json opencc/STCharacters.ocd2; do
  [[ -f "${APP}/Contents/SharedSupport/${file}" ]] || fail "shared data lacks ${file}"
done
pass "embeds the ${PLUGINS[*]} plugins, default Rime data, octagram grammar, squirrel.yaml, scribe.yaml and OpenCC data"

for file in default.yaml luna_pinyin.prism.bin luna_pinyin.table.bin quick5.table.bin; do
  [[ -s "${APP}/Contents/SharedSupport/build/${file}" ]] || fail "signed shared data lacks prebuilt ${file}"
done
for file in installation.yaml user.yaml; do
  [[ ! -e "${APP}/Contents/SharedSupport/${file}" ]] || fail "shared data contains build-machine state ${file}"
done
pass "ships precompiled shared data without build-machine installation state"

TOOLS=(rime_deployer rime_dict_manager rime-install scribe-refresh-input-menu)
for tool in "${TOOLS[@]}"; do
  [[ -x "${APP}/Contents/MacOS/${tool}" ]] || fail "${tool} is not next to Scribe"
done
for tool in rime_deployer rime_dict_manager; do
  for arch in arm64 x86_64; do
    lipo "${APP}/Contents/MacOS/${tool}" -verify_arch "${arch}" || fail "${tool} lacks ${arch}"
  done
done
pass "ships ${TOOLS[*]} next to Scribe, universal"

SETTINGS="${APP}/Contents/Helpers/ScribeSettings.app"
[[ -x "${SETTINGS}/Contents/MacOS/ScribeSettings" ]] || fail "Scribe Settings is not in Contents/Helpers"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${SETTINGS}/Contents/Info.plist")" == "${BUNDLE_ID}.Settings" ]] ||
  fail "unexpected settings bundle identifier"
for arch in arm64 x86_64; do
  lipo "${SETTINGS}/Contents/MacOS/ScribeSettings" -verify_arch "${arch}" || fail "Scribe Settings lacks ${arch}"
done
[[ ! -e "${SETTINGS}/Contents/Frameworks/librime.1.dylib" ]] || fail "Scribe Settings carries a second librime"
pass "ships Scribe Settings in Contents/Helpers, universal, using Scribe.app's librime"

# Software updates (docs/decisions/0011-releases-and-updates.md).
SPARKLE="${APP}/Contents/Frameworks/Sparkle.framework"
[[ -f "${SPARKLE}/Versions/B/Sparkle" ]] || fail "Sparkle.framework is not embedded"
[[ ! -e "${SPARKLE}/Versions/B/XPCServices" ]] || fail "Sparkle.framework still has its XPC services"
sparkle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${SPARKLE}/Resources/Info.plist")"
app_info() {
  /usr/libexec/PlistBuddy -c "Print :$1" "${APP}/Contents/Info.plist" 2>/dev/null || true
}
for key in SURequireSignedFeed SUVerifyUpdateBeforeExtraction SUEnableAutomaticChecks; do
  [[ "$(app_info "${key}")" == true ]] || fail "${key} is not true"
done
[[ "$(app_info SUAllowsAutomaticUpdates)" == false ]] || fail "SUAllowsAutomaticUpdates is not false"
feed="$(app_info SUFeedURL)"
feed_key="$(app_info SUPublicEDKey)"
if [[ -n "${feed}" || -n "${feed_key}" ]]; then
  [[ -n "${feed}" && -n "${feed_key}" ]] || fail "SUFeedURL and SUPublicEDKey must both be set, or neither"
  [[ "${feed}" == https://* ]] || fail "SUFeedURL ${feed} is not https"
  [[ "$(base64 -D <<< "${feed_key}" 2>/dev/null | wc -c | tr -d ' ')" == 32 ]] || fail "SUPublicEDKey is not a 32-byte key"
  feed_status="checks for updates at ${feed}"
else
  feed_status="no update feed (updates off)"
fi
if [[ -n "${EXPECT_FEED}" && "${feed}" != "${EXPECT_FEED}" ]]; then
  fail "SUFeedURL is ${feed:-absent}, expected ${EXPECT_FEED}"
fi
pass "embeds Sparkle ${sparkle_version} without its XPC services; ${feed_status}"

codesign --verify --strict --deep "${APP}" || fail "Scribe.app signature does not verify"
CODE=("${APP}" "${APP}/Contents/Frameworks/librime.1.dylib")
for plugin in "${PLUGINS[@]}"; do
  CODE+=("${APP}/Contents/Frameworks/rime-plugins/librime-${plugin}.dylib")
done
for tool in "${TOOLS[@]}"; do
  CODE+=("${APP}/Contents/MacOS/${tool}")
done
# Sparkle, from the software update checks above.
CODE+=("${SPARKLE}" "${SPARKLE}/Versions/B/Autoupdate" "${SPARKLE}/Versions/B/Updater.app")
CODE+=("${SETTINGS}")
codesign --verify --deep --strict "${SETTINGS}" || fail "Scribe Settings signature does not verify"
for code in "${CODE[@]}"; do
  codesign --verify --strict "${code}" || fail "${code##*/} signature does not verify"
  details="$(codesign --display --verbose=2 "${code}" 2>&1)"
  grep -q "flags=.*runtime" <<< "${details}" || fail "${code##*/} lacks the hardened runtime"
  if [[ "${SIGNED}" == 1 ]]; then
    grep -qF "TeamIdentifier=${TEAM_ID}" <<< "${details}" || fail "${code##*/} is not signed by team ${TEAM_ID}"
    grep -qF "Authority=Developer ID Application:" <<< "${details}" || fail "${code##*/} is not signed with Developer ID Application"
    grep -q "Timestamp=" <<< "${details}" || fail "${code##*/} has no secure timestamp"
  fi
done
for code in "${APP}" "${APP}/Contents/MacOS/rime_deployer" "${APP}/Contents/MacOS/rime_dict_manager" "${SETTINGS}"; do
  entitlements="$(codesign --display --entitlements - --xml "${code}" 2>/dev/null)"
  grep -q "com.apple.security.cs.disable-library-validation" <<< "${entitlements}" ||
    fail "${code##*/} lacks the disable-library-validation entitlement"
  ! grep -q "com.apple.security.get-task-allow" <<< "${entitlements}" ||
    fail "${code##*/} carries get-task-allow"
done
if [[ "${SIGNED}" == 1 ]]; then
  pass "Scribe.app, librime, its plugins, the tools and Scribe Settings signed by ${TEAM_ID} with hardened runtime and timestamp"
else
  pass "Scribe.app, librime, its plugins, the tools and Scribe Settings signed ad hoc with hardened runtime"
fi

self_test="$("${APP}/Contents/MacOS/Scribe" --self-test 2>/dev/null)" || fail "self-test failed: ${self_test}"
for plugin in "${PLUGINS[@]}"; do
  grep -qx "plugin ${plugin}: loaded" <<< "${self_test}" || fail "plugin ${plugin} does not load: ${self_test}"
done
pass "Scribe.app launches, loads librime $(head -1 <<< "${self_test}" | cut -d' ' -f2) and its plugins"

# Output from either tool means it got past loading librime. Neither command
# touches any files.
usage="$("${APP}/Contents/MacOS/rime_dict_manager" 2>&1)" || fail "rime_dict_manager does not run: ${usage}"
grep -q -- "--list" <<< "${usage}" || fail "rime_dict_manager does not run: ${usage}"
usage="$("${APP}/Contents/MacOS/rime_deployer" --check-release 2>&1 || true)"
[[ "${usage}" == "invalid arguments." ]] || fail "rime_deployer does not run: ${usage}"
bash -n "${APP}/Contents/MacOS/rime-install" || fail "rime-install is not a valid shell script"
bash -n "${APP}/Contents/MacOS/scribe-refresh-input-menu" || fail "input-menu refresh helper is not a valid shell script"
pass "rime_deployer and rime_dict_manager load librime; rime-install parses"

settings_test="$("${SETTINGS}/Contents/MacOS/ScribeSettings" --self-test 2>/dev/null)" ||
  fail "Scribe Settings does not launch: ${settings_test}"
grep -q '^librime ' <<< "${settings_test}" || fail "Scribe Settings does not load librime: ${settings_test}"
grep -qF "shared data: ${APP}/Contents/SharedSupport" <<< "${settings_test}" ||
  fail "Scribe Settings does not use Scribe.app's shared data: ${settings_test}"
pass "Scribe Settings launches with Scribe.app's librime and shared data"

if refresh_log="$("${APP}/Contents/MacOS/Scribe" --refresh-input-menu 2>&1)"; then
  fail "a package staging copy must not refresh the user's live input menu"
fi
grep -q 'must run as the user from an installed Scribe.app' <<< "${refresh_log}" ||
  fail "unexpected staging refresh refusal: ${refresh_log}"
pass "staging copies cannot modify the live input-source list"

mkdir "${WORK}/replay-user"
replay_log="$("${APP}/Contents/MacOS/Scribe" --replay \
  "${ROOT}/Tests/Fixtures/prebuilt/luna-pinyin.replay" "${WORK}/replay-user" 2>&1)" ||
  fail "packaged prebuilt schema cannot compose and commit: $(tail -10 <<< "${replay_log}")"
pass "packaged luna_pinyin composes and commits with a fresh user directory"

# Keep testing the public --build command on a separate copy. The installed
# app must remain sealed; postinstall no longer runs this command in it.
ditto "${APP}/Contents/SharedSupport" "${WORK}/prebuild"
rm -rf "${WORK}/prebuild/build"
build_log="$(cd "${WORK}/prebuild" && "${APP}/Contents/MacOS/Scribe" --build 2>&1)" ||
  fail "--build cannot prebuild the shared data: $(tail -5 <<< "${build_log}")"
for file in default.yaml luna_pinyin.prism.bin luna_pinyin.table.bin quick5.table.bin; do
  [[ -f "${WORK}/prebuild/build/${file}" ]] || fail "--build did not prebuild ${file}"
done
codesign --verify --strict --deep "${APP}" || fail "validation changed Scribe.app's sealed resources"
pass "--build prebuilds shared data outside the sealed app"

echo "All checks passed for ${PACKAGE##*/}"
