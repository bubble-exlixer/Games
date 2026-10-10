"""New sounds for the second update: whistle, staple gun, Pack-a-Punch, fizz, PA chime + voice, tray clatter."""
import numpy as np, subprocess
from scipy.signal import butter, sosfilt
SR = 44100
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'DeadShift', 'assets', 'audio', 'sfx') + os.sep
rng = np.random.default_rng(4)
def t_(d): return np.arange(int(d * SR)) / SR
def bp(x, lo, hi): return sosfilt(butter(2, [lo / (SR / 2), hi / (SR / 2)], 'band', output='sos'), x)
def lp(x, f): return sosfilt(butter(2, f / (SR / 2), 'low', output='sos'), x)
def env(n, a, r):
    e = np.ones(n); ai = max(1, int(a * SR)); e[:ai] = np.linspace(0, 1, ai)
    ri = max(1, int(r * SR)); e[-ri:] *= np.linspace(1, 0, ri) ** 2; return e
def save(name, x):
    x = x / (np.abs(x).max() + 1e-9) * 0.9
    st = np.stack([x, x], 1)
    raw = (st * 32767).astype('<i2').tobytes()
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', '-', '-c:a', 'libvorbis', '-q:a', '5', OUT + name + '.ogg'], input=raw, check=True)

# referee / hall monitor pea whistle: two shrill blasts with the pea's trill
def blast(d):
    t = t_(d); f = 2750 + 60 * np.sin(2 * np.pi * 5 * t)
    trill = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * 38 * t + 3 * np.sin(2 * np.pi * 7 * t)))
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = (np.sin(ph) + 0.25 * np.sin(2 * ph)) * trill + bp(rng.standard_normal(len(t)), 2400, 3600) * 0.25
    return x * env(len(t), 0.01, 0.06)
w = np.concatenate([blast(0.22), np.zeros(int(0.08 * SR)), blast(0.55)])
save('whistle', w)

# staple cannon: a hard snap and a metallic ka-chunk
t = t_(0.22)
snap = bp(rng.standard_normal(len(t)), 1800, 7000) * np.exp(-t / 0.01)
chunk = np.sin(2 * np.pi * (260 - 400 * t) * t) * np.exp(-t / 0.04)
ring = np.sin(2 * np.pi * 3100 * t) * np.exp(-t / 0.05) * 0.25
save('shot_staple', snap * 1.2 + chunk * 0.8 + ring)

# Pack-a-Punch: rising machine whine, grinding and zaps (about 3 s)
t = t_(3.3)
f = 60 + 160 * (t / 3.3) ** 1.5
saw = 2 * ((np.cumsum(f) / SR) % 1.0) - 1
grind = bp(rng.standard_normal(len(t)), 300, 1400) * (0.4 + 0.3 * np.sin(2 * np.pi * 9 * t))
x = lp(saw, 1200) * 0.6 + grind * 0.4
for k in range(9):
    s = int((0.3 + k * 0.33) * SR); n = int(0.09 * SR)
    x[s:s + n] += bp(rng.standard_normal(n), 2500, 7000) * np.exp(-np.arange(n) / (SR * 0.02)) * 0.9
save('papStart', x * env(len(t), 0.05, 0.2))
t = t_(1.3)
x = np.zeros(len(t))
for f0, st in [(392, 0), (523.25, 0.11), (659.25, 0.22), (1046.5, 0.36)]:
    s = int(st * SR); tt = t[: len(t) - s]
    x[s:] += np.sin(2 * np.pi * f0 * tt) * np.exp(-tt / 0.45) + 0.3 * np.sin(2 * np.pi * f0 * 2 * tt) * np.exp(-tt / 0.2)
x += bp(rng.standard_normal(len(t)), 3000, 8000) * np.exp(-t / 0.15) * 0.4
save('papDone', x)

# fizzing beaker that gets out of hand
t = t_(2.6)
fz = bp(rng.standard_normal(len(t)), 2500, 9000) * (0.2 + 0.8 * (t / 2.6) ** 2)
bub = np.zeros(len(t))
for k in range(60):
    s = int(rng.uniform(0, 2.5) * SR); n = int(0.03 * SR); f0 = rng.uniform(400, 1400)
    bub[s:s + n] += np.sin(2 * np.pi * np.linspace(f0, f0 * 1.8, n) * np.arange(n) / SR) * np.exp(-np.arange(n) / (SR * 0.01))
save('fizz', fz + bub * 0.6)

# school PA: two-tone chime
t = t_(1.4)
x = np.zeros(len(t))
for f0, st in [(659.25, 0), (523.25, 0.42)]:
    s = int(st * SR); tt = t[: len(t) - s]
    x[s:] += (np.sin(2 * np.pi * f0 * tt) + 0.4 * np.sin(2 * np.pi * f0 * 3 * tt)) * np.exp(-tt / 0.5)
save('paChime', x)

# a muffled PA "voice": syllables of band-passed buzz (we never hear the words, the captions carry them)
t = t_(3.2)
x = np.zeros(len(t))
pos = 0.0
while pos < 3.0:
    d = rng.uniform(0.09, 0.22); s = int(pos * SR); n = int(d * SR); tt = np.arange(n) / SR
    f0 = rng.uniform(105, 140); f = f0 * (1 - 0.15 * tt / d)
    buzz = 2 * ((np.cumsum(f) / SR) % 1.0) - 1
    x[s:s + n] += bp(buzz, rng.uniform(600, 1000), rng.uniform(1400, 2200)) * np.sin(np.pi * tt / d)
    pos += d + (rng.uniform(0.25, 0.4) if rng.random() < 0.18 else rng.uniform(0.01, 0.05))
x += bp(rng.standard_normal(len(t)), 1500, 4000) * 0.03
save('paVoice', x)

# lunch tray clatter / gravy slop
t = t_(0.5)
x = bp(rng.standard_normal(len(t)), 1200, 6000) * np.exp(-t / 0.06)
for k in range(4):
    s = int(rng.uniform(0.02, 0.3) * SR); n = int(0.12 * SR); tt = np.arange(n) / SR
    x[s:s + n] += np.sin(2 * np.pi * rng.uniform(900, 1500) * tt) * np.exp(-tt / 0.04) * 0.6
save('tray', x)
t = t_(0.6)
x = lp(rng.standard_normal(len(t)), 900) * np.exp(-t / 0.12) * (1 + 0.6 * np.sin(2 * np.pi * 23 * t))
save('slop', x)
print('sfx ok')
