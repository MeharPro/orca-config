# orca-config

This repo:
- Mirrors the latest **OrcaSlicer Windows Portable** release asset from `OrcaSlicer/OrcaSlicer`
- Keeps your custom OrcaSlicer presets in git under `configs/`

## Daily Sync (GitHub Actions)

Workflow: `.github/workflows/sync-orcaslicer-release.yml`

What it does:
- Checks `https://api.github.com/repos/OrcaSlicer/OrcaSlicer/releases/latest`
- If there’s a new tag, updates files under `releases/`
- Downloads the **Windows Portable** asset and uploads it to this repo’s **GitHub Release** with the same tag

## Custom Presets

Put your exported presets here:
- `configs/printers/`
- `configs/filaments/`

The sync job only writes to `releases/` and will not overwrite anything under `configs/`.

## Install (Windows)

From PowerShell:
```powershell
.\scripts\install-windows-portable.ps1
```

Options:
```powershell
.\scripts\install-windows-portable.ps1 -InstallDir "C:\Apps\OrcaSlicerPortable" -Force
```

