# orca-config

This repo:
- Mirrors the latest **OrcaSlicer Windows Portable** release asset from `OrcaSlicer/OrcaSlicer`
- Keeps your custom OrcaSlicer presets in git under `configs/`

## Daily Sync (GitHub Actions)

Workflow: `.github/workflows/sync-orcaslicer-release.yml`

What it does:
- Checks `https://api.github.com/repos/OrcaSlicer/OrcaSlicer/releases/latest`
- If there’s a new tag, updates files under `releases/`
- Downloads the **Windows Portable** asset, overlays your files from `configs/portable-overlay/root/`, rezips, and uploads it to this repo’s **GitHub Release** with the same tag
- Marks the synced tag as this repo's **Latest** release automatically
- Publishes mirror-owned release notes (and links upstream), instead of copying upstream notes text

## Daily Sync (Vercel Cron Backup)

This repo also includes a Vercel Cron endpoint that can trigger the GitHub Actions workflow automatically:
- `api/cron/sync.js`
- `vercel.json`

To enable it, set Vercel env var `GITHUB_PAT` (a GitHub PAT that can dispatch workflows on `MeharPro/orca-config`).
Optionally set `CRON_SECRET` and update the Vercel Cron path to include `?secret=...`.

## Admin Upload (No Local Computer Needed)

You can add/update printer/filament/process configs directly from the web without using your computer:

- Admin UI: `/admin`
- API: `/api/admin/commit`

Required Vercel env vars:
- `GITHUB_PAT` (GitHub PAT with repo + workflow permissions on `MeharPro/orca-config`)
- `ADMIN_PASSWORD` (password for the admin UI/API)

How it works:
- You upload a folder from the browser (it preserves relative paths).
- The API commits those files into the correct `configs/` subfolder in GitHub.
- If you upload to the **overlay** target, the next automation run will bake those files into the portable zip automatically.
- You can list/remove printer, filament, and process profiles from `/admin`.
- The admin lists are sourced from `releases/profile_catalog.json` (generated from the actual packaged zip), so they reflect what Orca can currently see.

Security notes:
- Use a strong random `ADMIN_PASSWORD` only in Vercel env vars.
- The admin APIs now accept password only via request headers (not URL query params).
- Keep Vercel deployment protection enabled and do not share the admin URL publicly.

## Custom Presets

Put your exported presets here:
- `configs/printers/`
- `configs/filaments/`

The sync job only writes to `releases/` and will not overwrite anything under `configs/`.

## Bake Presets Into Portable Zip (Auto)

To ship a “pre-configured” portable build, put files under:
- `configs/portable-overlay/root/`

These files must match the same paths inside the upstream portable zip (example: `resources/profiles/...`).

## Custom Branding

This repo can replace OrcaSlicer UI logo assets in the packaged portable zip.

- Source logo: `branding/school-logo.png`
- Generator: `scripts/generate-school-branding.py`
- Output overlay: `configs/portable-overlay/root/resources/images/`

When those overlay files are present, every automated repackage/release uses the school branding assets.

## Install (Windows)

From PowerShell:
```powershell
.\scripts\install-windows-portable.ps1
```

Options:
```powershell
.\scripts\install-windows-portable.ps1 -InstallDir "C:\Apps\OrcaSlicerPortable" -Force
```
