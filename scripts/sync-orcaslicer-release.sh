#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${ROOT_DIR}/releases"
STATE_FILE="${STATE_DIR}/latest_tag.txt"
JSON_FILE="${STATE_DIR}/latest.json"
MD_FILE="${STATE_DIR}/LATEST_RELEASE.md"

OWNER_REPO="OrcaSlicer/OrcaSlicer"
API_URL="https://api.github.com/repos/${OWNER_REPO}/releases/latest"

mkdir -p "${STATE_DIR}"

AUTH_HEADER=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

LATEST_JSON="$(curl -fsSL -H "Accept: application/vnd.github+json" "${AUTH_HEADER[@]}" "${API_URL}")"

LATEST_TAG="$(python3 - <<'PY'
import json, sys
try:
    data = json.loads(sys.stdin.read())
except json.JSONDecodeError as exc:
    print(f"Failed to parse JSON: {exc}", file=sys.stderr)
    sys.exit(2)

tag = (data.get("tag_name") or "").strip()
print(tag)
PY
<<<"${LATEST_JSON}")"

if [[ -z "${LATEST_TAG}" ]]; then
  echo "Could not determine latest tag from ${API_URL}" >&2
  exit 2
fi

CURRENT_TAG=""
if [[ -f "${STATE_FILE}" ]]; then
  CURRENT_TAG="$(cat "${STATE_FILE}")"
fi

if [[ "${LATEST_TAG}" == "${CURRENT_TAG}" ]]; then
  echo "No new release. Latest tag remains ${LATEST_TAG}."
  exit 0
fi

python3 - "${JSON_FILE}" "${MD_FILE}" "${STATE_FILE}" <<'PY'
import json
import sys
from pathlib import Path

json_file, md_file, state_file = sys.argv[1:4]

data = json.loads(sys.stdin.read())

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
PY
<<<"${LATEST_JSON}"

echo "Updated release files for ${LATEST_TAG}."
