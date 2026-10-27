#!/usr/bin/env python3
"""Render the Home tab with the Airlift / VPN connections panel.

There is no Xcode (and no browser) in this runner, so the board is drawn with
PIL from the tokens in ThreeOneOSFive/views/DesignSystem.swift instead of
screenshotting a simulator. Translucent fills go through their own layer so
they composite instead of replacing pixels.
"""
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
import matplotlib

FONTS = os.path.join(matplotlib.get_data_path(), "fonts", "ttf")


def _font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), int(round(size)))


def mono(s):
    return _font("DejaVuSansMono.ttf", s)


def mono_b(s):
    return _font("DejaVuSansMono-Bold.ttf", s)


def sans(s):
    return _font("DejaVuSans.ttf", s)


def sans_b(s):
    return _font("DejaVuSans-Bold.ttf", s)


MINT = "#65d6c2"
CANVAS = "#0b0f14"
SURFACE = "#111821"
RAISED = "#19232d"
HAIR = "#293542"
T1 = "#f2f5f7"
T2 = "#a7b2bf"
T3 = "#8f9ba8"
AMBER = "#e9b45f"
CORAL = "#f0746c"
VIOLET = "#8f86ff"


def rgb(c):
    if isinstance(c, tuple):
        return c[:3]
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


def rgba(c, a=255):
    return rgb(c) + (int(a),)


def vgrad(size, c1, c2):
    w, h = size
    a, b = rgb(c1), rgb(c2)
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        k = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3)))
    return img.convert("RGBA")


class Pen:
    """A drawing pen whose translucent shapes composite instead of replacing."""

    def __init__(self, img):
        self.img = img
        self.d = ImageDraw.Draw(img)

    def _layer(self):
        return Image.new("RGBA", self.img.size, (0, 0, 0, 0))

    def rr(self, box, radius, fill=None, outline=None, width=1):
        lay = self._layer()
        ImageDraw.Draw(lay).rounded_rectangle(box, radius=int(radius), fill=fill, outline=outline, width=int(width))
        self.img.alpha_composite(lay)

    def ell(self, box, fill=None, outline=None, width=1):
        lay = self._layer()
        ImageDraw.Draw(lay).ellipse(box, fill=fill, outline=outline, width=int(width))
        self.img.alpha_composite(lay)

    def line(self, xy, fill, width=1):
        lay = self._layer()
        ImageDraw.Draw(lay).line(xy, fill=fill, width=int(width))
        self.img.alpha_composite(lay)

    def arc(self, box, start, end, fill, width=1):
        lay = self._layer()
        ImageDraw.Draw(lay).arc(box, start, end, fill=fill, width=int(width))
        self.img.alpha_composite(lay)

    def text(self, xy, s, f, fill, anchor=None):
        self.d.text(xy, s, font=f, fill=fill, anchor=anchor)

    def tracked(self, xy, s, f, fill, spacing=1.2):
        x, y = xy
        for ch in s:
            self.d.text((x, y), ch, font=f, fill=fill)
            x += self.d.textlength(ch, font=f) + spacing

    def width(self, s, f):
        return self.d.textlength(s, font=f)

    def wrap(self, s, f, maxw):
        lines, cur = [], ""
        for word in s.split():
            candidate = (cur + " " + word).strip()
            if self.d.textlength(candidate, font=f) <= maxw:
                cur = candidate
            else:
                if cur:
                    lines.append(cur)
                cur = word
        if cur:
            lines.append(cur)
        return lines


def badge(p, xy, size, tint, glyph, f, alpha=26):
    x, y = xy
    p.rr((x, y, x + size, y + size), size * 0.32, fill=rgba(tint, alpha), outline=rgba(tint, 90))
    p.text((x + size / 2, y + size / 2 - 1), glyph, f, tint, anchor="mm")


def pill(p, xy, text, f, fg, bg, outline=None, pad=(9, 5)):
    x, y = xy
    w = int(p.width(text, f) + pad[0] * 2)
    h = int(f.size + pad[1] * 2)
    p.rr((x, y, x + w, y + h), h / 2, fill=bg, outline=outline)
    p.text((x + pad[0], y + pad[1] - 2), text, f, fg)
    return w, h


