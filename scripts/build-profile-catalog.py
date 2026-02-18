#!/usr/bin/env python3
import json
import sys
import zipfile
from datetime import datetime, timezone


def usage() -> None:
    print("Usage: build-profile-catalog.py <portable_zip> <output_json>", file=sys.stderr)


def list_names(entries, skip_prefix=False):
    out = []
    for item in entries or []:
        name = (item or {}).get("name")
        if not name:
            continue
        if skip_prefix and name.startswith("fdm_"):
            continue
        out.append(name)
    return out


def main() -> int:
    if len(sys.argv) != 3:
        usage()
        return 2

    zip_path = sys.argv[1]
    out_path = sys.argv[2]

    vendor_files = []
    with zipfile.ZipFile(zip_path, "r") as zf:
        for name in zf.namelist():
            if not name.startswith("resources/profiles/"):
                continue
            if name.count("/") != 2:
                continue
            if not name.endswith(".json"):
                continue
            vendor_files.append(name)

        vendors = {}
        all_printers = set()
        all_filaments = set()
        all_processes = set()

        for path in sorted(vendor_files):
            vendor = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
            with zf.open(path, "r") as fh:
                data = json.load(fh)

            printers = sorted(set(list_names(data.get("machine_model_list"), skip_prefix=False)))
            filaments = sorted(set(list_names(data.get("filament_list"), skip_prefix=True)))
            processes = sorted(set(list_names(data.get("process_list"), skip_prefix=True)))

            for p in printers:
                all_printers.add(p)
            for f in filaments:
                all_filaments.add(f)
            for p in processes:
                all_processes.add(p)

            vendors[vendor] = {
                "printers": printers,
                "filaments": filaments,
                "processes": processes,
            }

    out = {
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source_zip": zip_path.rsplit("/", 1)[-1],
        "printers": sorted(all_printers),
        "filaments": sorted(all_filaments),
        "processes": sorted(all_processes),
        "vendors": vendors,
    }

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
