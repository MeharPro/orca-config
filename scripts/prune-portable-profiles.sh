#!/usr/bin/env bash
set -euo pipefail

EXTRACT_DIR="${1:-}"
if [[ -z "${EXTRACT_DIR}" ]]; then
  echo "Usage: $0 <extracted-portable-root>" >&2
  exit 2
fi

PROFILES_DIR="${EXTRACT_DIR}/resources/profiles"
if [[ ! -d "${PROFILES_DIR}" ]]; then
  echo "Profiles directory not found: ${PROFILES_DIR}" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "'jq' is required but was not found in PATH." >&2
  exit 2
fi

rewrite_json() {
  local file="$1"
  local filter="$2"
  local tmp
  tmp="$(mktemp)"
  jq "${filter}" "${file}" >"${tmp}"
  mv "${tmp}" "${file}"
}

resolve_referenced_asset() {
  local vendor_dir="$1"
  local ref="$2"
  local exact="${vendor_dir}/${ref}"
  local found

  if [[ -f "${exact}" ]]; then
    echo "${ref}"
    return 0
  fi

  found="$(find "${vendor_dir}" -type f -iname "$(basename "${ref}")" -print -quit)"
  if [[ -n "${found}" ]]; then
    echo "${found#${vendor_dir}/}"
  fi
}

