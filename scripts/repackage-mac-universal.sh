#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_DMG="${1:-}"
OVERLAY_DIR="${2:-}"
OUT_DMG="${3:-}"

if [[ -z "${UPSTREAM_DMG}" || -z "${OUT_DMG}" ]]; then
  echo "Usage: $0 <upstream-dmg> <overlay-dir> <out-dmg>" >&2
  exit 2
fi

if [[ ! -f "${UPSTREAM_DMG}" ]]; then
  echo "Upstream DMG not found: ${UPSTREAM_DMG}" >&2
  exit 2
fi

if [[ -n "${OVERLAY_DIR}" && ! -d "${OVERLAY_DIR}" ]]; then
  echo "Overlay dir not found: ${OVERLAY_DIR}" >&2
  exit 2
fi

for cmd in hdiutil ditto find; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "'${cmd}' is required but was not found in PATH." >&2
    exit 2
  fi
done

OUT_DIR="$(dirname "${OUT_DMG}")"
mkdir -p "${OUT_DIR}"
OUT_DMG_ABS="$(cd "${OUT_DIR}" && pwd)/$(basename "${OUT_DMG}")"

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORK_DIR="$(mktemp -d)"
RW_DMG="${WORK_DIR}/upstream_rw.dmg"
MOUNT_DIR="${WORK_DIR}/mount"
ATTACHED_DEVICE=""
STAGE_APP=""

detach_image() {
  local target="${1:-}"
  if [[ -z "${target}" ]]; then
    return 0
  fi
  hdiutil detach "${target}" -quiet || hdiutil detach "${target}" -force -quiet || true
}

cleanup() {
  detach_image "${MOUNT_DIR}"
  detach_image "${ATTACHED_DEVICE}"
  rm -rf "${WORK_DIR}" || true
}
trap cleanup EXIT

mkdir -p "${MOUNT_DIR}"

hdiutil convert "${UPSTREAM_DMG}" -format UDRW -o "${RW_DMG}" >/dev/null
if [[ ! -f "${RW_DMG}" && -f "${RW_DMG}.dmg" ]]; then
  RW_DMG="${RW_DMG}.dmg"
fi
if [[ ! -f "${RW_DMG}" ]]; then
  echo "Failed to create read-write DMG copy from ${UPSTREAM_DMG}" >&2
  exit 2
fi

ATTACH_LOG="${WORK_DIR}/attach.log"
hdiutil attach -readwrite -nobrowse -mountpoint "${MOUNT_DIR}" "${RW_DMG}" >"${ATTACH_LOG}"
ATTACHED_DEVICE="$(awk '/Apple_APFS/ {print $1; exit}' "${ATTACH_LOG}")"
if [[ -z "${ATTACHED_DEVICE}" ]]; then
  ATTACHED_DEVICE="$(awk 'NR==1 {print $1}' "${ATTACH_LOG}")"
fi
if [[ -z "${ATTACHED_DEVICE}" ]]; then
  echo "Unable to determine attached device for ${UPSTREAM_DMG}" >&2
  exit 2
fi

SOURCE_APP="$(find "${MOUNT_DIR}" -maxdepth 1 -type d -name '*.app' | head -n1 || true)"
if [[ -z "${SOURCE_APP}" ]]; then
  echo "No .app bundle found inside mounted DMG." >&2
  exit 2
fi
APP_NAME="$(basename "${SOURCE_APP}")"
STAGE_APP="${WORK_DIR}/${APP_NAME}"

# Work on a local app copy so codesign runs on a normal writable filesystem.
ditto "${SOURCE_APP}" "${STAGE_APP}"

if [[ ! -d "${STAGE_APP}/Contents/Resources" ]]; then
  echo "Missing app resources folder: ${STAGE_APP}/Contents/Resources" >&2
  exit 2
fi

if [[ -n "${OVERLAY_DIR}" && -d "${OVERLAY_DIR}/resources" ]]; then
  cp -a "${OVERLAY_DIR}/resources/." "${STAGE_APP}/Contents/Resources/"
fi

# Apply the same curated printer/filament/process pruning as Windows.
bash "${ROOT_DIR}/scripts/prune-portable-profiles.sh" "${STAGE_APP}/Contents"

mkdir -p "${STAGE_APP}/Contents/Resources/orca-config"
cat > "${STAGE_APP}/Contents/Resources/orca-config/README.txt" <<'TXT'
This OrcaSlicer macOS DMG was repackaged by MeharPro/orca-config.

Injected from:
  configs/portable-overlay/

Profiles were curated via:
  scripts/prune-portable-profiles.sh
TXT

if command -v codesign >/dev/null 2>&1; then
  # Re-sign because changing bundle resources invalidates the upstream signature.
  codesign --force --deep --sign - --timestamp=none "${STAGE_APP}"
fi

# Put the signed app back into the writable DMG.
rm -rf "${SOURCE_APP}"
ditto "${STAGE_APP}" "${SOURCE_APP}"

sync || true
detach_image "${MOUNT_DIR}"
detach_image "${ATTACHED_DEVICE}"
ATTACHED_DEVICE=""

rm -f "${OUT_DMG_ABS}"
hdiutil convert "${RW_DMG}" -format UDZO -o "${OUT_DMG_ABS}" >/dev/null