def panel(p, box, radius=24, fill="#131c25", outline=HAIR, glow=None):
    if glow:
        p.rr(box, radius, fill=None, outline=glow, width=2)
    p.rr(box, radius, fill=fill, outline=outline)


def button(p, box, text, tint=MINT, filled=True, fg="#04120f", size=11):
    x0, y0, x1, y1 = box
    if filled:
        p.rr(box, (y1 - y0) / 2, fill=tint)
        p.text(((x0 + x1) / 2, (y0 + y1) / 2 - 1), text, mono_b(size), fg, anchor="mm")
    else:
        p.rr(box, (y1 - y0) / 2, fill=rgba(tint, 24), outline=rgba(tint, 130))
        p.text(((x0 + x1) / 2, (y0 + y1) / 2 - 1), text, mono_b(size - 1), tint, anchor="mm")


def section(p, x, y, glyph, title, subtitle, tint=MINT, rule_to=None, glyph_size=12):
    badge(p, (x, y), 26, tint, glyph, mono_b(glyph_size))
    p.tracked((x + 36, y + 2), title, mono_b(11.5), T1, 1.0)
    p.tracked((x + 36, y + 18), subtitle, mono(8), T3, 0.9)
    if rule_to:
        p.line([(x + 36, y + 36), (rule_to, y + 36)], rgba(HAIR))


def status_bar(p, w):
    p.text((20, 14), "9:41", mono_b(11), T1)
    for i, hh in enumerate((5, 7, 9, 11)):
        p.rr((w - 96 + i * 6, 26 - hh, w - 92 + i * 6, 26), 1, fill=T2)
    p.text((w - 66, 14), "5G", mono(9), T2)
    p.rr((w - 52, 15, w - 20, 29), 4, outline=rgba(T2))
    p.rr((w - 50, 17, w - 30, 27), 2, fill=MINT)


def tab_bar(p, w, h):
    y0, y1 = h - 66, h - 24
    p.rr((16, y0, w - 16, y1), 21, fill=rgba(SURFACE, 235), outline=HAIR)
    items = [("\u25cf", "HOME", MINT), ("\u25a6", "PATCHES", T3), ("\u2726", "CLEAN", T3)]
    span = (w - 32) / 3
    for i, (glyph, label, tint) in enumerate(items):
        cx = 16 + span * i + span / 2
        p.text((cx - 24, y0 + 11), glyph, mono(11), tint, anchor="lm")
        p.text((cx - 10, y0 + 11), label, mono(9), tint, anchor="lm")


def logo(p, x, y, size=40):
    p.rr((x, y, x + size, y + size), size * 0.28, fill=MINT)
    for i, ww in enumerate((22, 15, 19)):
        yy = y + 11 + i * 8
        p.rr((x + 9, yy, x + 9 + ww, yy + 3), 2, fill="#04120f")
        p.ell((x + 9 + ww - 2, yy - 2, x + 13 + ww, yy + 5), fill="#04120f")


