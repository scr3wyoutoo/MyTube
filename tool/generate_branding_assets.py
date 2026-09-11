"""Generate all native MyTube icon and splash assets from the master artwork."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / "assets" / "branding"
MASCOT_PATH = BRANDING / "mytube_mascot.png"
SPLASH_ART_PATH = BRANDING / "mytube_splash_art.png"

CREAM = (253, 248, 234)
CREAM_DARK = (247, 226, 197)
NAVY = (7, 38, 70)
CORAL = (242, 73, 66)
TURQUOISE = (25, 190, 181)


def _font(size: int) -> ImageFont.FreeTypeFont:
    candidates = (
        Path("C:/Windows/Fonts/segoeuib.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf"),
    )
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.truetype("DejaVuSans-Bold.ttf", size=size)


def _contain(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    result = image.copy()
    result.thumbnail(size, Image.Resampling.LANCZOS)
    return result


def _trim_alpha(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("The mascot source has no visible pixels.")
    return image.crop(bounds)


def _build_icon_source(mascot: Image.Image) -> Image.Image:
    size = 1024
    icon = Image.new("RGB", (size, size), CREAM)
    pixels = icon.load()
    for y in range(size):
        t = y / (size - 1)
        color = tuple(
            round(CREAM[channel] * (1 - t) + CREAM_DARK[channel] * t)
            for channel in range(3)
        )
        for x in range(size):
            pixels[x, y] = color

    draw = ImageDraw.Draw(icon, "RGBA")
    draw.ellipse((-175, -195, 335, 315), fill=(*TURQUOISE, 38))
    draw.ellipse((755, 720, 1125, 1090), fill=(*CORAL, 42))
    draw.rounded_rectangle(
        (735, 80, 940, 116), radius=18, fill=(*CORAL, 82)
    )
    draw.rounded_rectangle(
        (84, 842, 295, 878), radius=18, fill=(*TURQUOISE, 82)
    )

    trimmed = _trim_alpha(mascot)
    fitted = _contain(trimmed, (820, 820))
    x = (size - fitted.width) // 2
    y = (size - fitted.height) // 2 + 8
    icon.paste(fitted, (x, y), fitted)
    return icon


def _build_foreground(mascot: Image.Image, size: int) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    fitted = _contain(_trim_alpha(mascot), (round(size * 0.70), round(size * 0.70)))
    x = (size - fitted.width) // 2
    y = (size - fitted.height) // 2 + round(size * 0.012)
    canvas.paste(fitted, (x, y), fitted)
    return canvas


def _build_splash_source(art: Image.Image) -> Image.Image:
    splash = art.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)
    draw = ImageDraw.Draw(splash)
    font = _font(104)
    label = "MyTube"
    bounds = draw.textbbox((0, 0), label, font=font)
    width = bounds[2] - bounds[0]
    x = (1024 - width) // 2
    y = 850
    draw.text((x + 4, y + 5), label, font=font, fill=(255, 255, 255))
    draw.text((x, y), label, font=font, fill=NAVY)
    underline_width = round(width * 0.62)
    underline_x = (1024 - underline_width) // 2
    draw.rounded_rectangle(
        (underline_x, y + 118, underline_x + underline_width, y + 132),
        radius=7,
        fill=TURQUOISE,
    )
    return splash


def _save_rgb(source: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    source.convert("RGB").resize((size, size), Image.Resampling.LANCZOS).save(
        path, optimize=True
    )


def _save_rgba(source: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    source.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS).save(
        path, optimize=True
    )


def _generate_android(icon: Image.Image, mascot: Image.Image, splash: Image.Image) -> None:
    densities = {
        "mdpi": 1.0,
        "hdpi": 1.5,
        "xhdpi": 2.0,
        "xxhdpi": 3.0,
        "xxxhdpi": 4.0,
    }
    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for density, scale in densities.items():
        _save_rgb(icon, res / f"mipmap-{density}" / "ic_launcher.png", round(48 * scale))
        _save_rgb(
            icon,
            res / f"mipmap-{density}" / "ic_launcher_round.png",
            round(48 * scale),
        )
        foreground = _build_foreground(mascot, round(108 * scale))
        foreground.save(
            res / f"mipmap-{density}" / "ic_launcher_foreground.png", optimize=True
        )
        _save_rgb(
            splash,
            res / f"drawable-{density}" / "mytube_splash.png",
            round(240 * scale),
        )


def _generate_apple_asset_set(icon: Image.Image, contents_path: Path) -> None:
    contents = json.loads(contents_path.read_text(encoding="utf-8"))
    for entry in contents["images"]:
        filename = entry.get("filename")
        logical_size = entry.get("size")
        scale_text = entry.get("scale")
        if not filename or not logical_size or not scale_text:
            continue
        points = float(logical_size.split("x", 1)[0])
        scale = int(scale_text.removesuffix("x"))
        _save_rgb(icon, contents_path.parent / filename, round(points * scale))


def _generate_ios(icon: Image.Image, splash: Image.Image) -> None:
    _generate_apple_asset_set(
        icon, ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json"
    )
    launch_set = ROOT / "ios" / "Runner" / "Assets.xcassets" / "LaunchImage.imageset"
    for filename, scale in (
        ("LaunchImage.png", 1),
        ("LaunchImage@2x.png", 2),
        ("LaunchImage@3x.png", 3),
    ):
        _save_rgb(splash, launch_set / filename, 240 * scale)


def _generate_macos(icon: Image.Image) -> None:
    contents_path = (
        ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json"
    )
    if contents_path.exists():
        _generate_apple_asset_set(icon, contents_path)


def _generate_web(icon: Image.Image, mascot: Image.Image, splash: Image.Image) -> None:
    icons = ROOT / "web" / "icons"
    _save_rgb(icon, icons / "Icon-192.png", 192)
    _save_rgb(icon, icons / "Icon-512.png", 512)
    _save_rgb(icon, icons / "Icon-maskable-192.png", 192)
    _save_rgb(icon, icons / "Icon-maskable-512.png", 512)
    _save_rgb(icon, ROOT / "web" / "favicon.png", 32)
    _save_rgb(splash, icons / "MyTube-Splash.png", 512)
    _save_rgba(_build_foreground(mascot, 512), icons / "MyTube-Mascot.png", 512)


def _generate_windows(icon: Image.Image) -> None:
    destination = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    destination.parent.mkdir(parents=True, exist_ok=True)
    icon.save(
        destination,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


def main() -> None:
    mascot = Image.open(MASCOT_PATH).convert("RGBA")
    splash_art = Image.open(SPLASH_ART_PATH).convert("RGB")
    icon = _build_icon_source(mascot)
    splash = _build_splash_source(splash_art)

    icon.save(BRANDING / "mytube_icon_source.png", optimize=True)
    splash.save(BRANDING / "mytube_splash_source.png", optimize=True)

    _generate_android(icon, mascot, splash)
    _generate_ios(icon, splash)
    _generate_macos(icon)
    _generate_web(icon, mascot, splash)
    _generate_windows(icon)

    print("Generated MyTube icons and splash assets from the master artwork.")
    print(f"Icon source: {BRANDING / 'mytube_icon_source.png'}")
    print(f"Splash source: {BRANDING / 'mytube_splash_source.png'}")


if __name__ == "__main__":
    main()
