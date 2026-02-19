#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${ROOT_DIR}/releases"
STATE_FILE="${STATE_DIR}/latest_tag.txt"
JSON_FILE="${STATE_DIR}/latest.json"
MD_FILE="${STATE_DIR}/LATEST_RELEASE.md"
WIN_PORTABLE_JSON_FILE="${STATE_DIR}/windows_portable.json"
WIN_PORTABLE_MD_FILE="${STATE_DIR}/WINDOWS_PORTABLE.md"
MAC_UNIVERSAL_JSON_FILE="${STATE_DIR}/mac_universal.json"
MAC_UNIVERSAL_MD_FILE="${STATE_DIR}/MAC_UNIVERSAL.md"

OWNER_REPO="OrcaSlicer/OrcaSlicer"
API_URL="https://api.github.com/repos/${OWNER_REPO}/releases/latest"
MIRROR_REPO="${MIRROR_REPO:-MeharPro/orca-config}"

mkdir -p "${STATE_DIR}"

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  LATEST_JSON="$(curl -fsSL -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GITHUB_TOKEN}" "${API_URL}")"
else
  LATEST_JSON="$(curl -fsSL -H "Accept: application/vnd.github+json" "${API_URL}")"
fi

LATEST_TAG="$(python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    print(f"Failed to parse JSON: {exc}", file=sys.stderr)
    sys.exit(2)

tag = (data.get("tag_name") or "").strip()
print(tag)
' <<<"${LATEST_JSON}")"

if [[ -z "${LATEST_TAG}" ]]; then
  echo "Could not determine latest tag from ${API_URL}" >&2
  exit 2
fi

CURRENT_TAG=""
if [[ -f "${STATE_FILE}" ]]; then
  CURRENT_TAG="$(cat "${STATE_FILE}")"
fi

TAG_CHANGED="0"
if [[ "${LATEST_TAG}" != "${CURRENT_TAG}" ]]; then
  TAG_CHANGED="1"
fi

python3 -c '
import json
import sys
from pathlib import Path

json_file, md_file, state_file, win_json_file, win_md_file, mac_json_file, mac_md_file, mirror_repo = sys.argv[1:9]

data = json.load(sys.stdin)

assets_raw = data.get("assets") or []
assets = []
for a in assets_raw:
    assets.append(
        {
            "id": a.get("id"),
            "name": a.get("name"),
            "size": a.get("size"),
            "content_type": a.get("content_type"),
            "browser_download_url": a.get("browser_download_url"),
            "updated_at": a.get("updated_at"),
        }
    )

subset = {
    "id": data.get("id"),
    "tag_name": data.get("tag_name"),
    "name": data.get("name"),
    "draft": data.get("draft"),
    "prerelease": data.get("prerelease"),
    "published_at": data.get("published_at"),
    "html_url": data.get("html_url"),
    "tarball_url": data.get("tarball_url"),
    "zipball_url": data.get("zipball_url"),
    "body": data.get("body"),
    "assets": assets,
}

Path(json_file).write_text(json.dumps(subset, indent=2) + "\n")

tag = (subset.get("tag_name") or "").strip()
name = (subset.get("name") or "").strip()
published = (subset.get("published_at") or "").strip()
url = (subset.get("html_url") or "").strip()
body = (subset.get("body") or "").rstrip()

md_lines = [
    "# OrcaSlicer Latest Release",
    "",
    f"- Tag: {tag}",
]
if name:
    md_lines.append(f"- Name: {name}")
if published:
    md_lines.append(f"- Published: {published}")
if url:
    md_lines.append(f"- URL: {url}")

md_lines.append("")
md_lines.append("## Notes")
md_lines.append("")
md_lines.append(body or "(No release notes provided.)")
md_lines.append("")

Path(md_file).write_text("\n".join(md_lines))
Path(state_file).write_text(tag + "\n")


def is_windows_portable(asset_name: str) -> bool:
    n = asset_name.lower()
    if "portable" not in n:
        return False
    if "win" not in n and "windows" not in n:
        return False
    if "linux" in n or "ubuntu" in n or "mac" in n or "osx" in n or "darwin" in n:
        return False
    if "installer" in n or "setup" in n:
        return False
    return True


def is_mac_universal(asset_name: str) -> bool:
    n = asset_name.lower()
    if "mac" not in n:
        return False
    if ".dmg" not in n:
        return False
    if "win" in n or "windows" in n or "linux" in n or "ubuntu" in n:
        return False
    return True


def score(asset_name: str) -> int:
    n = asset_name.lower()
    s = 0
    if "portable" in n:
        s += 50
    if "windows" in n or "win" in n:
        s += 40
    if "x64" in n or "amd64" in n or "win64" in n or "64" in n:
        s += 15
    if n.endswith(".zip"):
        s += 10
    if n.endswith(".7z"):
        s += 8
    if n.endswith(".exe"):
        s += 2
    return s


