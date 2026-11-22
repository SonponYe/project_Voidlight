"""Builds the game's sound effects from the CC0 packs in the project root.

The packs are general-purpose (RPG / household / creature sounds), so the game
sounds are made by layering, pitching, filtering and reversing a few of their
samples. Run this to rebuild every file in assets/audio/sfx/ after editing a
recipe below:

    pip install numpy soundfile
    python tools/build_sfx.py

It reads the zips straight from the project root (they are git-ignored) and
writes small mono .ogg files, which ARE committed, so nobody else needs the
zips or this script just to play the game.
"""
import io
import os
import sys
import zipfile

import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
SR = 44100

PACKS = {
    "a": "100-CC0-SFX.zip",
    "b": "80-CC0-RPG-SFX.zip",
    "c": "80-CC0-creature-sfx-2.zip",
    "d": "sfx_100_v2.zip",
}
_zips = {}


def load(ref):
    """'a:shot_02' -> mono float array at SR from the matching pack."""
    key, name = ref.split(":")
    z = _zips.get(key)
    if z is None:
        z = _zips[key] = zipfile.ZipFile(os.path.join(ROOT, PACKS[key]))
    wanted = [n for n in z.namelist() if n.endswith("/" + name + ".ogg") or n == name + ".ogg"
              or n.endswith("sfx100v2_" + name + ".ogg")]
    if not wanted:
        sys.exit("sample not found: " + ref)
    data, rate = sf.read(io.BytesIO(z.read(wanted[0])))
    if data.ndim > 1:
        data = data.mean(axis=1)
    return resample(data, rate, SR)


def resample(x, src, dst):
    if src == dst:
        return x
    n = int(len(x) * dst / src)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)


def pitch(x, factor):
    """Plays faster (higher, shorter) when factor > 1, slower when < 1."""
    n = int(len(x) / factor)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)


def lowpass(x, hz):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    spec[freqs > hz] *= 0
    return np.fft.irfft(spec, len(x))


def highpass(x, hz):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    spec[freqs < hz] *= 0
    return np.fft.irfft(spec, len(x))


def db(x, amount):
    return x * (10 ** (amount / 20))


def trim(x, seconds):
    return x[: int(seconds * SR)]


