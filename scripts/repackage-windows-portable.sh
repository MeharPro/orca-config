#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_ARCHIVE="${1:-}"
OVERLAY_DIR="${2:-}"
OUT_ZIP="${3:-}"

if [[ -z "${UPSTREAM_ARCHIVE}" || -z "${OUT_ZIP}" ]]; then
  echo "Usage: $0 <upstream-zip-or-7z> <overlay-dir> <out-zip>" >&2
  exit 2
fi

if [[ ! -f "${UPSTREAM_ARCHIVE}" ]]; then
  echo "Upstream archive not found: ${UPSTREAM_ARCHIVE}" >&2
  exit 2
fi

if [[ -n "${OVERLAY_DIR}" && ! -d "${OVERLAY_DIR}" ]]; then
  echo "Overlay dir not found: ${OVERLAY_DIR}" >&2
  exit 2
fi

if ! command -v zip >/dev/null 2>&1; then
  echo "'zip' is required but was not found in PATH." >&2
  exit 2
fi

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

EXTRACT_DIR="${WORK_DIR}/extract"
mkdir -p "${EXTRACT_DIR}"

UPSTREAM_ARCHIVE_LC="$(printf '%s' "${UPSTREAM_ARCHIVE}" | tr '[:upper:]' '[:lower:]')"
case "${UPSTREAM_ARCHIVE_LC}" in
  *.zip)
    if ! command -v unzip >/dev/null 2>&1; then
      echo "'unzip' is required to extract .zip archives but was not found in PATH." >&2
      exit 2
    fi
    unzip -q "${UPSTREAM_ARCHIVE}" -d "${EXTRACT_DIR}"
    ;;
  *.7z)
    if ! command -v 7z >/dev/null 2>&1; then
      echo "'7z' is required to extract .7z archives but was not found in PATH." >&2
      exit 2
    fi
    7z x -y "-o${EXTRACT_DIR}" "${UPSTREAM_ARCHIVE}" >/dev/null
    ;;
  *)
    echo "Unsupported archive type: ${UPSTREAM_ARCHIVE}" >&2
    exit 2
    ;;
esac

# Overlay any files in OVERLAY_DIR onto the extracted portable distribution.
# The overlay dir should mirror the archive layout (e.g. resources/profiles/...).
if [[ -n "${OVERLAY_DIR}" ]]; then
  if find "${OVERLAY_DIR}" -type f -maxdepth 1 >/dev/null 2>&1; then
    : # no-op
  fi

  if [[ -n "$(find "${OVERLAY_DIR}" -mindepth 1 -print -quit 2>/dev/null || true)" ]]; then
    cp -a "${OVERLAY_DIR}/." "${EXTRACT_DIR}/"
    # Avoid leaking git placeholder files into the shipped archive.
    find "${EXTRACT_DIR}" -name ".gitkeep" -type f -delete || true
  fi
fi

# Add a small marker so it's obvious this archive was repackaged.
mkdir -p "${EXTRACT_DIR}/orca-config"
cat > "${EXTRACT_DIR}/orca-config/README.txt" <<'TXT'
This OrcaSlicer Portable archive was repackaged by MeharPro/orca-config.

The repackaging process overlays custom files from:
  configs/portable-overlay/

If you want to change what is injected into the portable zip, update those files
in the repo and rerun the workflow.
TXT

mkdir -p "$(dirname "${OUT_ZIP}")"
rm -f "${OUT_ZIP}"

(cd "${EXTRACT_DIR}" && zip -qr -9 "${OUT_ZIP}" .)
