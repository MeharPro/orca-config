# Portable Overlay (Auto-Injected)

Everything under `configs/portable-overlay/root/` gets **copied into** the OrcaSlicer Windows Portable archive **before** it is rezipped and uploaded to this repo’s GitHub Release.

How to use it:
- Create files/folders that match the *same paths* inside the upstream portable zip.
- On every upstream release sync, those files will overwrite the upstream versions.

Examples:
- Add/override built-in profiles:
  - `configs/portable-overlay/root/resources/profiles/MeharPro.json`
  - `configs/portable-overlay/root/resources/profiles/MeharPro/machine/...`
  - `configs/portable-overlay/root/resources/profiles/MeharPro/filament/...`
  - `configs/portable-overlay/root/resources/profiles/MeharPro/process/...`
- Override a built-in printer definition:
  - `configs/portable-overlay/root/resources/printers/C11.json`

Notes:
- This is for **baking defaults into the portable app** (so you don’t have to import presets manually).
- If you only want “files to import later”, use `configs/printers/` and `configs/filaments/` instead.
