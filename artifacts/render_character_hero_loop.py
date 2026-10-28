"""Bake the rotating character onto a TryStore stage.

Source : artifacts/.hero-cutouts/frame_XXXX.png  (298 RGBA cutouts, 600x900)
Output : ThreeOneOSFive/CharacterHeroLoop.mp4     (silent, loops in AVPlayerLooper)
         ThreeOneOSFive/Assets.xcassets/CharacterHeroStage.imageset/*.jpg
         artifacts/character-hero-preview.mp4     (same bytes, for the browser preview)

Stage colours come from the app palette so the hero backdrop sits on the project's
own tokens: canvas #000000, logo blue #2A87D9 (AppPalette.brand).
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
CUTOUTS = ROOT / "artifacts" / ".hero-cutouts"
APP = ROOT / "ThreeOneOSFive"
VIDEO_OUT = APP / "CharacterHeroLoop.mp4"
POSTER_SET = APP / "Assets.xcassets" / "CharacterHeroStage.imageset"
PREVIEW_OUT = ROOT / "artifacts" / "character-hero-preview.mp4"

W, H = 1080, 1440
FPS = 23.976  # 298 cutouts cover the 12.43 s source clip

# The source turntable never returns to its opening pose, so the loop is trimmed to
# the pose pair that matches best (IoU 0.82 across 245 frames) and the wrap is
# cross-faded; without that the cycle would jump every ten seconds.
LOOP_START = 53
LOOP_END = 297
CROSSFADE = 16
POSTER_INDEX = 74

CANVAS = (0, 0, 0)          # AppPalette.canvas
BRAND = (42, 135, 217)      # AppPalette.brand
NAVY = (11, 30, 61)

CHAR_CENTER_X = 0.615
CHAR_BOTTOM_Y = 0.94
CHAR_HEIGHT = 0.76

EMBLEM_CENTER = (0.615, 0.345)
EMBLEM_DIAMETER = 0.52
RING_DIAMETER = 0.62

SCALE = 4  # supersample factor for the mask edges


def radial(size, center, radius, peak):
    """Soft radial falloff, returned as float alpha in 0..peak."""
    w, h = size
    ys = (np.arange(h, dtype=np.float32)[:, None] - center[1]) / radius
    xs = (np.arange(w, dtype=np.float32)[None, :] - center[0]) / radius
    d = np.sqrt(xs * xs + ys * ys)
    return np.clip(1.0 - d, 0.0, 1.0) ** 1.8 * peak


def over(base: np.ndarray, colour, alpha: np.ndarray) -> np.ndarray:
    """Alpha-composite a flat colour onto an RGB float array."""
    a = alpha[..., None]
    return base * (1.0 - a) + np.array(colour, dtype=np.float32) * a


def circle_mask(diameter, soft=0.0):
    """Anti-aliased circle mask at 1x, drawn supersampled."""
    px = int(round(diameter))
    big = Image.new("L", (px * SCALE, px * SCALE), 0)
    ImageDraw.Draw(big).ellipse((0, 0, px * SCALE - 1, px * SCALE - 1), fill=255)
    mask = big.resize((px, px), Image.LANCZOS)
    if soft:
        mask = mask.filter(ImageFilter.GaussianBlur(soft))
    return mask


def ring_mask(diameter, width):
    """Anti-aliased circle outline at 1x."""
    px = int(round(diameter))
    big = Image.new("L", (px * SCALE, px * SCALE), 0)
    ImageDraw.Draw(big).ellipse(
        (0, 0, px * SCALE - 1, px * SCALE - 1), outline=255, width=int(round(width * SCALE))
    )
    return big.resize((px, px), Image.LANCZOS)


def paste(base: np.ndarray, rgba: np.ndarray, left: int, top: int) -> None:
    """Composite an RGBA patch into the float RGB canvas in place."""
    h, w = rgba.shape[:2]
    a = (rgba[:, :, 3:4].astype(np.float32) / 255.0)
    rgb = rgba[:, :, :3].astype(np.float32)
    region = base[top : top + h, left : left + w]
    base[top : top + h, left : left + w] = region * (1.0 - a) + rgb * a


def build_stage(feet_y: int) -> np.ndarray:
    """Static stage: black base, navy pool, logo-blue bloom, emblem, scrims."""
    base = np.zeros((H, W, 3), dtype=np.float32)
    base[:, :] = CANVAS

    px = W * CHAR_CENTER_X
    base = over(base, NAVY, radial((W, H), (px, H * 0.52), W * 0.62, 0.62))
    base = over(base, BRAND, radial((W, H), (px, H * 0.50), W * 0.58, 0.15))

    # Vertical falloff so the bottom edge returns to black.
    bottom = np.clip((np.arange(H, dtype=np.float32) / H - 0.55) / 0.45, 0.0, 1.0) ** 1.5 * 0.55
    base = base * (1.0 - bottom[:, None, None])

    # Logo emblem, dim and slightly soft so it reads as a watermark.
    emblem_px = int(W * EMBLEM_DIAMETER)
    icon = Image.open(APP / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png")
    icon = icon.convert("RGB").resize((emblem_px, emblem_px), Image.LANCZOS)
    emblem = np.dstack([np.array(icon, dtype=np.float32)])
    mask = np.array(circle_mask(emblem_px, soft=emblem_px * 0.012), dtype=np.float32) / 255.0 * 0.17
    ex = int(round(W * EMBLEM_CENTER[0] - emblem_px / 2))
    ey = int(round(H * EMBLEM_CENTER[1] - emblem_px / 2))
    todo = base[ey : ey + emblem_px, ex : ex + emblem_px]
    alpha = mask[..., None]
    base[ey : ey + emblem_px, ex : ex + emblem_px] = todo * (1.0 - alpha) + emblem * alpha

    # Two thin rings around it, in the accent only.
    ring_px = int(W * RING_DIAMETER)
    rx = int(round(W * EMBLEM_CENTER[0] - ring_px / 2))
    ry = int(round(H * EMBLEM_CENTER[1] - ring_px / 2))
    outer = np.array(ring_mask(ring_px, 2.6), dtype=np.float32) / 255.0 * 0.30
    layer = np.zeros((H, W, 1), dtype=np.float32)
    layer[ry : ry + ring_px, rx : rx + ring_px, 0] = outer
    inner_px = int(ring_px - W * 0.032)
    ix = int(round(W * EMBLEM_CENTER[0] - inner_px / 2))
    iy = int(round(H * EMBLEM_CENTER[1] - inner_px / 2))
    inner = np.array(ring_mask(inner_px, 1.4), dtype=np.float32) / 255.0 * 0.07
    layer[iy : iy + inner_px, ix : ix + inner_px, 0] = np.maximum(
        layer[iy : iy + inner_px, ix : ix + inner_px, 0],
        inner * 1.0,
    )
    ring_alpha = layer[:, :, 0]
    base = over(base, BRAND, ring_alpha)

    # Left scrim: the hero headline and CTA sit on this side.
    xs = np.arange(W, dtype=np.float32) / W
    scrim = np.clip(1.0 - xs / 0.60, 0.0, 1.0) ** 1.35 * 0.82
    base = base * (1.0 - scrim[None, :, None])

    # Ground: a hairline and pooled light under the feet.
    ground = np.zeros((H, W), dtype=np.float32)
    ground = np.maximum(ground, radial((W, H), (px, feet_y), W * 0.30, 0.20))
    base = over(base, BRAND, ground)
    line = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(line)
    d.rectangle((int(W * 0.34), feet_y, int(W * 0.89), feet_y + 1), fill=110)
    base = over(base, BRAND, np.array(line, dtype=np.float32) / 255.0)

    return base


def main() -> None:
    frames = sorted(CUTOUTS.glob("frame_*.png"))
    if not frames:
        raise SystemExit("no cutouts found")
    if not (0 <= LOOP_START < POSTER_INDEX <= LOOP_END < len(frames)):
        raise SystemExit("loop range or poster index outside the cutout sequence")

    # One crop window for every frame keeps the figure steady through the turn.
    boxes = []
    for f in frames:
        a = np.array(Image.open(f).convert("RGBA"))[:, :, 3]
        ys, xs = np.where(a > 40)
        boxes.append((xs.min(), ys.min(), xs.max(), ys.max()))
    x0 = min(b[0] for b in boxes)
    y0 = min(b[1] for b in boxes)
    x1 = max(b[2] for b in boxes)
    y1 = max(b[3] for b in boxes)
    pad = 8
    crop = (max(0, x0 - pad), max(0, y0 - pad), x1 + pad + 1, y1 + pad + 1)

    char_h = int(H * CHAR_HEIGHT)
    char_w = int(round(char_h * (crop[2] - crop[0]) / (crop[3] - crop[1])))
    top = int(round(H * CHAR_BOTTOM_Y)) - char_h
    left = int(round(W * CHAR_CENTER_X - char_w / 2))
    print(f"cutouts={len(frames)} crop={crop} paste=({left},{top}) size=({char_w}x{char_h})")

    stage = build_stage(feet_y=int(round(H * CHAR_BOTTOM_Y)) + 4)

    sample_mode = "--samples" in __import__("sys").argv
    if sample_mode:
        for idx in (LOOP_START, POSTER_INDEX, 149, 223, LOOP_END):
            patch = Image.open(frames[idx]).convert("RGBA").crop(crop).resize(
                (char_w, char_h), Image.LANCZOS
            )
            canvas = stage.copy()
            paste(canvas, np.array(patch, dtype=np.uint8), left, top)
            Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8)).save(
                ROOT / "artifacts" / f".stage-sample-{idx:04d}.png"
            )
        print("sample frames written")
        return

    loop = frames[LOOP_START : LOOP_END + 1]
    print(f"loop frames {LOOP_START}..{LOOP_END} ({len(loop)}) crossfade {CROSSFADE}")

    ffmpeg = os.environ.get("FFMPEG_EXE")
    if not ffmpeg:
        import imageio_ffmpeg

        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    encode = subprocess.Popen(
        [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", "24000/1001",
            "-i", "-",
            "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "20",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            str(VIDEO_OUT),
        ],
        stdin=subprocess.PIPE,
    )
    assert encode.stdin is not None
    poster_written = False
    head: list[np.ndarray] = []
    total = len(loop)
    for index, f in enumerate(loop):
        patch = Image.open(f).convert("RGBA").crop(crop).resize((char_w, char_h), Image.LANCZOS)
        canvas = stage.copy()
        paste(canvas, np.array(patch, dtype=np.uint8), left, top)
        out = np.clip(canvas, 0, 255).astype(np.uint8)

        if index < CROSSFADE:
            head.append(out)
        if index >= total - CROSSFADE:
            # Blend the tail back into the opening frames so the wrap is graded, not cut.
            weight = (index - (total - CROSSFADE) + 1) / (CROSSFADE + 1)
            out = ((1.0 - weight) * out.astype(np.float32)
                   + weight * head[index - (total - CROSSFADE)].astype(np.float32))
            out = np.clip(out, 0, 255).astype(np.uint8)

        encode.stdin.write(out.tobytes())
        if index == POSTER_INDEX - LOOP_START:
            poster = Image.fromarray(out)
            poster.save(POSTER_SET / "character-hero-stage.jpg", quality=94)
            poster.resize((540, 720), Image.LANCZOS).save(
                ROOT / "artifacts" / "character-hero-poster.png"
            )
            poster_written = True
    encode.stdin.close()
    if encode.wait() != 0:
        raise SystemExit("ffmpeg encode failed")
    assert poster_written
    PREVIEW_OUT.write_bytes(VIDEO_OUT.read_bytes())
    print(f"wrote {VIDEO_OUT} ({VIDEO_OUT.stat().st_size} bytes) and the poster")


if __name__ == "__main__":
    main()
