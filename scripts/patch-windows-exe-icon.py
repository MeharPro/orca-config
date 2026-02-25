#!/usr/bin/env python3
"""Patch a Windows PE executable icon resource from an .ico file.

This replaces existing RT_ICON payloads while preserving icon IDs and language
metadata, so group-icon references stay valid for the taskbar and shell.
"""

from __future__ import annotations

import argparse
import struct
import sys
from dataclasses import dataclass
from pathlib import Path


try:
    import lief
except Exception as exc:  # pragma: no cover - runtime dependency guard
    print(
        "Missing dependency 'lief'. Install with: python3 -m pip install lief\n"
        f"Import error: {exc}",
        file=sys.stderr,
    )
    raise SystemExit(2)


@dataclass(frozen=True)
class IcoFrame:
    width: int
    height: int
    color_count: int
    reserved: int
    planes: int
    bit_count: int
    data: bytes


def read_ico_frames(ico_path: Path) -> list[IcoFrame]:
    blob = ico_path.read_bytes()
    if len(blob) < 6:
        raise ValueError(f"ICO is too small: {ico_path}")

    reserved, image_type, count = struct.unpack_from("<HHH", blob, 0)
    if reserved != 0 or image_type != 1 or count == 0:
        raise ValueError(f"Invalid ICO header in {ico_path}")

    expected_size = 6 + (count * 16)
    if len(blob) < expected_size:
        raise ValueError(f"Truncated ICO directory in {ico_path}")

    frames: list[IcoFrame] = []
    for idx in range(count):
        offset = 6 + (idx * 16)
        w, h, color_count, reserved, planes, bit_count, size, data_offset = struct.unpack_from(
            "<BBBBHHII", blob, offset
        )
        width = 256 if w == 0 else w
        height = 256 if h == 0 else h
        end = data_offset + size
        if end > len(blob):
            raise ValueError(f"ICO frame {idx} out of bounds in {ico_path}")
        frames.append(
            IcoFrame(
                width=width,
                height=height,
                color_count=color_count,
                reserved=reserved,
                planes=planes,
                bit_count=bit_count,
                data=blob[data_offset:end],
            )
        )

    return frames


def pick_best_frame(frames: list[IcoFrame], target_width: int, target_height: int) -> IcoFrame:
    exact = [f for f in frames if f.width == target_width and f.height == target_height]
    if exact:
        exact.sort(key=lambda f: (f.bit_count, len(f.data)), reverse=True)
        return exact[0]

    def score(frame: IcoFrame) -> tuple[int, int, int]:
        distance = abs(frame.width - target_width) + abs(frame.height - target_height)
        return (distance, -frame.bit_count, -len(frame.data))

    return sorted(frames, key=score)[0]


def patch_exe_icon(exe_path: Path, ico_path: Path) -> None:
    binary = lief.PE.parse(str(exe_path))
    if binary is None:
        raise RuntimeError(f"Failed to parse PE binary: {exe_path}")

    if not binary.has_resources:
        raise RuntimeError(f"PE binary has no resources: {exe_path}")

    manager = binary.resources_manager
    if not manager.has_icons:
        raise RuntimeError(f"PE binary has no icon resources: {exe_path}")

    frames = read_ico_frames(ico_path)
    icons = list(manager.icons)
    if not icons:
        raise RuntimeError(f"No icon entries found in: {exe_path}")

    for old_icon in icons:
        target_width = old_icon.width or 256
        target_height = old_icon.height or 256
        frame = pick_best_frame(frames, target_width, target_height)

        new_icon = lief.PE.ResourceIcon.from_serialization(old_icon.serialize())
        if not isinstance(new_icon, lief.PE.ResourceIcon):
            raise RuntimeError("Could not clone icon entry for patching")

        # Preserve resource identity and group linkage.
        new_icon.id = old_icon.id
        new_icon.lang = old_icon.lang
        new_icon.sublang = old_icon.sublang
        new_icon.width = old_icon.width
        new_icon.height = old_icon.height
        new_icon.color_count = old_icon.color_count
        new_icon.reserved = old_icon.reserved
        new_icon.planes = old_icon.planes
        new_icon.bit_count = old_icon.bit_count
        new_icon.pixels = list(frame.data)
        manager.change_icon(old_icon, new_icon)

    builder_config = lief.PE.Builder.config_t()
    builder = lief.PE.Builder(binary, builder_config)
    builder.build()

    out_tmp = exe_path.with_suffix(exe_path.suffix + ".tmp")
    builder.write(str(out_tmp))
    out_tmp.replace(exe_path)


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch Windows .exe icon resources from an .ico file.")
    parser.add_argument("--exe", required=True, help="Path to target PE executable")
    parser.add_argument("--ico", required=True, help="Path to source .ico file")
    args = parser.parse_args()

    exe_path = Path(args.exe)
    ico_path = Path(args.ico)
    if not exe_path.is_file():
        print(f"Executable not found: {exe_path}", file=sys.stderr)
        return 2
    if not ico_path.is_file():
        print(f"Icon file not found: {ico_path}", file=sys.stderr)
        return 2

    patch_exe_icon(exe_path, ico_path)
    print(f"Patched taskbar icon in {exe_path.name} using {ico_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
