# Custom OrcaSlicer Configs

Put your exported OrcaSlicer presets here so they live alongside the mirrored Windows Portable release.

Suggested structure:
- `configs/printers/` (printer profiles/presets you export)
- `configs/filaments/` (filament profiles/presets you export)
- `configs/processes/` (process/quality presets you export)
- `configs/portable-overlay/` (advanced: files to bake into the portable zip)

Notes:
- The sync automation only writes to `releases/` and will not overwrite anything under `configs/`.
- `scripts/install-windows-portable.ps1` will copy this folder into the installed portable directory under `user-configs/` (for easy import).
- To automatically inject configs into the Windows Portable archive (so they’re “pre-installed”), put them under `configs/portable-overlay/root/` with paths that match the upstream zip layout.

Example (Dremel 3D45):
- `configs/printers/Dremel 3D45/`
- `configs/filaments/Dremel/`
- `configs/processes/Dremel/`
