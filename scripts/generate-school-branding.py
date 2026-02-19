#!/usr/bin/env python3
import argparse
import base64
import io
from pathlib import Path

from PIL import Image, ImageOps


def load_logo(path: Path) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    return img


def render_contain(logo: Image.Image, width: int, height: int, grayscale: bool = False) -> Image.Image:
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    fit = ImageOps.contain(logo, (width, height), Image.Resampling.LANCZOS)
    x = (width - fit.width) // 2
    y = (height - fit.height) // 2
    canvas.alpha_composite(fit, (x, y))
    if grayscale:
        alpha = canvas.getchannel("A")
        gray = ImageOps.grayscale(canvas)
        canvas = Image.merge("RGBA", (gray, gray, gray, alpha))
    return canvas


def save_png(logo: Image.Image, out: Path, width: int, height: int, grayscale: bool = False) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    render_contain(logo, width, height, grayscale=grayscale).save(out, "PNG")


def save_ico(logo: Image.Image, out: Path, size: int = 256) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    img = render_contain(logo, size, size)
    img.save(out, format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (154, 154), (256, 256)])


def save_icns(logo: Image.Image, out: Path, size: int = 1024) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    img = render_contain(logo, size, size)
    img.save(out, format="ICNS")


def save_svg_embed(logo: Image.Image, out: Path, width: str, height: str, viewbox: str) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    vb = [float(p) for p in viewbox.split()]
    vb_w = int(round(vb[2]))
    vb_h = int(round(vb[3]))
    raster = render_contain(logo, vb_w, vb_h)
    bio = io.BytesIO()
    raster.save(bio, "PNG")
    b64 = base64.b64encode(bio.getvalue()).decode("ascii")
    svg = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="{viewbox}">\n'
        f'  <image href="data:image/png;base64,{b64}" x="0" y="0" width="{vb_w}" height="{vb_h}" preserveAspectRatio="xMidYMid meet"/>\n'
        "</svg>\n"
    )
    out.write_text(svg, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Orca branding replacement assets from a school logo.")
    parser.add_argument("--logo", default="branding/school-logo.png", help="Input logo image path")
    parser.add_argument("--overlay-root", default="configs/portable-overlay/root", help="Overlay root directory")
    args = parser.parse_args()

    logo = load_logo(Path(args.logo))
    overlay_root = Path(args.overlay_root)
    images_root = overlay_root / "resources" / "images"

    png_targets = [
        ("OrcaSlicer.png", 154, 154, False),
        ("OrcaSlicer_32px.png", 32, 32, False),
        ("OrcaSlicer_64.png", 64, 64, False),
        ("OrcaSlicer_128px.png", 128, 128, False),
        ("OrcaSlicer_154.png", 154, 154, False),
        ("OrcaSlicer_154_title.png", 184, 184, False),
        ("OrcaSlicer_192px.png", 192, 192, False),
        ("OrcaSlicer_192px_transparent.png", 192, 192, False),
        ("OrcaSlicer_192px_grayscale.png", 192, 192, True),
        ("OrcaSlicerTitle.png", 154, 154, False),
        ("OrcaSlicer-mac_128px.png", 128, 128, False),
    ]
    for name, w, h, gray in png_targets:
        save_png(logo, images_root / name, w, h, grayscale=gray)

    save_ico(logo, images_root / "OrcaSlicer.ico")
    save_ico(logo, images_root / "OrcaSlicer-mac_256px.ico")
    save_ico(logo, images_root / "OrcaSlicerTitle.ico")
    save_icns(logo, images_root / "OrcaSlicer.icns")
    save_icns(logo, overlay_root / "resources" / "Icon.icns")

    svg_targets = [
        ("OrcaSlicer.svg", "1024", "1024", "0 0 1024 1024"),
        ("OrcaSlicer_about.svg", "560", "125", "0 0 560 125"),
        ("OrcaSlicer_about_dark.svg", "560", "125", "0 0 560 125"),
        ("OrcaSlicer_gradient.svg", "1024", "1024", "0 0 1024 1024"),
        ("OrcaSlicer_gradient_narrow.svg", "814.987", "1023.9927", "0 0 814.987 1023.9927"),
        ("OrcaSlicer_gradient_circle.svg", "1024", "1024", "0 0 1280 1280"),
        ("OrcaSlicer_gray.svg", "1024", "1024", "0 0 1024 1024"),
        ("splash_logo.svg", "480", "480", "0 0 480 480"),
        ("splash_logo_dark.svg", "480", "480", "0 0 480 480"),
    ]
    for name, w, h, viewbox in svg_targets:
        save_svg_embed(logo, images_root / name, w, h, viewbox)

    print("Generated branding assets in", images_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
