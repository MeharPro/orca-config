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
  .machine_model_list = [
    {"name":"Dremel 3D45","sub_path":"machine/Dremel 3D45.json"}
  ] |
  .machine_list = [
    {"name":"fdm_machine_common","sub_path":"machine/fdm_machine_common.json"},
    {"name":"fdm_dremel_common","sub_path":"machine/fdm_dremel_common.json"},
    {"name":"Dremel 3D45 0.4 nozzle","sub_path":"machine/Dremel 3D45 0.4 nozzle.json"}
  ] |
  .process_list = [
    {"name":"fdm_process_common","sub_path":"process/fdm_process_common.json"},
    {"name":"fdm_process_dremel_common","sub_path":"process/fdm_process_dremel_common.json"},
    {"name":"Dremel 3D45 Optimized Quality","sub_path":"process/Dremel_3D45_Process_Optimized.json"}
  ] |
  .filament_list = [
    {"name":"fdm_filament_common","sub_path":"filament/fdm_filament_common.json"},
    {"name":"fdm_filament_pla","sub_path":"filament/fdm_filament_pla.json"},
    {"name":"Dremel Generic PLA","sub_path":"filament/Dremel Generic PLA.json"},
    {"name":"Dremel Generic PLA @3D45 all","sub_path":"filament/Dremel Generic PLA @3D45 all.json"},
    {"name":"Flashforge Generic PLA","sub_path":"filament/Flashforge Generic PLA.json"},
    {"name":"Flashforge Generic ABS","sub_path":"filament/Flashforge Generic ABS.json"}
  ]
'

rewrite_json "${FLASHFORGE_JSON}" '
  .machine_model_list = [
    {"name":"Flashforge Adventurer 5M Pro","sub_path":"machine/Flashforge Adventurer 5M Pro.json"}
  ] |
  .machine_list = [
    {"name":"fdm_machine_common","sub_path":"machine/fdm_machine_common.json"},
    {"name":"fdm_flashforge_common","sub_path":"machine/fdm_flashforge_common.json"},
    {"name":"fdm_adventurer5m_common","sub_path":"machine/fdm_adventurer5m_common.json"},
    {"name":"Flashforge Adventurer 5M Pro 0.4 Nozzle","sub_path":"machine/Flashforge Adventurer 5M Pro 0.4 Nozzle.json"},
    {"name":"Flashforge Adventurer 5M Pro 0.6 Nozzle","sub_path":"machine/Flashforge Adventurer 5M Pro 0.6 Nozzle.json"},
    {"name":"Flashforge Adventurer 5M Pro 0.8 Nozzle","sub_path":"machine/Flashforge Adventurer 5M Pro 0.8 Nozzle.json"}
  ] |
  .process_list = [
    {"name":"fdm_process_common","sub_path":"process/fdm_process_common.json"},
    {"name":"fdm_process_flashforge_common","sub_path":"process/fdm_process_flashforge_common.json"},
    {"name":"fdm_process_flashforge_0.20","sub_path":"process/fdm_process_flashforge_0.20.json"},
    {"name":"fdm_process_flashforge_0.30","sub_path":"process/fdm_process_flashforge_0.30.json"},
    {"name":"fdm_process_flashforge_0.40","sub_path":"process/fdm_process_flashforge_0.40.json"},
    {"name":"0.20mm Standard @Flashforge AD5M Pro 0.4 Nozzle","sub_path":"process/0.20mm Standard @Flashforge AD5M Pro 0.4 Nozzle.json"},
    {"name":"0.30mm Standard @Flashforge AD5M Pro 0.6 Nozzle","sub_path":"process/0.30mm Standard @Flashforge AD5M Pro 0.6 Nozzle.json"},
    {"name":"0.40mm Standard @Flashforge AD5M Pro 0.8 Nozzle","sub_path":"process/0.40mm Standard @Flashforge AD5M Pro 0.8 Nozzle.json"}
  ] |
  .filament_list = [
    {"name":"fdm_filament_common","sub_path":"filament/fdm_filament_common.json"},
    {"name":"fdm_filament_abs","sub_path":"filament/fdm_filament_abs.json"},
    {"name":"fdm_filament_pla","sub_path":"filament/fdm_filament_pla.json"},
    {"name":"Flashforge Generic PLA","sub_path":"filament/Flashforge Generic PLA.json"},
    {"name":"Flashforge Generic ABS","sub_path":"filament/Flashforge Generic ABS.json"}
  ]
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
  .default_materials = "Dremel Generic PLA @3D45 all;Flashforge Generic PLA;Flashforge Generic ABS" |
  .default_bed_type = "Cool Plate"
'
rewrite_json "${PROFILES_DIR}/Dremel/machine/Dremel 3D45 0.4 nozzle.json" '
  .default_filament_profile = [
    "Dremel Generic PLA @3D45 all",
    "Flashforge Generic PLA",
    "Flashforge Generic ABS"
  ] |
  .default_print_profile = "Dremel 3D45 Optimized Quality" |
  .default_bed_type = "Cool Plate"
'
rewrite_json "${PROFILES_DIR}/Flashforge/machine/Flashforge Adventurer 5M Pro.json" '
  .default_materials = "Flashforge Generic PLA;Flashforge Generic ABS" |
  .default_bed_type = "Textured PEI Plate"
'
rewrite_json "${PROFILES_DIR}/Flashforge/machine/Flashforge Adventurer 5M Pro 0.4 Nozzle.json" '
  .default_filament_profile = ["Flashforge Generic PLA"] |
  .default_bed_type = "Textured PEI Plate"
'
rewrite_json "${PROFILES_DIR}/Flashforge/machine/Flashforge Adventurer 5M Pro 0.6 Nozzle.json" '
  .default_filament_profile = ["Flashforge Generic PLA"] |
  .default_bed_type = "Textured PEI Plate"
'
rewrite_json "${PROFILES_DIR}/Flashforge/machine/Flashforge Adventurer 5M Pro 0.8 Nozzle.json" '
  .default_filament_profile = ["Flashforge Generic PLA"] |
  .default_bed_type = "Textured PEI Plate"
'

# Enable supports by default for the curated print profiles.
rewrite_json "${PROFILES_DIR}/Dremel/process/Dremel_3D45_Process_Optimized.json" '
  .enable_support = 1 |
  .support_type = "tree(auto)"
'
for process in \
  "${PROFILES_DIR}/Flashforge/process/0.20mm Standard @Flashforge AD5M Pro 0.4 Nozzle.json" \
  "${PROFILES_DIR}/Flashforge/process/0.30mm Standard @Flashforge AD5M Pro 0.6 Nozzle.json" \
  "${PROFILES_DIR}/Flashforge/process/0.40mm Standard @Flashforge AD5M Pro 0.8 Nozzle.json"; do
  if [[ -f "${process}" ]]; then
    rewrite_json "${process}" '
      .enable_support = 1 |
      .support_type = "tree(auto)"
    '
  fi
done

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
