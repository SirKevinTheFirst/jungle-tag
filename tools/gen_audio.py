#!/usr/bin/env python3
"""Synthesizes every sound effect, ambience loop and the music loop used by Jungle Tag.

All audio is original and generated from scratch, so the project has no licensing
strings attached. Run from the project root:  python3 tools/gen_audio.py
Requires numpy. Output goes to res://audio/*.wav (16-bit mono).
"""
import os
import wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio")
rng = np.random.default_rng(1234)


def save(name, sig, sr=SR, peak=0.9):
    sig = np.asarray(sig, dtype=np.float64)
    m = np.max(np.abs(sig)) or 1.0
    sig = sig / m * peak
    data = (np.clip(sig, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())


def t_axis(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def shaped_noise(n, lo, hi, sr=SR, tilt=0.0):
    """Circular FFT band-limited noise. Because the filter is circular, the result loops seamlessly."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / sr)
    mask = ((f >= lo) & (f <= hi)).astype(float)
    # soft edges
    mask = np.convolve(mask, np.hanning(31) / np.hanning(31).sum(), mode="same")
    if tilt:
        mask *= (np.maximum(f, 20) / 1000.0) ** tilt
    return np.fft.irfft(spec * mask, n)


def env_adsr(n, a=0.01, d=0.1, s=0.6, r=0.2, sr=SR):
    a_n, d_n, r_n = int(a * sr), int(d * sr), int(r * sr)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, a_n, endpoint=False),
        np.linspace(1, s, d_n, endpoint=False),
        np.full(s_n, s),
        np.linspace(s, 0, r_n),
    ])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def exp_env(n, decay, sr=SR):
    return np.exp(-np.arange(n) / sr / decay)


def sweep(f0, f1, dur, sr=SR, curve=1.0):
    t = t_axis(dur, sr)
    k = (t / dur) ** curve
    freq = f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(freq) / sr)


def place(buf, sig, start):
    s = int(start)
    e = min(len(buf), s + len(sig))
    if e > s:
        buf[s:e] += sig[: e - s]


def place_wrap(buf, sig, start):
    """Adds sig into buf wrapping around the end, used to keep loops seamless."""
    n = len(buf)
    idx = (np.arange(len(sig)) + int(start)) % n
    np.add.at(buf, idx, sig)


# ----------------------------------------------------------------- birds
def bird_chirp(kind):
    if kind == 0:  # quick double chirp
        parts = []
        for f in (3200, 3600):
            c = sweep(f, f * 1.6, 0.07, curve=0.6) * env_adsr(int(0.07 * SR), 0.005, 0.02, 0.7, 0.03)
            parts += [c, np.zeros(int(0.05 * SR))]
        return np.concatenate(parts)
    if kind == 1:  # descending whistle
        d = 0.45
        t = t_axis(d)
        f = 2600 - 1200 * (t / d) + 120 * np.sin(2 * np.pi * 18 * t)
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * env_adsr(len(t), 0.02, 0.1, 0.8, 0.15)
    if kind == 2:  # trill
        d = 0.6
        t = t_axis(d)
        f = 4200 + 600 * np.sin(2 * np.pi * 28 * t)
        am = 0.5 + 0.5 * np.sin(2 * np.pi * 28 * t)
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * am * env_adsr(len(t), 0.03, 0.1, 0.8, 0.2)
    # kind 3: toucan-like croak
    d = 0.28
    t = t_axis(d)
    f = 520 + 80 * np.sin(2 * np.pi * 9 * t)
    s = sum(np.sin(2 * np.pi * np.cumsum(f * h) / SR) / h for h in range(1, 7))
    return s * env_adsr(len(t), 0.01, 0.05, 0.8, 0.1) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 30 * t)))


def jungle_ambience():
    dur = 24.0
    n = int(dur * SR)
    buf = np.zeros(n)
    # cicada / insect bed: modulated high band noise
    bed = shaped_noise(n, 4500, 7500)
    t = np.arange(n) / SR
    mod = 0.55 + 0.45 * np.sin(2 * np.pi * (2.0 * t)) * np.sin(2 * np.pi * t / dur * 3)  # integer cycles -> loops
    buf += bed * mod * 0.25
    # crickets: pulsed sine
    cr = np.sin(2 * np.pi * 5200 * t) * (np.sin(2 * np.pi * 30 * t) > 0.6) * 0.06
    cr *= 0.5 + 0.5 * np.sin(2 * np.pi * t / dur * 2)
    buf += cr
    # soft low forest wash
    buf += shaped_noise(n, 80, 600) * 0.25
    # distant birds sprinkled
    for i in range(26):
        b = bird_chirp(int(rng.integers(0, 4))) * rng.uniform(0.05, 0.22)
        place_wrap(buf, b, rng.uniform(0, n))
    return buf


def wind_loop():
    dur = 16.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    w = shaped_noise(n, 120, 1400, tilt=-0.6)
    gust = 0.45 + 0.35 * np.sin(2 * np.pi * t / dur * 2) + 0.2 * np.sin(2 * np.pi * t / dur * 5 + 1)
    rustle = shaped_noise(n, 2000, 6000) * (shaped_noise(n, 0.5, 6) > 0.0) * 0.35
    return w * gust + rustle * gust


def river_loop():
    dur = 10.0
    n = int(dur * SR)
    base = shaped_noise(n, 300, 3500, tilt=-0.3)
    buf = base * 0.6
    for i in range(160):
        f = rng.uniform(500, 1600)
        d = rng.uniform(0.02, 0.06)
        bub = sweep(f, f * 1.8, d) * exp_env(int(d * SR), d / 3)
        place_wrap(buf, bub * rng.uniform(0.1, 0.4), rng.uniform(0, n))
    return buf


def waterfall_loop():
    dur = 10.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    roar = shaped_noise(n, 60, 9000, tilt=-0.25)
    rumble = shaped_noise(n, 30, 160) * 1.5
    return (roar + rumble) * (0.9 + 0.1 * np.sin(2 * np.pi * t / dur * 4))


# ----------------------------------------------------------------- movement
def footstep(v):
    d = 0.16
    n = int(d * SR)
    thump = np.sin(2 * np.pi * np.cumsum(np.linspace(140 + v * 15, 60, n)) / SR) * exp_env(n, 0.03)
    rustle = shaped_noise(n, 900, 5000) * exp_env(n, 0.04) * 0.5
    return thump + rustle


def climb(v):
    d = 0.18
    n = int(d * SR)
    scrape = shaped_noise(n, 600 + v * 300, 3800) * env_adsr(n, 0.01, 0.05, 0.5, 0.1)
    knock = np.sin(2 * np.pi * (220 + v * 30) * t_axis(d)) * exp_env(n, 0.02)
    return scrape * 0.7 + knock


def vine_grab():
    d = 0.35
    n = int(d * SR)
    t = t_axis(d)
    creak = np.sign(np.sin(2 * np.pi * np.cumsum(180 + 60 * np.sin(2 * np.pi * 7 * t)) / SR)) * 0.25
    creak *= (np.sin(2 * np.pi * 45 * t) > 0.2)
    leaves = shaped_noise(n, 1500, 7000) * exp_env(n, 0.12)
    return (creak + leaves) * env_adsr(n, 0.005, 0.1, 0.5, 0.15)


def whoosh(dur=0.6, lo=300, hi=2500):
    n = int(dur * SR)
    t = t_axis(dur)
    noise = rng.standard_normal(n)
    # sweeping band via short-time filter: blend of two filtered versions
    a = shaped_noise(n, lo, lo * 3)
    b = shaped_noise(n, hi / 3, hi)
    k = np.sin(np.pi * t / dur)
    return (a * (1 - t / dur) + b * (t / dur)) * k ** 2 + noise * 0.0


def jump():
    d = 0.18
    n = int(d * SR)
    return sweep(220, 520, d, curve=0.5) * env_adsr(n, 0.005, 0.05, 0.4, 0.1) * 0.6 + whoosh(d, 400, 3000) * 0.6


def land():
    d = 0.25
    n = int(d * SR)
    thud = np.sin(2 * np.pi * np.cumsum(np.linspace(110, 40, n)) / SR) * exp_env(n, 0.05)
    return thud + shaped_noise(n, 600, 4000) * exp_env(n, 0.05) * 0.6


# ----------------------------------------------------------------- game events
def tone(f, dur, harmonics=(1,), decay=None, sr=SR):
    t = t_axis(dur, sr)
    s = sum(np.sin(2 * np.pi * f * h * t) / (i + 1) for i, h in enumerate(harmonics))
    if decay:
        s *= exp_env(len(t), decay, sr)
    return s


def tag_sfx():
    d = 0.6
    n = int(d * SR)
    bonk = np.sin(2 * np.pi * np.cumsum(np.linspace(420, 160, n)) / SR) * exp_env(n, 0.06)
    ding = tone(1318, d, (1, 2.01, 3.0), 0.18) * 0.5 + tone(1760, d, (1, 2.0), 0.15) * 0.3
    return bonk + ding


def infect_sfx():
    d = 0.8
    n = int(d * SR)
    t = t_axis(d)
    growl = np.sign(np.sin(2 * np.pi * np.cumsum(90 + 30 * np.sin(2 * np.pi * 11 * t)) / SR))
    growl = growl * env_adsr(n, 0.02, 0.2, 0.5, 0.3) * 0.4
    zap = sweep(1800, 300, d, curve=0.4) * exp_env(n, 0.25) * 0.5
    return growl + zap + shaped_noise(n, 100, 900) * exp_env(n, 0.2)


def camo_on():
    d = 0.9
    n = int(d * SR)
    t = t_axis(d)
    shimmer = sum(np.sin(2 * np.pi * np.cumsum(np.linspace(f, f * 2.2, n)) / SR) for f in (400, 605, 810)) / 3
    leaves = shaped_noise(n, 2000, 8000) * np.sin(np.pi * t / d)
    return shimmer * env_adsr(n, 0.05, 0.3, 0.5, 0.4) * 0.6 + leaves * 0.5


def camo_off():
    d = 0.6
    n = int(d * SR)
    shimmer = sum(np.sin(2 * np.pi * np.cumsum(np.linspace(f * 2, f, n)) / SR) for f in (400, 605)) / 2
    return shimmer * env_adsr(n, 0.01, 0.2, 0.4, 0.3) * 0.6 + shaped_noise(n, 1500, 6000) * exp_env(n, 0.15) * 0.4


def camo_ready():
    a = tone(1046, 0.25, (1, 2), 0.1)
    b = tone(1568, 0.4, (1, 2), 0.15)
    out = np.zeros(int(0.55 * SR))
    place(out, a, 0)
    place(out, b, 0.12 * SR)
    return out


def whistle():
    d = 0.9
    t = t_axis(d)
    f = 2400 + 160 * np.sin(2 * np.pi * 22 * t)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) + shaped_noise(len(t), 2000, 4000) * 0.15
    return s * env_adsr(len(t), 0.02, 0.1, 0.9, 0.2)


def gong():
    d = 2.5
    n = int(d * SR)
    s = sum(tone(f, d, (1,), dec) * a for f, dec, a in ((110, 1.4, 1), (164.8, 1.1, 0.6), (220.5, 0.9, 0.5), (331, 0.6, 0.3), (497, 0.4, 0.2)))
    return s * env_adsr(n, 0.005, 0.1, 1, 0.3)


def beep(f=880, d=0.12):
    n = int(d * SR)
    return tone(f, d, (1, 3), None) * env_adsr(n, 0.003, 0.02, 0.8, 0.05)


def ui_click():
    d = 0.06
    n = int(d * SR)
    return tone(1500, d, (1, 2.5), 0.012) + shaped_noise(n, 2000, 6000) * exp_env(n, 0.006) * 0.4


def ui_hover():
    d = 0.05
    return tone(2200, d, (1,), 0.01) * 0.5


# ----------------------------------------------------------------- music
def marimba(f, dur, sr):
    t = t_axis(dur, sr)
    n = len(t)
    s = np.sin(2 * np.pi * f * t) * exp_env(n, 0.45, sr) + 0.35 * np.sin(2 * np.pi * f * 4.0 * t) * exp_env(n, 0.06, sr)
    return s * np.minimum(1, np.arange(n) / (0.003 * sr))


def music_loop():
    sr = 22050
    bpm = 112
    beat = 60 / bpm
    bars = 16
    total = bars * 4 * beat
    n = int(round(total * sr))
    buf = np.zeros(n)
    # pentatonic in C (major) for a happy jungle feel
    scale = [261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25, 783.99, 880.0]
    chords = [(0, 2, 4), (4, 6, 8), (3, 5, 7), (1, 3, 5)]  # indices into scale
    bass_roots = [130.81, 220.0, 196.0, 146.83]
    mrng = np.random.default_rng(7)
    for bar in range(bars):
        ch = chords[bar % 4]
        bar_t = bar * 4 * beat
        # bass: root on 1, fifth-ish on 3
        root = bass_roots[bar % 4]
        for b, f in ((0, root), (2, root * 1.5), (3.5, root)):
            t = t_axis(beat * 1.2, sr)
            s = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t)) * exp_env(len(t), 0.35, sr)
            place(buf, s * 0.55, (bar_t + b * beat) * sr)
        # marimba arpeggio in eighths with occasional rests
        for e in range(8):
            if mrng.random() < 0.18:
                continue
            idx = ch[mrng.integers(0, 3)] + (3 if mrng.random() < 0.3 else 0)
            idx = min(idx, len(scale) - 1)
            place(buf, marimba(scale[idx], beat * 1.5, sr) * 0.35, (bar_t + e * beat / 2) * sr)
        # melody on top every other bar pair
        if (bar // 2) % 2 == 1:
            for q in range(4):
                if mrng.random() < 0.35:
                    continue
                idx = min(ch[q % 3] + 5, len(scale) - 1)
                place(buf, marimba(scale[idx] , beat * 2, sr) * 0.3, (bar_t + q * beat) * sr)
        # percussion: bongos and shaker
        for s16 in range(16):
            tt = (bar_t + s16 * beat / 4) * sr
            if s16 % 4 == 0:
                d = 0.12
                bong = np.sin(2 * np.pi * np.cumsum(np.linspace(260, 180, int(d * sr))) / sr) * exp_env(int(d * sr), 0.04, sr)
                place(buf, bong * 0.5, tt)
            if s16 in (6, 10, 14):
                d = 0.1
                bong = np.sin(2 * np.pi * np.cumsum(np.linspace(380, 300, int(d * sr))) / sr) * exp_env(int(d * sr), 0.03, sr)
                place(buf, bong * 0.4, tt)
            d = 0.05
            sh = rng.standard_normal(int(d * sr)) * exp_env(int(d * sr), 0.012, sr) * (0.12 if s16 % 2 else 0.06)
            place(buf, sh, tt)
    # tail of the last notes wraps to the start so the loop is seamless
    return buf


def main():
    os.makedirs(OUT, exist_ok=True)
    save("amb_jungle", jungle_ambience(), peak=0.7)
    save("amb_wind", wind_loop(), peak=0.6)
    save("amb_river", river_loop(), peak=0.7)
    save("amb_waterfall", waterfall_loop(), peak=0.8)
    for k in range(4):
        save(f"bird_{k}", bird_chirp(k), peak=0.8)
    for v in range(4):
        save(f"step_{v}", footstep(v), peak=0.6)
    for v in range(3):
        save(f"climb_{v}", climb(v), peak=0.6)
    save("vine_grab", vine_grab(), peak=0.7)
    save("swing", whoosh(0.7, 250, 2200), peak=0.6)
    save("jump", jump(), peak=0.5)
    save("land", land(), peak=0.6)
    save("tag", tag_sfx(), peak=0.9)
    save("infect", infect_sfx(), peak=0.9)
    save("camo_on", camo_on(), peak=0.8)
    save("camo_off", camo_off(), peak=0.7)
    save("camo_ready", camo_ready(), peak=0.6)
    save("round_start", whistle(), peak=0.8)
    save("round_end", gong(), peak=0.9)
    save("beep", beep(), peak=0.5)
    save("beep_high", beep(1320, 0.3), peak=0.6)
    save("ui_click", ui_click(), peak=0.5)
    save("ui_hover", ui_hover(), peak=0.3)
    save("music_loop", music_loop(), peak=0.6)
    print("audio written to", OUT)


if __name__ == "__main__":
    main()
