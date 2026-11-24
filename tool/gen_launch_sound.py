#!/usr/bin/env python3
"""Renders the Deeprowss launch sound to assets/sounds/launch_sting.wav.

This is a faithful offline port of the synthesised sting in
assets/receiver/index.html (Windows EXE / Android TV / LG / Samsung / web):
sub boom, rising whoosh while the logo spins, bright chime as it lands.
Run:  python3 tool/gen_launch_sound.py   (needs numpy)
"""
import math, wave, os
import numpy as np

SR = 44100
DUR = 3.6
N = int(SR * DUR)
T0 = 0.06  # same start offset as the web version
mix = np.zeros(N)

def exp_ramp(v0, v1, t, a, b):
    """Web Audio exponentialRampToValueAtTime between (a,v0) and (b,v1)."""
    x = np.clip((t - a) / (b - a), 0, 1)
    return v0 * (v1 / v0) ** x

def tone(kind, f1, f2, st, dur, vol, atk):
    global mix
    s = int((T0 + st) * SR)
    e = min(N, int((T0 + st + dur + 0.05) * SR))
    t = np.arange(s, e) / SR - (T0 + st)
    f = exp_ramp(f1, f2, t, 0, dur) if f2 else np.full_like(t, f1)
    phase = 2 * math.pi * np.cumsum(f) / SR
    w = np.sin(phase) if kind == 'sine' else (2 / math.pi) * np.arcsin(np.sin(phase))
    g = np.where(t < atk, exp_ramp(.0001, vol, t, 0, atk), exp_ramp(vol, .0001, t, atk, dur))
    g = np.where(t > dur, 0, g)
    mix[s:e] += w * g

tone('sine', 95, 38, 0, .9, .5, .01)         # sub boom as the logo appears
tone('triangle', 180, 1500, 0, 1.7, .1, .7)  # rising sweep while it spins
tone('sine', 360, 3000, .05, 1.65, .05, .8)

# whoosh: white noise through a band-pass sweeping 300 -> 4200 Hz
rng = np.random.default_rng(7)
noise = rng.uniform(-1, 1, int(SR * 1.9))
out = np.zeros_like(noise)
x1 = x2 = y1 = y2 = 0.0
Q = 1.1
for i in range(len(noise)):
    t = i / SR
    f0 = 300 * (4200 / 300) ** min(t / 1.7, 1)
    w0 = 2 * math.pi * f0 / SR
    al = math.sin(w0) / (2 * Q)
    a0 = 1 + al
    b0 = al / a0; b2 = -al / a0
    a1 = -2 * math.cos(w0) / a0; a2 = (1 - al) / a0
    y = b0 * noise[i] + b2 * x2 - a1 * y1 - a2 * y2
    x2, x1 = x1, noise[i]; y2, y1 = y1, y
    out[i] = y
tn = np.arange(len(noise)) / SR
ng = np.where(tn < 1.45, exp_ramp(.0001, .13, tn, 0, 1.45), exp_ramp(.13, .0001, tn, 1.45, 1.85))
ng = np.where(tn > 1.85, 0, ng)
s = int(T0 * SR)
mix[s:s + len(out)] += out * ng

# chime when the spin lands
for i, f in enumerate([659.25, 987.77, 1318.5, 1661.2]):
    tone('sine', f, 0, 1.72 + i * .07, 1.5, .17 / (1 + i * .4), .005)
    tone('sine', f * 2.01, 0, 1.72 + i * .07, .7, .035, .005)

mix *= .9
peak = np.max(np.abs(mix))
mix *= .85 / peak   # the web version has compressor make-up gain; normalise to a healthy level
# Loudness boost: drive into a soft limiter (raises the average level, not just
# the peak), then normalise to just under full scale.
DRIVE = 3.0
mix = np.tanh(mix * DRIVE)
mix *= .98 / np.max(np.abs(mix))
fade = int(.05 * SR)
mix[:fade // 5] *= np.linspace(0, 1, fade // 5)
mix[-fade:] *= np.linspace(1, 0, fade)

path = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds', 'launch_sting.wav')
with wave.open(path, 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype('<i2').tobytes())
print('wrote', os.path.abspath(path), round(peak, 3))
