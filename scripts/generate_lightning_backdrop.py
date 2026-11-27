#!/usr/bin/env python3
"""Render the blue lightning backdrop and mux the original storm audio.

The source storm recording has real thunder peaks at roughly 2.2, 4.5, 7.1,
11.1, 13.4 and 15.5 seconds. The strikes below are placed on those beats so the
visual flash and the audio transient arrive together.

Run from the repository root:

    python scripts/generate_lightning_backdrop.py

The rendered film is written to artifacts/lightning/. Copy it into the asset
catalogue only after inspecting the preview frames and the still.
"""

from __future__ import annotations

import math
import random
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts" / "lightning"
FRAMES = OUT / "frames"
SOURCE = ROOT / "artifacts" / "stormloop" / "StormLoop.mp4"

WIDTH = 1080
HEIGHT = 1920
FPS = 30
DURATION = 17.2
FRAME_COUNT = round(DURATION * FPS)

# Times are the loudest thunder beats in the source recording.
STRIKE_TIMES = [
    (2.22, 0.30, 1.00),
    (4.52, 0.72, 0.82),
    (7.09, 0.50, 1.12),
    (11.05, 0.18, 0.94),
    (13.43, 0.84, 1.00),
    (15.50, 0.62, 0.62),
]


def sky_gradient() -> Image.Image:
    stops = [
        (0.00, (2, 7, 17)),
        (0.36, (3, 20, 42)),
        (0.68, (5, 38, 70)),
        (1.00, (2, 13, 28)),
    ]
    positions = [stop[0] for stop in stops]
    ys = np.linspace(0, 1, HEIGHT)
    channels = [
        np.interp(ys, positions, [stop[1][channel] for stop in stops])
        for channel in range(3)
    ]
    arr = np.stack(channels, axis=-1)
    arr = np.repeat(arr[:, None, :], WIDTH, axis=1)
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB")


def radial_glow(
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    color: tuple[int, int, int],
    power: float = 2.0,
) -> Image.Image:
    yy, xx = np.mgrid[0:HEIGHT, 0:WIDTH]
    distance = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    alpha = np.clip(1.0 - distance, 0.0, 1.0) ** power
    arr = np.asarray(color, dtype=np.float32)[None, None, :] * alpha[..., None]
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB")