def score_mac(asset_name: str) -> int:
    n = asset_name.lower()
    s = 0
    if "mac" in n:
        s += 30
    if "universal" in n:
        s += 25
    if "arm" in n or "apple" in n:
        s += 10
    if "intel" in n or "x86_64" in n:
        s += 10
    if n.endswith(".dmg"):
        s += 20
    return s


def mirror_download_url(tag: str, asset_name: str) -> str:
    if not tag or not asset_name:
        return ""
    return f"https://github.com/{mirror_repo}/releases/download/{tag}/{asset_name}"


candidates = [a for a in assets if (a.get("name") and is_windows_portable(a["name"]))]

if not candidates:
    available = [a.get("name") for a in assets if a.get("name")]
    available_s = "\n".join(f"- {n}" for n in available) or "(no assets)"
    print(
        "Could not find a Windows portable asset in the upstream release. Available assets:\n"
        + available_s,
        file=sys.stderr,
    )
    sys.exit(3)

candidates.sort(
    key=lambda a: (
        score(a["name"]),
        int(a.get("size") or 0),
        a["name"].lower(),
    ),
    reverse=True,
)

selected = candidates[0]

win_doc = {
    "tag_name": tag,
    "upstream_release_url": url,
    "asset": selected,
}
Path(win_json_file).write_text(json.dumps(win_doc, indent=2) + "\n")

asset_name = selected.get("name") or ""
asset_url = selected.get("browser_download_url") or ""
asset_size = selected.get("size") or 0
mirror_url = mirror_download_url(tag, asset_name)

win_md_lines = [
    "# OrcaSlicer Windows Portable (Latest)",
    "",
    f"- Tag: {tag}",
]
if published:
    win_md_lines.append(f"- Published: {published}")
if url:
    win_md_lines.append(f"- Upstream Release: {url}")
if asset_name:
    win_md_lines.append(f"- Asset: {asset_name}")
if asset_size:
    win_md_lines.append(f"- Size (bytes): {asset_size}")
if asset_url:
    win_md_lines.append(f"- Upstream Download: {asset_url}")
if mirror_url:
    win_md_lines.append(f"- Mirror Download: {mirror_url}")
win_md_lines.append("")

Path(win_md_file).write_text("\n".join(win_md_lines))


mac_candidates = [a for a in assets if (a.get("name") and is_mac_universal(a["name"]))]

if mac_candidates:
    mac_candidates.sort(
        key=lambda a: (
            score_mac(a["name"]),
            int(a.get("size") or 0),
            a["name"].lower(),
        ),
        reverse=True,
    )
    mac_selected = mac_candidates[0]
    mac_doc = {
        "tag_name": tag,
        "upstream_release_url": url,
        "asset": mac_selected,
    }
    Path(mac_json_file).write_text(json.dumps(mac_doc, indent=2) + "\n")

    mac_name = mac_selected.get("name") or ""
    mac_url = mac_selected.get("browser_download_url") or ""
    mac_size = mac_selected.get("size") or 0
    mac_mirror_url = mirror_download_url(tag, mac_name)
    mac_md_lines = [
        "# OrcaSlicer Mac Universal DMG (Latest)",
        "",
        f"- Tag: {tag}",
    ]
    if published:
        mac_md_lines.append(f"- Published: {published}")
    if url:
        mac_md_lines.append(f"- Upstream Release: {url}")
    if mac_name:
        mac_md_lines.append(f"- Asset: {mac_name}")
    if mac_size:
        mac_md_lines.append(f"- Size (bytes): {mac_size}")
    if mac_url:
        mac_md_lines.append(f"- Upstream Download: {mac_url}")
    if mac_mirror_url:
        mac_md_lines.append(f"- Mirror Download: {mac_mirror_url}")
    mac_md_lines.append("")
    Path(mac_md_file).write_text("\n".join(mac_md_lines))
else:
    Path(mac_json_file).write_text(
        json.dumps(
            {
                "tag_name": tag,
                "upstream_release_url": url,
                "asset": None,
            },
            indent=2,
        )
        + "\n"
    )
    mac_md_lines = [
        "# OrcaSlicer Mac Universal DMG (Latest)",
        "",
        f"- Tag: {tag}",
        "- Asset: (No macOS DMG found in upstream latest release)",
        "",
    ]
    Path(mac_md_file).write_text("\n".join(mac_md_lines))
' "${JSON_FILE}" "${MD_FILE}" "${STATE_FILE}" "${WIN_PORTABLE_JSON_FILE}" "${WIN_PORTABLE_MD_FILE}" "${MAC_UNIVERSAL_JSON_FILE}" "${MAC_UNIVERSAL_MD_FILE}" "${MIRROR_REPO}" <<<"${LATEST_JSON}"

if [[ "${TAG_CHANGED}" == "1" ]]; then
  echo "New upstream release detected: ${CURRENT_TAG:-<none>} -> ${LATEST_TAG}"
else
  echo "No new upstream release. Latest tag remains ${LATEST_TAG}."
fi