def fade(x, fade_in=0.004, fade_out=0.03):
    x = x.copy()
    a, b = int(fade_in * SR), int(fade_out * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def mix(*layers):
    """Each layer is (samples, start_seconds)."""
    length = max(int(start * SR) + len(s) for s, start in layers)
    out = np.zeros(length)
    for s, start in layers:
        i = int(start * SR)
        out[i:i + len(s)] += s
    return out


def save(name, x, peak_db=-2.0):
    x = fade(x)
    peak = np.abs(x).max()
    if peak > 0:
        x = x * (10 ** (peak_db / 20) / peak)
    os.makedirs(OUT, exist_ok=True)
    sf.write(os.path.join(OUT, name + ".ogg"), x, SR, format="OGG", subtype="VORBIS")
    print("%-14s %.2fs" % (name, len(x) / SR))


def build():
    # --- gunfire: a bright crack on a low thump, three flavours ---
    save("shot_1", mix((pitch(load("a:shot_02"), 0.85), 0), (db(lowpass(load("a:slam_04"), 900), -3), 0)))
    save("shot_2", mix((trim(pitch(load("a:shot_01"), 0.9), 0.4), 0), (db(lowpass(load("a:slam_06"), 700), -4), 0)))
    save("shot_3", mix((pitch(load("a:shot_02"), 0.75), 0), (db(load("a:hit_02"), -2), 0.005)))
    # --- a shot landing on a wall: a short ping / chip ---
    save("impact_1", load("d:metal_hit_02"), -6)
    save("impact_2", trim(load("d:stones_03"), 0.3), -6)
    save("impact_3", load("d:wood_04"), -6)
    # --- being hit, and dying (no voices: heavy impacts, which suit every look) ---
    save("hurt_1", mix((load("a:hit_03"), 0), (db(load("a:hit_01"), -4), 0.01)))
    save("hurt_2", mix((load("d:hit_01"), 0), (db(load("d:hit_02"), -3), 0.01)))
    save("hurt_3", mix((load("a:hit_04"), 0), (db(lowpass(load("c:stomp_01"), 300), -2), 0)))
    save("death", mix((pitch(load("c:stomp_01"), 0.9), 0), (db(load("d:metal_hit_01"), -4), 0.05),
                      (db(lowpass(load("a:slam_03"), 800), -3), 0.02)))
    # --- bomb ---
    save("explosion", mix((load("a:explosion"), 0), (db(pitch(load("c:stomp_01"), 0.6), 3), 0),
                          (db(lowpass(pitch(load("a:slam_02"), 0.7), 600), 0), 0.03),
                          (db(load("b:spell_fire_07"), 10), 0.08)), -1.0)
    save("bomb_place", mix((load("a:key_open_01"), 0), (db(load("a:switch_02"), -3), 0.12)), -8)
    # --- Gens ---
    save("shield_on", load("b:spell_01"), -6)
    save("shield_break", mix((load("d:glass_02"), 0), (load("d:glass_05"), 0.04), (db(load("d:metal_06"), -4), 0.02)), -3)
    cloak = fade(lowpass(db(load("d:air_02"), 0), 3500), 0.15, 0.4)
    save("camo_on", cloak, -9)
    save("camo_off", cloak[::-1], -9)
    save("haunt", mix((load("a:weird_02"), 0), (db(load("a:weird_04"), -2), 0.1)), -6)
    save("decoy", mix((load("a:plop_01"), 0), (db(load("b:spell_02"), -3), 0.05)), -7)
    lights = mix((load("d:switch_01"), 0), (db(load("a:machine_03"), 2), 0.05))
    save("blackout_off", lights, -4)  # the power coming back: click, then a hum spinning up
    save("blackout_on", lights[::-1], -4)  # ...and going out is the same, backwards
    # --- match flow ---
    save("start", mix((load("a:gong_01"), 0), (db(lowpass(load("c:stomp_01"), 200), -4), 0)), -3)
    save("win", mix((load("a:bell_03"), 0), (db(load("b:item_gem_04"), -2), 0.18), (db(load("b:item_coins_03"), -5), 0.36)), -3)
    save("defeat", lowpass(pitch(load("a:gong_02"), 0.7), 2500), -5)
    # --- interface ---
    save("ui_click", load("d:switch_01"), -6)
    save("ui_confirm", mix((load("b:lock_02"), 0), (db(load("d:switch_02"), -3), 0.07)), -6)
    save("ui_back", pitch(load("d:switch_02"), 0.85), -7)
    # --- footsteps on rubble: dry steps, pitched to vary ---
    for i, (ref, p) in enumerate([("d:footstep_01", 1.0), ("d:footstep_02", 1.0), ("d:footstep_01", 0.88), ("d:footstep_02", 1.12)], 1):
        save("step_%d" % i, highpass(pitch(load(ref), p), 120), -6)
    # --- pickups and low-health warnings ---
    save("empty", mix((db(pitch(load("d:switch_01"), 0.7), 0), 0), (db(load("d:metal_hit_02"), -10), 0.01)), -6)
    save("pickup", mix((load("b:item_gem_02"), 0), (db(load("d:items_01"), -8), 0.05)), -6)
    save("heal", mix((load("b:item_gem_04"), 0), (db(pitch(load("b:spell_02"), 1.1), -4), 0.08)), -4)
    save("gen_pickup", mix((load("b:item_gem_03"), 0), (db(load("b:spell_01"), -3), 0.06)), -4)
    save_heartbeat("heartbeat")
    save_dread("dread")
    # --- the world: a low wind bed that loops, and far-off thuds of artillery ---
    save_stereo_loop("ambient", "d:loop_ambient_04")
    save("rumble", fade(lowpass(pitch(load("d:thunder_01"), 0.8), 450), 0.6, 1.2), -4)


def save_heartbeat(name):
    """A synthesised two-beat heartbeat (lub-dub), exactly one loop long."""
    length = 0.9
    t = np.arange(int(length * SR)) / SR
    out = np.zeros_like(t)
    for start, amp in ((0.0, 1.0), (0.28, 0.7)):
        u = np.clip(t - start, 0, None)
        env = (1 - np.exp(-u / 0.004)) * np.exp(-u / 0.06) * (t >= start)
        freq = 42 + 28 * np.exp(-u / 0.05)  # a thump that drops in pitch
        out += amp * env * np.sin(2 * np.pi * np.cumsum(freq) / SR)
    save(name, out, -3)


def save_dread(name):
    """A low, slowly pulsing drone, built so its end joins its start (every
    frequency is a whole number of cycles in the 8 second loop)."""
    length = 8.0
    t = np.arange(int(length * SR)) / SR
    out = np.zeros_like(t)
    for freq, amp in ((55.0, 1.0), (55.5, 0.7), (82.5, 0.35), (110.25, 0.2), (164.75, 0.08)):
        out += amp * np.sin(2 * np.pi * freq * t)
    out *= 0.65 + 0.35 * np.sin(2 * np.pi * 0.25 * t)
    peak = 10 ** (-6 / 20) / np.abs(out).max()
    os.makedirs(OUT, exist_ok=True)
    sf.write(os.path.join(OUT, name + ".ogg"), out * peak, SR, format="OGG", subtype="VORBIS")
    print("%-14s %.2fs (loops)" % (name, length))


def save_stereo_loop(name, ref):
    key, short = ref.split(":")
    z = _zips.get(key) or zipfile.ZipFile(os.path.join(ROOT, PACKS[key]))
    member = [n for n in z.namelist() if n.endswith("sfx100v2_" + short + ".ogg")][0]
    data, rate = sf.read(io.BytesIO(z.read(member)))
    data = data * (10 ** (-18 / 20) / np.abs(data).max())  # a quiet bed; the game adds its own volume on top
    sf.write(os.path.join(OUT, name + ".ogg"), data, rate, format="OGG", subtype="VORBIS")
    print("%-14s %.2fs (loops)" % (name, len(data) / rate))


if __name__ == "__main__":
    build()