def cloud_texture(seed: int) -> Image.Image:
    rng = np.random.default_rng(seed)
    base_h, base_w = 240, 390
    acc = np.zeros((base_h, base_w), dtype=np.float32)
    amplitude = 1.0
    total = 0.0
    for octave in range(5):
        h = max(6, base_h // (2**octave))
        w = max(8, base_w // (2**octave))
        noise = rng.random((h, w)).astype(np.float32)
        scaled = Image.fromarray((noise * 255).astype(np.uint8)).resize(
            (base_w, base_h), Image.Resampling.BICUBIC
        )
        acc += amplitude * (np.asarray(scaled, dtype=np.float32) / 255.0)
        total += amplitude
        amplitude *= 0.55
    acc /= max(total, 1e-6)
    acc = (acc - acc.min()) / max(float(acc.max() - acc.min()), 1e-6)
    acc = np.clip((acc - 0.22) / 0.78, 0.0, 1.0) ** 1.35

    ys = np.linspace(0.0, 1.0, base_h)[:, None]
    envelope = 0.38 + 0.62 * np.exp(-((ys - 0.34) / 0.48) ** 2)
    acc *= envelope

    texture = Image.fromarray((acc * 255).astype(np.uint8)).resize(
        (WIDTH, HEIGHT), Image.Resampling.BICUBIC
    )
    texture = texture.filter(ImageFilter.GaussianBlur(11))
    values = np.asarray(texture, dtype=np.float32) / 255.0
    rgb = np.stack(
        [
            values * 14.0,
            values * 42.0,
            values * 76.0,
        ],
        axis=-1,
    )
    return Image.fromarray(rgb.clip(0, 255).astype(np.uint8), "RGB")


def rain_texture(seed: int) -> Image.Image:
    rng = random.Random(seed)
    layer = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for _ in range(760):
        x = rng.uniform(-WIDTH * 0.15, WIDTH * 1.15)
        y = rng.uniform(-40, HEIGHT)
        length = rng.uniform(16, 64)
        alpha = rng.randint(7, 22)
        draw.line(
            [(x, y), (x - length * 0.22, y + length)],
            fill=(168, 210, 255, alpha),
            width=1,
        )
    return layer


def vignette() -> Image.Image:
    yy, xx = np.mgrid[0:HEIGHT, 0:WIDTH]
    distance = np.sqrt(
        ((xx - WIDTH * 0.50) / (WIDTH * 0.82)) ** 2
        + ((yy - HEIGHT * 0.52) / (HEIGHT * 0.82)) ** 2
    )
    mask = 1.0 - 0.52 * np.clip(distance - 0.28, 0.0, 1.0) ** 1.20
    arr = np.repeat((mask * 255).astype(np.uint8)[:, :, None], 3, axis=2)
    return Image.fromarray(arr, "RGB")


def make_main_bolt(
    rng: random.Random,
    start: tuple[float, float],
    end: tuple[float, float],
    segments: int = 18,
    jitter: float = 0.020,
) -> list[tuple[float, float]]:
    """A downward-only jagged channel: y always advances, so it cannot loop."""
    points = [start]
    for index in range(1, segments):
        t = index / segments
        points.append(
            (
                start[0]
                + (end[0] - start[0]) * t
                + rng.gauss(0.0, jitter) * (0.45 + 0.55 * t),
                start[1] + (end[1] - start[1]) * t,
            )
        )
    points.append(end)
    return points


def make_branch(
    rng: random.Random,
    origin: tuple[float, float],
    side: float,
    length: float,
    steps: int = 5,
) -> list[tuple[float, float]]:
    """Short forked channels also travel downward, away from the main channel."""
    points = [origin]
    x, y = origin
    for _ in range(steps):
        x += side * (length / steps) + rng.gauss(0.0, 0.004)
        y += (length * 0.82) / steps + rng.gauss(0.0, 0.003)
        points.append((x, y))
    return points


def make_strike(rng: random.Random, time: float, x: float, strength: float) -> dict:
    start = (x, -0.03)
    end = (x + rng.uniform(-0.10, 0.10), rng.uniform(0.54, 0.72))
    main = make_main_bolt(rng, start, end)
    branches = []
    for _ in range(3):
        idx = rng.randint(max(3, len(main) // 5), max(4, len(main) * 3 // 4))
        origin = main[idx]
        branches.append(
            make_branch(
                rng,
                origin,
                rng.choice([-1.0, 1.0]),
                rng.uniform(0.065, 0.145),
            )
        )
    return {"time": time, "strength": strength, "main": main, "branches": branches}


def strike_curve(dt: float) -> float:
    if dt < 0.0 or dt > 0.70:
        return 0.0
    if dt < 0.025:
        return dt / 0.025
    if dt < 0.080:
        return 1.0
    if dt < 0.140:
        return 0.42
    if dt < 0.205:
        return 0.98
    return max(0.0, math.exp(-(dt - 0.205) * 7.0))


def stamp_strike(base: Image.Image, strike: dict, intensity: float) -> Image.Image:
    scale = 4
    low = Image.new("RGB", (WIDTH // scale, HEIGHT // scale), (0, 0, 0))
    draw = ImageDraw.Draw(low)
    main_points = [(x * WIDTH / scale, y * HEIGHT / scale) for x, y in strike["main"]]
    draw.line(main_points, fill=(44, 185, 255), width=3, joint="curve")
    for branch in strike["branches"]:
        points = [(x * WIDTH / scale, y * HEIGHT / scale) for x, y in branch]
        draw.line(points, fill=(18, 82, 128), width=1, joint="curve")
    low = low.filter(ImageFilter.GaussianBlur(5))
    glow = low.resize((WIDTH, HEIGHT), Image.Resampling.BILINEAR)

    core = Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0))
    core_draw = ImageDraw.Draw(core)
    core_draw.line(
        [(x * WIDTH, y * HEIGHT) for x, y in strike["main"]],
        fill=(222, 248, 255),
        width=2,
        joint="curve",
    )
    for branch in strike["branches"]:
        core_draw.line(
            [(x * WIDTH, y * HEIGHT) for x, y in branch],
            fill=(146, 207, 238),
            width=1,
            joint="curve",
        )

    amount = max(0.0, min(1.0, intensity))
    glow = Image.blend(Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0)), glow, amount)
    core = Image.blend(Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0)), core, amount)
    base = ImageChops.add(base, glow)
    return ImageChops.add(base, core)


