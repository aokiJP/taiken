"""体験 のアプリアイコン: 夜明けの空に、朱の印「体」。ライト・ダーク・色付きの3種を書き出す。

使い方: python3 tools/make_app_icon.py Taiken/Assets.xcassets/AppIcon.appiconset
(Pillow と Noto Serif CJK が必要)
"""
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(sys.argv[1])
SIZE = 1024
FONT_PATH = "/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc"


def jp_font(size):
    for index in range(10):
        try:
            font = ImageFont.truetype(FONT_PATH, size, index=index)
        except OSError:
            break
        if "JP" in " ".join(font.getname()):
            return font
    return ImageFont.truetype(FONT_PATH, size, index=0)


def hex_rgb(value):
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


def gradient(stops):
    """縦のグラデーション (stops: [(位置0〜1, '#rrggbb')])"""
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                k = (t - p0) / (p1 - p0) if p1 > p0 else 0
                a, b = hex_rgb(c0), hex_rgb(c1)
                color = tuple(round(a[i] + (b[i] - a[i]) * k) for i in range(3))
                break
        for x in range(SIZE):
            px[x, y] = color
    return img


def glow(img, center, radius, color, strength):
    """温かい光の溜まり"""
    layer = Image.new("RGB", (SIZE, SIZE), color)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse(
        [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius], fill=int(255 * strength)
    )
    mask = mask.filter(ImageFilter.GaussianBlur(radius * 0.45))
    return Image.composite(layer, img, mask)


def seal_layer(fill, glyph_color, seed, side=600, rotation=-6, cut_glyph=False):
    """印 (白文): 朱の角丸の地に、白抜きの文字。朱肉のかすれを少しだけ付ける"""
    scale = 4  # 縁をなめらかにするため大きく描いて縮める
    big = side * scale
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    radius = int(big * 0.2)
    draw.rounded_rectangle([0, 0, big - 1, big - 1], radius=radius, fill=fill)

    font = jp_font(int(big * 0.64))
    text = "体"
    box = draw.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    pos = ((big - w) / 2 - box[0], (big - h) / 2 - box[1] - big * 0.01)
    if cut_glyph:
        glyph = Image.new("L", (big, big), 0)
        ImageDraw.Draw(glyph).text(pos, text, font=font, fill=255)
        alpha = layer.getchannel("A")
        alpha = Image.composite(Image.new("L", (big, big), 0), alpha, glyph)
        layer.putalpha(alpha)
    else:
        draw.text(pos, text, font=font, fill=glyph_color)

    # かすれ: 小さな点を透明にする (同じ seed なら同じ模様)
    rng = random.Random(seed)
    alpha = layer.getchannel("A")
    speck = ImageDraw.Draw(alpha)
    for _ in range(70):
        r = rng.uniform(0.002, 0.0065) * big
        # 縁に近いほど、かすれやすい
        edge = rng.choice(["t", "b", "l", "r"])
        depth = abs(rng.gauss(0, 0.09)) * big
        t = rng.uniform(0, big)
        x, y = {"t": (t, depth), "b": (t, big - depth), "l": (depth, t), "r": (big - depth, t)}[edge]
        speck.ellipse([x - r, y - r, x + r, y + r], fill=0)
    for _ in range(14):
        r = rng.uniform(0.002, 0.005) * big
        x, y = rng.uniform(0, big), rng.uniform(0, big)
        speck.ellipse([x - r, y - r, x + r, y + r], fill=0)
    # 縁の一部をわずかに欠けさせる
    for _ in range(12):
        edge = rng.choice(["t", "b", "l", "r"])
        t = rng.uniform(0.12, 0.88) * big
        r = rng.uniform(0.004, 0.011) * big
        x, y = {"t": (t, 0), "b": (t, big), "l": (0, t), "r": (big, t)}[edge]
        speck.ellipse([x - r, y - r, x + r, y + r], fill=0)
    layer.putalpha(alpha)

    layer = layer.resize((side, side), Image.LANCZOS)
    return layer.rotate(rotation, resample=Image.BICUBIC, expand=True)


def place(base, layer, offset=(0, 0)):
    x = (SIZE - layer.width) // 2 + offset[0]
    y = (SIZE - layer.height) // 2 + offset[1]
    base.paste(layer, (x, y), layer)
    return base


def shadow_for(layer, blur=26, opacity=0.28, color=(28, 33, 49)):
    alpha = layer.getchannel("A").point(lambda a: int(a * opacity))
    pad = blur * 3
    canvas = Image.new("RGBA", (layer.width + pad * 2, layer.height + pad * 2), (0, 0, 0, 0))
    solid = Image.new("RGBA", layer.size, color + (255,))
    solid.putalpha(alpha)
    canvas.paste(solid, (pad, pad), solid)
    return canvas.filter(ImageFilter.GaussianBlur(blur))


def stars(img, seed, count):
    rng = random.Random(seed)
    draw = ImageDraw.Draw(img)
    for _ in range(count):
        x, y = rng.uniform(0, SIZE), rng.uniform(0, SIZE * 0.62)
        r = rng.uniform(1.2, 3.4)
        a = int(rng.uniform(90, 230))
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))
    return img


def light():
    sky = gradient([(0, "#C3CDE6"), (0.58, "#EFD3D6"), (1, "#FBE6D6")])
    sky = glow(sky, (SIZE * 0.42, SIZE * 0.68), SIZE * 0.42, hex_rgb("#FFF1E4"), 0.55)
    base = sky.convert("RGBA")
    seal = seal_layer((204, 58, 44, 255), (255, 247, 243, 255), seed=7)
    place(base, shadow_for(seal), (0, 22))
    return place(base, seal)


def dark():
    sky = gradient([(0, "#0D1225"), (0.58, "#161F40"), (1, "#22294B")])
    sky = glow(sky, (SIZE * 0.42, SIZE * 0.7), SIZE * 0.4, hex_rgb("#3C2A3E"), 0.6)
    base = stars(sky.convert("RGBA"), seed=11, count=46)
    seal = seal_layer((236, 91, 75, 255), (255, 247, 243, 255), seed=7)
    place(base, shadow_for(seal, opacity=0.5, color=(0, 0, 0)), (0, 22))
    return place(base, seal)


def tinted():
    """色付きアイコン: 黒地に明るい灰色の印 (文字は抜く)。色はシステムが付ける"""
    base = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    seal = seal_layer((226, 226, 226, 255), None, seed=7, cut_glyph=True)
    return place(base, seal)


OUT.mkdir(parents=True, exist_ok=True)
light().convert("RGB").save(OUT / "AppIcon.png")
dark().convert("RGB").save(OUT / "AppIcon-Dark.png")
tinted().convert("RGB").save(OUT / "AppIcon-Tinted.png")
print("ok")
