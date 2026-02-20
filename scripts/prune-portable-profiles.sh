#!/usr/bin/env bash
set -euo pipefail

EXTRACT_DIR="${1:-}"
if [[ -z "${EXTRACT_DIR}" ]]; then
  echo "Usage: $0 <extracted-portable-root>" >&2
  exit 2
fi

PROFILES_DIR=""
if [[ -d "${EXTRACT_DIR}/resources/profiles" ]]; then
  PROFILES_DIR="${EXTRACT_DIR}/resources/profiles"
elif [[ -d "${EXTRACT_DIR}/Resources/profiles" ]]; then
  PROFILES_DIR="${EXTRACT_DIR}/Resources/profiles"
fi

if [[ -z "${PROFILES_DIR}" ]]; then
  echo "Profiles directory not found under ${EXTRACT_DIR}/resources/profiles or ${EXTRACT_DIR}/Resources/profiles" >&2
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

DREMEL_JSON="${PROFILES_DIR}/Dremel.json"
FLASHFORGE_JSON="${PROFILES_DIR}/Flashforge.json"
CUSTOM_JSON="${PROFILES_DIR}/Custom.json"
ORCA_FILAMENT_LIBRARY_JSON="${PROFILES_DIR}/OrcaFilamentLibrary.json"

for required in "${DREMEL_JSON}" "${FLASHFORGE_JSON}" "${CUSTOM_JSON}" "${ORCA_FILAMENT_LIBRARY_JSON}"; do
  if [[ ! -f "${required}" ]]; then
    echo "Required profile bundle missing: ${required}" >&2
    exit 2
  fi
done

# Keep all upstream files on disk for runtime safety. Only rewrite manifests so
# OrcaSlicer exposes the curated profile set in the UI.
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
    .name == "Dremel Generic PLA @3D45 all" or
    .name == "Flashforge Generic PLA" or
    .name == "Flashforge Generic ABS"
  )) |
  .filament_list = (
    .filament_list + [
      {"name":"Flashforge Generic PLA","sub_path":"filament/Flashforge Generic PLA.json"},
      {"name":"Flashforge Generic ABS","sub_path":"filament/Flashforge Generic ABS.json"}
    ]
    | unique_by(.name)
  )
'

rewrite_json "${FLASHFORGE_JSON}" '
  .machine_model_list |= map(select(.name == "Flashforge Adventurer 5M Pro")) |
  .machine_list |= map(select(
    .name == "fdm_machine_common" or
    .name == "fdm_flashforge_common" or
    .name == "fdm_adventurer5m_common" or
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
    .name == "0.20mm Standard @Flashforge AD5M Pro 0.4 Nozzle" or
    .name == "0.30mm Standard @Flashforge AD5M Pro 0.6 Nozzle" or
    .name == "0.40mm Standard @Flashforge AD5M Pro 0.8 Nozzle"
  )) |
  .filament_list |= map(select(
    .name == "fdm_filament_common" or
    .name == "fdm_filament_abs" or
    .name == "fdm_filament_pla" or
    .name == "Flashforge Generic PLA" or
    .name == "Flashforge Generic ABS"
  ))
'

rewrite_json "${CUSTOM_JSON}" '
  .machine_model_list = [] |
  .machine_list = [] |
  .process_list = [] |
  .filament_list = []
'

rewrite_json "${ORCA_FILAMENT_LIBRARY_JSON}" '
  .filament_list = []
'

# Align defaults with the curated filament choices.
rewrite_json "${PROFILES_DIR}/Dremel/machine/Dremel 3D45.json" '
  .default_materials = "Dremel Generic PLA @3D45 all;Flashforge Generic PLA;Flashforge Generic ABS"
'
rewrite_json "${PROFILES_DIR}/Dremel/machine/Dremel 3D45 0.4 nozzle.json" '
  .default_filament_profile = [
    "Dremel Generic PLA @3D45 all",
    "Flashforge Generic PLA",
    "Flashforge Generic ABS"
  ] |
  .default_print_profile = "Dremel 3D45 Optimized Quality"
'
rewrite_json "${PROFILES_DIR}/Flashforge/machine/Flashforge Adventurer 5M Pro.json" '
  .default_materials = "Flashforge Generic PLA;Flashforge Generic ABS"
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

# Make Flashforge Generic PLA/ABS selectable on the Dremel profile as requested.
for filament in \
  "${PROFILES_DIR}/Flashforge/filament/Flashforge Generic PLA.json" \
  "${PROFILES_DIR}/Flashforge/filament/Flashforge Generic ABS.json"; do
  if [[ -f "${filament}" ]]; then
    rewrite_json "${filament}" '
      .compatible_printers = ((.compatible_printers // []) + ["Dremel 3D45", "Dremel 3D45 0.4 nozzle"] | unique)
    '
  fi
done

# Hide all other vendors without deleting any files that Orca may rely on.
for root in "${PROFILES_DIR}"/*.json; do
  base="$(basename "${root}")"
  case "${base}" in
    Dremel.json|Flashforge.json|Custom.json|OrcaFilamentLibrary.json|blacklist.json)
      continue
      ;;
  esac

  rewrite_json "${root}" '
    if has("machine_model_list") then .machine_model_list = [] else . end |
    if has("machine_list") then .machine_list = [] else . end |
    if has("process_list") then .process_list = [] else . end |
    if has("filament_list") then .filament_list = [] else . end
  '
done