def build_frame(
    time: float,
    strikes: list[dict],
    sky: Image.Image,
    clouds: list[Image.Image],
    rain: Image.Image,
    horizon: Image.Image,
    mask: Image.Image,
) -> Image.Image:
    base = sky.copy()
    base = ImageChops.add(base, ImageChops.offset(clouds[0], int(time * 11) % WIDTH, 0))
    base = ImageChops.add(base, ImageChops.offset(clouds[1], int(-time * 7) % WIDTH, 0))
    base = ImageChops.add(base, horizon)
    base = Image.alpha_composite(
        base.convert("RGBA"), ImageChops.offset(rain, int(time * 42) % WIDTH, 0)
    ).convert("RGB")

    active: list[tuple[dict, float]] = []
    flash = 0.0
    for strike in strikes:
        dt = time - strike["time"]
        amount = strike_curve(dt)
        if amount <= 0.015:
            continue
        active.append((strike, amount))
        flash = max(flash, amount * strike["strength"])

    if flash > 0.01:
        blue_flash = Image.new("RGB", (WIDTH, HEIGHT), (34, 106, 160))
        base = Image.blend(base, blue_flash, min(0.23, flash * 0.20))

    for strike, amount in active:
        base = stamp_strike(base, strike, amount * strike["strength"])

    return ImageChops.multiply(base, mask)


def extract_audio() -> Path:
    audio = OUT / "storm-audio-48k.wav"
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(SOURCE),
            "-vn",
            "-ac",
            "2",
            "-ar",
            "48000",
            str(audio),
        ],
        check=True,
    )
    return audio


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    FRAMES.mkdir(parents=True, exist_ok=True)
    for old in FRAMES.glob("*.jpg"):
        old.unlink()

    print("preparing sky, clouds, rain and lightning paths…")
    sky = sky_gradient()
    clouds = [cloud_texture(1701), cloud_texture(90210)]
    rain = rain_texture(4411)
    horizon = radial_glow(WIDTH * 0.52, HEIGHT * 0.70, WIDTH * 0.95, HEIGHT * 0.30, (7, 63, 108), 2.4)
    mask = vignette()

    strikes = [
        make_strike(random.Random(int(time * 1000) + 7), time, x, strength)
        for time, x, strength in STRIKE_TIMES
    ]

    print(f"rendering {FRAME_COUNT} frames at {WIDTH}x{HEIGHT}…")
    for index in range(FRAME_COUNT):
        time = index / FPS
        frame = build_frame(time, strikes, sky, clouds, rain, horizon, mask)
        frame.save(FRAMES / f"{index:04d}.jpg", quality=92, subsampling=2, optimize=False)
        if index % 30 == 0:
            print(f"  {index:04d}/{FRAME_COUNT}")

    still_time = STRIKE_TIMES[2][0] + 0.045
    still = build_frame(still_time, strikes, sky, clouds, rain, horizon, mask)
    still.save(OUT / "StormLoopStill.jpg", quality=93, subsampling=2, optimize=False)

    audio = extract_audio()
    video = OUT / "LightningBackdrop.mp4"
    print("encoding video with the original storm audio…")
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-framerate",
            str(FPS),
            "-i",
            str(FRAMES / "%04d.jpg"),
            "-i",
            str(audio),
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            "21",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "160k",
            "-shortest",
            "-movflags",
            "+faststart",
            str(video),
        ],
        check=True,
    )
    print(f"video: {video}")
    print(f"still: {OUT / 'StormLoopStill.jpg'}")


if __name__ == "__main__":
    main()
