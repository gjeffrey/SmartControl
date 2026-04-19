#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Resources" / "AppIcon.iconset"
MASTER = ROOT / "Resources" / "AppIcon-master.png"


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(top[0] * (1 - t) + bottom[0] * t)
        g = int(top[1] * (1 - t) + bottom[1] * t)
        b = int(top[2] * (1 - t) + bottom[2] * t)
        for x in range(size):
            pixels[x, y] = (r, g, b, 255)
    return image


def alpha_composite(base: Image.Image, overlay: Image.Image, mask: Image.Image | None = None) -> Image.Image:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.alpha_composite(overlay)
    if mask is not None:
        return Image.composite(layer, base, mask)
    result = base.copy()
    result.alpha_composite(overlay)
    return result


def draw_master() -> Image.Image:
    size = 1024
    corner = 232
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((108, 118, 916, 926), radius=corner, fill=(0, 0, 0, 180))
    shadow = shadow.filter(ImageFilter.GaussianBlur(50))
    image.alpha_composite(shadow)

    body = vertical_gradient(size, (238, 244, 250), (174, 190, 207))
    body_mask = rounded_mask(size, corner)
    image = Image.composite(body, image, body_mask)

    top_glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tg = ImageDraw.Draw(top_glow)
    tg.rounded_rectangle((54, 44, 970, 530), radius=190, fill=(255, 255, 255, 132))
    top_glow = top_glow.filter(ImageFilter.GaussianBlur(28))
    image.alpha_composite(top_glow)

    tint = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tint_draw = ImageDraw.Draw(tint)
    tint_draw.ellipse((90, 54, 860, 648), fill=(145, 208, 255, 105))
    tint_draw.ellipse((440, 400, 1000, 980), fill=(74, 122, 255, 60))
    tint = tint.filter(ImageFilter.GaussianBlur(70))
    image.alpha_composite(tint)

    platter = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    platter_draw = ImageDraw.Draw(platter)
    platter_draw.rounded_rectangle((214, 220, 810, 812), radius=146, fill=(31, 42, 56, 255))
    platter_draw.rounded_rectangle((236, 242, 788, 790), radius=128, fill=(44, 60, 78, 255))
    platter_draw.rounded_rectangle((260, 266, 764, 766), radius=110, fill=(222, 233, 245, 245))
    platter_draw.rounded_rectangle((282, 288, 742, 742), radius=92, fill=(210, 224, 238, 255))
    platter = platter.filter(ImageFilter.GaussianBlur(0.3))
    image.alpha_composite(platter)

    rings = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ring_draw = ImageDraw.Draw(rings)
    ring_draw.ellipse((352, 358, 672, 678), outline=(91, 104, 120, 120), width=12)
    ring_draw.ellipse((394, 400, 630, 636), outline=(255, 255, 255, 150), width=8)
    ring_draw.ellipse((468, 474, 556, 562), fill=(88, 102, 118, 255))
    ring_draw.ellipse((490, 496, 534, 540), fill=(228, 238, 247, 255))
    image.alpha_composite(rings)

    arm = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    arm_draw = ImageDraw.Draw(arm)
    arm_draw.rounded_rectangle((584, 388, 676, 640), radius=46, fill=(40, 54, 72, 255))
    arm_draw.rounded_rectangle((616, 432, 738, 500), radius=32, fill=(47, 63, 84, 255))
    arm_draw.rounded_rectangle((672, 458, 792, 514), radius=28, fill=(231, 239, 246, 255))
    arm_draw.polygon([(758, 474), (844, 432), (854, 456), (784, 516)], fill=(231, 239, 246, 255))
    arm_draw.ellipse((586, 390, 674, 478), fill=(231, 239, 246, 255))
    arm_draw.ellipse((610, 414, 650, 454), fill=(57, 75, 96, 255))
    image.alpha_composite(arm)

    glass = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glass_draw = ImageDraw.Draw(glass)
    glass_draw.rounded_rectangle((144, 136, 880, 402), radius=132, fill=(255, 255, 255, 88))
    glass_draw.rounded_rectangle((180, 612, 534, 710), radius=49, fill=(255, 255, 255, 48))
    glass = glass.filter(ImageFilter.GaussianBlur(14))
    image.alpha_composite(glass)

    border = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    border_draw = ImageDraw.Draw(border)
    border_draw.rounded_rectangle((2, 2, size - 3, size - 3), radius=corner, outline=(255, 255, 255, 110), width=5)
    border_draw.rounded_rectangle((18, 18, size - 19, size - 19), radius=corner - 18, outline=(0, 0, 0, 28), width=2)
    image.alpha_composite(border)

    image.putalpha(body_mask)
    return image


def save_iconset(master: Image.Image) -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, dimension in sizes.items():
        resized = master.resize((dimension, dimension), Image.Resampling.LANCZOS)
        resized.save(ICONSET / name)


def main() -> None:
    master = draw_master()
    MASTER.parent.mkdir(parents=True, exist_ok=True)
    master.save(MASTER)
    save_iconset(master)


if __name__ == "__main__":
    main()