def home_top(p, w, h):
    status_bar(p, w)
    logo(p, 16, 44, 40)
    p.text((68, 46), "TRY STORE", sans_b(17), T1)
    p.tracked((68, 68), "MAX CONTROL", mono(7.5), MINT, 0.7)
    for i, glyph in enumerate(("\u25a4", "\u2699")):
        cx = w - 20 - 34 - i * 44
        p.ell((cx - 17, 51, cx + 17, 85), fill=rgba(RAISED, 220), outline=HAIR)
        p.text((cx, 68), glyph, mono(13), T1, anchor="mm")

    hx0, hy0, hx1, hy1 = 16, 100, w - 16, 336
    hero = vgrad((hx1 - hx0, hy1 - hy0), "#0f3e49", "#0b1218")
    sheen = Image.new("RGBA", hero.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    for i in range(hero.size[0]):
        band = max(0.0, 30.0 - abs(i - hero.size[0] * 0.44) * 0.30)
        sd.line([(i, 0), (i, hero.size[1])], fill=(255, 255, 255, int(band)))
    sheen = sheen.filter(ImageFilter.GaussianBlur(20))
    rounded = Image.new("L", hero.size, 0)
    ImageDraw.Draw(rounded).rounded_rectangle((0, 0, hero.size[0] - 1, hero.size[1] - 1), radius=30, fill=255)
    hero = Image.composite(hero, Image.new("RGBA", hero.size, (0, 0, 0, 0)), rounded)
    hero.alpha_composite(Image.composite(sheen, Image.new("RGBA", hero.size, (0, 0, 0, 0)), rounded))
    p.img.alpha_composite(hero, (hx0, hy0))
    p.rr((hx0, hy0, hx1, hy1), 30, outline=rgba(MINT, 92))

    p.rr((28, 118, 168, 142), 12, fill=(0, 0, 0, 118), outline=(255, 255, 255, 26))
    p.ell((38, 126, 46, 134), fill=MINT)
    p.tracked((58, 123), "SYSTEM READY", mono(9), T1, 0.8)

    p.text((34, 160), "YOUR PATCH", sans_b(23), T1)
    p.text((34, 186), "CONTROL CENTER", sans_b(23), T1)
    for i, line in enumerate(p.wrap("Manage modules, connections, and device health from one focused workspace.", sans(9.5), w - 96)[:3]):
        p.text((34, 222 + i * 13), line, sans(9.5), T2)
    button(p, (34, 266, 234, 300), "EXPLORE PATCH STUDIO", size=10)

    panel(p, (16, 352, w - 16, 588))
    ring = (36, 380, 128, 472)
    p.ell(ring, outline=rgba(HAIR, 255), width=9)
    p.arc(ring, 135, 390, MINT, 9)
    p.text((82, 416), "NOMINAL", mono_b(11), T1, anchor="mm")
    p.text((82, 433), "THERMAL", mono(7.5), T3, anchor="mm")
    section(p, 150, 366, "\u2248", "DEVICE VITALS", "LIVE SYSTEM STATE", rule_to=w - 34)
    rows = [("\u21bb", "LAUNCH COUNT", "42", MINT),
            ("\u2713", "EXPLOIT", "SUPPORTED", MINT),
            ("\u2605", "FAVORITES", "3", AMBER)]
    for i, (glyph, label, value, tint) in enumerate(rows):
        yy = 424 + i * 34
        p.text((152, yy), glyph, mono(11), tint)
        p.tracked((174, yy + 1), label, mono(8), T2, 0.6)
        p.text((w - 34, yy - 1), value, mono_b(10), T1, anchor="ra")
        if i < len(rows) - 1:
            p.line([(174, yy + 20), (w - 34, yy + 20)], rgba(HAIR, 130))

    panel(p, (16, 604, w - 16, 854), radius=26)
    section(p, 34, 622, "\u25a6", "MODULE STATUS", "LIVE DEVICE RECEIPTS", rule_to=w - 76)
    p.text((34, 668), "2", sans_b(30), T1)
    p.text((60, 682), "/ 5", mono_b(12), T3)
    pill(p, (w - 116, 672), "PATCHED", mono_b(8), MINT, rgba(MINT, 26), rgba(MINT, 100))
    for i in range(5):
        x0 = 34 + i * 56
        p.rr((x0, 712, x0 + 50, 717), 2, fill=MINT if i < 2 else rgba(HAIR, 220))
    for i, line in enumerate(p.wrap("Active modules are read straight from the device receipts, so Home and Patches can never disagree.", mono(8), w - 80)[:2]):
        p.text((34, 730 + i * 12), line, mono(8), T3)
    button(p, (34, 770, w - 34, 808), "OPEN PATCH STUDIO", size=10)


def home_lower(p, w, h):
    section(p, 16, 26, "\u25a6", "MODULE STATUS", "LIVE DEVICE RECEIPTS", rule_to=w - 56)
    p.text((34, 74), "2", sans_b(28), T1)
    p.text((58, 88), "/ 5", mono_b(12), T3)
    for i in range(5):
        x0 = 34 + i * 56
        p.rr((x0, 118, x0 + 50, 123), 2, fill=MINT if i < 2 else rgba(HAIR, 220))
    button(p, (34, 140, w - 34, 176), "OPEN PATCH STUDIO", size=10)

    top, bottom = 200, 548
    panel(p, (16, top, w - 16, bottom), radius=26, fill="#12212a", glow=rgba(MINT, 120))
    section(p, 34, top + 18, "\u25c9", "CONNECTIONS", "AIRLIFT AND VPN", rule_to=w - 76)
    pill(p, (w - 92, top + 20), "ON HOME", mono_b(8), "#04120f", AMBER)

    rows = [("\u2b1b", "AIRLIFT PAIRING", "Ready", MINT),
            ("\u25c8", "VPN TUNNEL", "Connected", MINT)]
    for i, (glyph, label, value, tint) in enumerate(rows):
        yy = top + 70 + i * 52
        badge(p, (34, yy), 36, tint, glyph, mono_b(13))
        p.tracked((82, yy + 4), label, mono(8.5), T2, 0.7)
        p.text((82, yy + 19), value, mono_b(12), tint)
        pill(p, (w - 106, yy + 9), "LIVE", mono_b(8), tint, rgba(tint, 26), rgba(tint, 100))

    button(p, (34, top + 180, w - 34, top + 218), "PAIR ON THIS IPHONE", size=10)
    for i, line in enumerate(p.wrap("Direct pairing on iOS 27; other versions import a pairing file.", mono(8), w - 80)[:2]):
        p.text((34, top + 234 + i * 12), line, mono(8), T3)
    button(p, (34, top + 276, 156, top + 312), "IMPORT PAIRING", tint=VIOLET, filled=False, size=10)
    button(p, (166, top + 276, w - 34, top + 312), "DELETE PAIRING", tint=CORAL, filled=False, size=10)

    for i, (glyph, title, detail) in enumerate((("\u25a6", "PATCHES", "Module library"), ("\u2318", "LOGS", "Support trail"))):
        x0 = 16 + i * ((w - 32) / 2 + 6)
        x1 = x0 + (w - 32) / 2 - 6
        panel(p, (x0, 568, x1, 664), radius=20)
        badge(p, (x0 + 14, 582), 34, MINT, glyph, mono_b(12))
        p.tracked((x0 + 58, 590), title, mono_b(9), T1, 0.8)
        p.text((x0 + 58, 606), detail, mono(8), T3)
        p.text((x1 - 20, 616), "\u203a", mono(15), T3)

    section(p, 16, 682, "\u25a3", "SYSTEM SNAPSHOT", "LIVE DEVICE HEALTH", rule_to=w - 56)
    tiles = (("iPhone 15 Pro", "MODEL"), ("iOS 18.7.10", "BUILD"),
             ("Nominal", "THERMAL"), ("Supported", "EXPLOIT"))
    for i, (value, label) in enumerate(tiles):
        col, row = i % 2, i // 2
        x0 = 16 + col * ((w - 32) / 2 + 6)
        x1 = x0 + (w - 32) / 2 - 6
        y0 = 720 + row * 56
        panel(p, (x0, y0, x1, y0 + 50), radius=16, fill="#111a22")
        p.tracked((x0 + 12, y0 + 10), label, mono(7.5), T3, 0.7)
        p.text((x0 + 12, y0 + 26), value, mono_b(10), T1)

    tab_bar(p, w, h)


def right_column(p, x, y, w):
    p.tracked((x, y), "WHAT THIS PASS CHANGED", mono_b(11), T3, 1.4)
    bullets = [
        "Airlift pairing and the VPN tunnel report on Home,",
        "on the surface the app opens on, not in Settings.",
        "One adaptive action: Open LocalDevVPN, Pair on this",
        "iPhone, or Stop pairing, decided by the tunnel state.",
        "Import and delete pairing moved with it, so the panel",
        "is complete without a trip into another tab.",
    ]
    for i, line in enumerate(bullets):
        p.text((x, y + 30 + i * 16), line, mono(9), T2)
    p.text((x, y + 30 + len(bullets) * 16), "28 strings, all five languages level.", mono(9), MINT)

    p.line([(x, y + 166), (x + w, y + 166)], rgba(HAIR))
    p.tracked((x, y + 186), "PANEL STATES", mono_b(11), T3, 1.4)
    states = [("tunnel down", "OPEN LOCALDEVPN", AMBER),
              ("tunnel up, iOS 27", "PAIR ON THIS IPHONE", MINT),
              ("pairing running", "STOP PAIRING", CORAL),
              ("pairing ready", "IMPORT / DELETE PAIRING", VIOLET)]
    for i, (state, action, tint) in enumerate(states):
        yy = y + 216 + i * 40
        p.rr((x, yy, x + w, yy + 32), 14, fill="#111a22", outline=HAIR)
        p.text((x + 12, yy + 11), state, mono(9), T2)
        pw = int(p.width(action, mono_b(8)) + 18)
        pill(p, (x + w - 12 - pw, yy + 7), action, mono_b(8), tint, rgba(tint, 26), rgba(tint, 120), (9, 4))

    p.line([(x, y + 394), (x + w, y + 394)], rgba(HAIR))
    p.tracked((x, y + 414), "SETTINGS KEEPS", mono_b(11), T3, 1.4)
    for i, line in enumerate(
        ("language  \u00b7  device  \u00b7  stats overlay",
         "reduce motion  \u00b7  licence  \u00b7  verified builds",
         "developer credit  \u00b7  done")):
        p.text((x, y + 444 + i * 17), line, mono(9), T2)

    p.line([(x, y + 512), (x + w, y + 512)], rgba(HAIR))
    for i, line in enumerate(
        ("The tunnel is polled every 5 s through",
         "LocalDevTunnelProbe, the same check the patch",
         "service trusts before it writes anything.")):
        p.text((x, y + 532 + i * 16), line, mono(9), T3)

    p.rr((x, y + 596, x + w, y + 656), 16, fill="#111a22", outline=rgba(AMBER, 90))
    for i, line in enumerate(
        ("Drawn from the design tokens in",
         "views/DesignSystem.swift. No Xcode in this",
         "runner, so it is a board, not a screenshot.")):
        p.text((x + 14, y + 610 + i * 14), line, mono(8.5), AMBER)


def main():
    W, H = 1250, 1010
    canvas = Image.new("RGBA", (W, H), rgba(CANVAS))
    p = Pen(canvas)
    p.tracked((44, 40), "HOME TAB  \u2014  AIRLIFT AND VPN CONNECTIONS", mono_b(11), T3, 2.0)
    p.tracked((44, 60), "TWO SCROLL POSITIONS OF THE SAME TAB  \u00b7  TOKENS FROM DESIGN SYSTEM", mono(8), HAIR, 1.6)

    pw, ph = 320, 900
    phone(canvas, 44, 92, pw, ph, home_top)
    phone(canvas, 388, 92, pw, ph, home_lower)
    p = Pen(canvas)
    p.tracked((44, 978), "HOME  \u00b7  TOP", mono(8.5), T3, 1.2)
    p.tracked((388, 978), "HOME  \u00b7  LOWER  \u2014  CONNECTIONS PANEL", mono(8.5), MINT, 1.2)
    right_column(p, 740, 92, 466)

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "home-connections.png")
    canvas.convert("RGB").save(out)
    print("wrote", out, canvas.size)


def phone(canvas, x, y, w, h, draw_content, radius=40):
    content = vgrad((w, h), "#0e161d", "#070a0e")
    orbs = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    od = ImageDraw.Draw(orbs)
    od.ellipse((-74, -46, 150, 178), fill=(86, 72, 235, 140))
    od.ellipse((w - 118, 150, w + 66, 350), fill=(31, 199, 193, 105))
    content = Image.alpha_composite(content, orbs.filter(ImageFilter.GaussianBlur(38)))
    draw_content(Pen(content), w, h)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    content.putalpha(ImageChops.multiply(content.getchannel("A"), mask))
    canvas.alpha_composite(content, (x, y))
    Pen(canvas).rr((x, y, x + w - 1, y + h - 1), radius, outline=rgba(HAIR), width=2)


if __name__ == "__main__":
    main()
