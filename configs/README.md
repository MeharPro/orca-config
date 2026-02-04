# Custom OrcaSlicer Configs

Put your exported OrcaSlicer presets here so they live alongside the mirrored Windows Portable release.

Suggested structure:
- `configs/printers/` (printer profiles/presets you export)
- `configs/filaments/` (filament profiles/presets you export)

Notes:
- The sync automation only writes to `releases/` and will not overwrite anything under `configs/`.
- `scripts/install-windows-portable.ps1` will copy this folder into the installed portable directory under `user-configs/` (for easy import).

