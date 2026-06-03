#!/usr/bin/env bash

set -euo pipefail

# Build an unsigned iPhoneOS .app and package it as an .ipa for TrollStore.
#
# Usage:
#   bash Scripts/build-trollstore-ipa.sh
#
# Optional environment variables:
#   PROJECT="Simpanin.xcodeproj"
#   SCHEME="Simpanin"
#   CONFIGURATION="Release"
#   APP_NAME="Simpanin"
#   OUTPUT_NAME="Simpanin-TrollStore.ipa"

PROJECT="${PROJECT:-Simpanin.xcodeproj}"
SCHEME="${SCHEME:-Simpanin}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-Simpanin}"
OUTPUT_NAME="${OUTPUT_NAME:-${APP_NAME}-TrollStore.ipa}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/trollstore"
DERIVED_DATA_PATH="${BUILD_DIR}/DerivedData"
PRODUCTS_DIR="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}-iphoneos"
APP_PATH="${PRODUCTS_DIR}/${APP_NAME}.app"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
IPA_PATH="${ROOT_DIR}/${OUTPUT_NAME}"

echo "==> Project: ${PROJECT}"
echo "==> Scheme: ${SCHEME}"
echo "==> Configuration: ${CONFIGURATION}"
echo "==> Output: ${IPA_PATH}"

cd "${ROOT_DIR}"

echo "==> Cleaning old build artifacts..."
rm -rf "${BUILD_DIR}" "${IPA_PATH}"
mkdir -p "${BUILD_DIR}"

echo "==> Building unsigned iPhoneOS app..."
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -sdk iphoneos \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: app not found: ${APP_PATH}" >&2
  echo "Try checking APP_NAME, SCHEME, or build output above." >&2
  exit 1
fi

sign_binary_with_ldid() {
  local binary_path="$1"

  if [[ -f "${binary_path}" ]]; then
    echo "    ldid -S ${binary_path}"
    ldid -S "${binary_path}"
  else
    echo "    skip missing binary: ${binary_path}"
  fi
}

echo "==> Applying ldid pseudo-signing if ldid is installed..."
if command -v ldid >/dev/null 2>&1; then
  MAIN_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${APP_PATH}/Info.plist")"
  sign_binary_with_ldid "${APP_PATH}/${MAIN_EXECUTABLE}"

  if [[ -d "${APP_PATH}/Frameworks" ]]; then
    while IFS= read -r -d '' framework; do
      framework_name="$(basename "${framework}" .framework)"
      sign_binary_with_ldid "${framework}/${framework_name}"
    done < <(find "${APP_PATH}/Frameworks" -type d -name "*.framework" -print0)
  fi

  if [[ -d "${APP_PATH}/PlugIns" ]]; then
    while IFS= read -r -d '' appex; do
      appex_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${appex}/Info.plist")"
      sign_binary_with_ldid "${appex}/${appex_executable}"

      if [[ -d "${appex}/Frameworks" ]]; then
        while IFS= read -r -d '' framework; do
          framework_name="$(basename "${framework}" .framework)"
          sign_binary_with_ldid "${framework}/${framework_name}"
        done < <(find "${appex}/Frameworks" -type d -name "*.framework" -print0)
      fi
    done < <(find "${APP_PATH}/PlugIns" -type d -name "*.appex" -print0)
  fi
else
  echo "    ldid not found; skipping pseudo-signing."
  echo "    If TrollStore install fails, install it with: brew install ldid"
fi

echo "==> Packaging IPA..."
rm -rf "${PAYLOAD_DIR}"
mkdir -p "${PAYLOAD_DIR}"
cp -R "${APP_PATH}" "${PAYLOAD_DIR}/"

(
  cd "${BUILD_DIR}"
  /usr/bin/zip -qry "${IPA_PATH}" Payload
)

echo "==> Done."
echo "IPA exported at: ${IPA_PATH}"