# Keep only vendor bundles that will be exposed in the repackaged distribution.
for path in "${PROFILES_DIR}"/*; do
  base="$(basename "${path}")"
  case "${base}" in
    Dremel|Dremel.json|Flashforge|Flashforge.json|Custom.json|OrcaFilamentLibrary.json|blacklist.json)
      ;;
    *)
      rm -rf "${path}"
      ;;
  esac
done

DREMEL_JSON="${PROFILES_DIR}/Dremel.json"
FLASHFORGE_JSON="${PROFILES_DIR}/Flashforge.json"
CUSTOM_JSON="${PROFILES_DIR}/Custom.json"
ORCA_FILAMENT_LIBRARY_JSON="${PROFILES_DIR}/OrcaFilamentLibrary.json"

rewrite_json "${DREMEL_JSON}" '
  .machine_model_list |= map(select(.name == "Dremel 3D45")) |
  .machine_list |= map(select(
    .name == "fdm_machine_common" or
    .name == "fdm_dremel_common" or
    .name == "Dremel 3D45 0.4 nozzle"
  )) |
  .process_list |= map(select(
    .name == "fdm_process_common" or
    .name == "fdm_process_dremel_common" or
    .name == "Dremel 3D45 Optimized Quality"
  )) |
  .filament_list |= map(select(
    .name == "fdm_filament_common" or
    .name == "fdm_filament_pla" or
    .name == "Dremel Generic PLA" or
    .name == "Dremel Generic PLA @3D45 all"
  ))
'

rewrite_json "${FLASHFORGE_JSON}" '
  .machine_model_list |= map(select(.name == "Flashforge Adventurer 5M Pro")) |
  .machine_list |= map(select(
    .name == "fdm_machine_common" or
    .name == "fdm_flashforge_common" or
    .name == "fdm_adventurer5m_common" or
    .name == "Flashforge Adventurer 5M Pro 0.25 Nozzle" or
    .name == "Flashforge Adventurer 5M Pro 0.4 Nozzle" or
    .name == "Flashforge Adventurer 5M Pro 0.6 Nozzle" or
    .name == "Flashforge Adventurer 5M Pro 0.8 Nozzle"
  )) |
  .process_list |= map(select(
    .name == "fdm_process_common" or
    .name == "fdm_process_flashforge_common" or
    .name == "fdm_process_flashforge_0.20" or
    .name == "fdm_process_flashforge_0.30" or
    .name == "fdm_process_flashforge_0.40" or
    (.name | test("AD5M Pro"))
  )) |
  .filament_list |= map(select(
    .name == "fdm_filament_common" or
    .name == "fdm_filament_abs" or
    .name == "fdm_filament_pla" or
    .name == "Flashforge Generic PLA" or
    .name == "Flashforge Generic ABS" or
    .name == "Flashforge PLA @FF AD5M 0.25 Nozzle" or
    .name == "Flashforge ABS @FF AD5M 0.25 Nozzle"
  ))
'

# Keep expected core bundle files present while exposing no extra profiles.
rewrite_json "${CUSTOM_JSON}" '
  .machine_model_list = [] |
  .machine_list = [] |
  .process_list = [] |
  .filament_list = []
'

rewrite_json "${ORCA_FILAMENT_LIBRARY_JSON}" '
  .filament_list = []
'

# Align defaults with the kept filament list.
rewrite_json "${PROFILES_DIR}/Dremel/machine/Dremel 3D45.json" '
  .default_materials = "Dremel Generic PLA @3D45 all"
'
rewrite_json "${PROFILES_DIR}/Dremel/machine/Dremel 3D45 0.4 nozzle.json" '
  .default_filament_profile = ["Dremel Generic PLA @3D45 all"] |
  .default_print_profile = "Dremel 3D45 Optimized Quality"
'
rewrite_json "${PROFILES_DIR}/Flashforge/machine/Flashforge Adventurer 5M Pro.json" '
  .default_materials = "Flashforge Generic PLA;Flashforge Generic ABS;Flashforge PLA @FF AD5M 0.25 Nozzle"
'
rewrite_json "${PROFILES_DIR}/Flashforge/machine/Flashforge Adventurer 5M Pro 0.25 Nozzle.json" '
  .default_filament_profile = ["Flashforge PLA @FF AD5M 0.25 Nozzle"]
'
rewrite_json "${PROFILES_DIR}/Flashforge/machine/Flashforge Adventurer 5M Pro 0.4 Nozzle.json" '
  .default_filament_profile = ["Flashforge Generic PLA"]
'
rewrite_json "${PROFILES_DIR}/Flashforge/machine/Flashforge Adventurer 5M Pro 0.6 Nozzle.json" '
  .default_filament_profile = ["Flashforge Generic PLA"]
'
rewrite_json "${PROFILES_DIR}/Flashforge/machine/Flashforge Adventurer 5M Pro 0.8 Nozzle.json" '
  .default_filament_profile = ["Flashforge Generic PLA"]
'

collect_keep_paths() {
  local vendor_json="$1"
  local vendor_dir="$2"
  local out_file="$3"

  : >"${out_file}"
  jq -r '
    [
      (.machine_model_list[]?.sub_path // empty),
      (.machine_list[]?.sub_path // empty),
      (.process_list[]?.sub_path // empty),
      (.filament_list[]?.sub_path // empty)
    ] | .[]
  ' "${vendor_json}" >>"${out_file}"

  while IFS= read -r model_sub_path; do
    local model_file
    local resolved
    model_file="${vendor_dir}/${model_sub_path}"
    if [[ -f "${model_file}" ]]; then
      while IFS= read -r ref; do
        resolved="$(resolve_referenced_asset "${vendor_dir}" "${ref}" || true)"
        if [[ -n "${resolved}" ]]; then
          echo "${resolved}" >>"${out_file}"
        fi
      done < <(jq -r '.bed_model, .bed_texture, .hotend_model | select(type == "string" and length > 0)' "${model_file}")
    fi
  done < <(jq -r '.machine_model_list[]?.sub_path // empty' "${vendor_json}")

  # Keep vendor-level assets (STL/PNG/textures) used by machine models.
  find "${vendor_dir}" -maxdepth 1 -type f ! -name '*.json' -exec basename {} \; >>"${out_file}"
  sort -u "${out_file}" -o "${out_file}"
}

prune_vendor_files() {
  local vendor_dir="$1"
  local keep_file="$2"
  local rel

  while IFS= read -r file; do
    rel="${file#${vendor_dir}/}"
    if ! grep -Fxq "${rel}" "${keep_file}"; then
      rm -f "${file}"
    fi
  done < <(find "${vendor_dir}" -type f)

  find "${vendor_dir}" -type d -empty -delete
}

dremel_keep="$(mktemp)"
flashforge_keep="$(mktemp)"
trap 'rm -f "${dremel_keep}" "${flashforge_keep}"' EXIT

collect_keep_paths "${DREMEL_JSON}" "${PROFILES_DIR}/Dremel" "${dremel_keep}"
collect_keep_paths "${FLASHFORGE_JSON}" "${PROFILES_DIR}/Flashforge" "${flashforge_keep}"
prune_vendor_files "${PROFILES_DIR}/Dremel" "${dremel_keep}"
prune_vendor_files "${PROFILES_DIR}/Flashforge" "${flashforge_keep}"
