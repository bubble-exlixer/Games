"""Sounds for the silly update: hats, power-ups, shock gate, mega hamster, new weapons, bosses, bus escape."""
import numpy as np, subprocess
from scipy.signal import butter, sosfilt
SR = 44100
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'DeadShift', 'assets', 'audio', 'sfx') + os.sep
rng = np.random.default_rng(11)
def t_(d): return np.arange(int(d * SR)) / SR
def bp(x, lo, hi): return sosfilt(butter(2, [lo / (SR / 2), hi / (SR / 2)], 'band', output='sos'), x)
def lp(x, f): return sosfilt(butter(2, f / (SR / 2), 'low', output='sos'), x)
def hp(x, f): return sosfilt(butter(2, f / (SR / 2), 'high', output='sos'), x)
def noise(n): return rng.standard_normal(n)
def env(n, a, r):
    e = np.ones(n); ai = max(1, int(a * SR)); e[:ai] = np.linspace(0, 1, ai)
    ri = max(1, int(r * SR)); e[-ri:] *= np.linspace(1, 0, ri) ** 2; return e
def sweep(f, t): return 2 * np.pi * np.cumsum(f) / SR
def saw(ph): return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
def sq(ph): return np.sign(np.sin(ph))
def save(name, x, peak=0.9):
    x = np.nan_to_num(x); x = x / (np.abs(x).max() + 1e-9) * peak
    st = np.stack([x, x], 1)
    raw = (st * 32767).astype('<i2').tobytes()
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', '-', '-c:a', 'libvorbis', '-q:a', '5', OUT + name + '.ogg'], input=raw, check=True)
def at(x, y, s):
    i = int(s * SR); n = min(len(y), len(x) - i)
    if n > 0: x[i:i + n] += y[:n]

# ploink: hat popping off, a cartoon cork pop + rising boing
t = t_(0.45)
pop = bp(noise(len(t)), 800, 5000) * np.exp(-t / 0.006)
f = 380 + 900 * (1 - np.exp(-t / 0.05))
boing = np.sin(sweep(f * (1 + 0.06 * np.sin(2 * np.pi * 22 * t)), t)) * np.exp(-t / 0.16)
save('ploink', pop * 1.4 + boing)

# snow day: soft wind whoosh + sparkly chimes
t = t_(2.2)
x = lp(noise(len(t)), 900) * np.sin(np.pi * t / 2.2) * 0.6
for k, f0 in enumerate([1568, 2093, 2637, 3136, 2349, 1760]):
    tt = t_(1.2); at(x, np.sin(2 * np.pi * f0 * tt) * np.exp(-tt / 0.35) * 0.5, 0.1 + k * 0.12)
save('snowday', x)

# fire drill alarm: classic school fire bell (fast hammer on a bell)
t = t_(2.0)
bell = sum(np.sin(2 * np.pi * f0 * t) * a for f0, a in [(1180, 1), (2410, 0.5), (3530, 0.3)])
ham = (np.sin(2 * np.pi * 22 * t) > 0).astype(float)
ham = lp(ham, 60) * 0.5 + 0.5
save('alarm', bell * ham * env(len(t), 0.01, 0.2))

# free period: school bell ring (the end-of-class electric bell, short)
t = t_(1.4)
bell = sum(np.sin(2 * np.pi * f0 * t) * a for f0, a in [(880, 1), (1760, 0.4), (2650, 0.25)])
save('freebell', bell * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 30 * t))) * env(len(t), 0.005, 0.3))

# electric zap / crackle (shock gate on hit)
t = t_(0.5)
x = np.zeros(len(t))
for k in range(14):
    n = int(rng.uniform(0.01, 0.04) * SR); s = rng.uniform(0, 0.45)
    at(x, hp(noise(n), 1500) * np.exp(-np.arange(n) / (SR * 0.008)), s)
x += sq(sweep(np.full(len(t), 120.0), t)) * 0.25 * np.exp(-t / 0.2)
save('zap', x)
# shock gate hum (loopable 1 s): 60 Hz mains buzz with crackle
t = t_(1.0)
x = saw(sweep(np.full(len(t), 120.0), t)) * 0.4 + sq(sweep(np.full(len(t), 60.0), t)) * 0.2
x = lp(x, 1800)
for k in range(10):
    n = int(0.01 * SR); at(x, hp(noise(n), 2000) * 0.6, rng.uniform(0, 0.98))
save('gatehum', x, 0.7)
# lever clunk
t = t_(0.35)
save('lever', lp(noise(len(t)), 1200) * np.exp(-t / 0.03) + np.sin(2 * np.pi * 140 * t) * np.exp(-t / 0.08))

# mega hamster roar: a tiny squeak pitched through a growl, rising
t = t_(0.9)
f = 900 + 500 * np.sin(np.pi * t / 0.9)
x = saw(sweep(f, t)) * (0.6 + 0.4 * np.sin(2 * np.pi * 34 * t))
x = bp(x, 600, 5000) * env(len(t), 0.03, 0.3)
save('hamroar', x)

# trombone: brassy note (wah) / sad wah-wah-wahhh
def bone(f0, d, bend=0.0, wah=True):
    t = t_(d); f = f0 * (1 + bend * t / d) * (1 + 0.012 * np.sin(2 * np.pi * 5.5 * t * (t > 0.25)))
    ph = sweep(f, t)
    x = sum(np.sin(k * ph) / k ** 0.7 for k in range(1, 12))
    cut = 600 + 2200 * (np.sin(np.pi * np.minimum(t / 0.18, 1) / 2) if wah else 1)
    y = np.zeros(len(t)); blk = 512
    for i in range(0, len(t), blk):
        y[i:i + blk] = lp(x[max(0, i - 2048):i + blk], float(np.mean(cut[i:i + blk])))[-len(x[i:i + blk]):]
    return y * env(len(t), 0.03, 0.08)
save('trombone', bone(116.5, 0.55))
w = np.zeros(int(2.4 * SR))
at(w, bone(155.6, 0.42), 0); at(w, bone(146.8, 0.42), 0.45); at(w, bone(138.6, 0.42), 0.9); at(w, bone(130.8, 1.3, -0.05), 1.35)
save('wahwah', w)
# sonic blast: low brass blat + air
t = t_(0.5)
x = bone(58.3, 0.5, -0.1) + bp(noise(len(t)), 200, 2000) * np.exp(-t / 0.1) * 0.6
save('blat', x)

# textbook launcher: compressed-air thump; book slam
t = t_(0.35)
save('shot_book', lp(noise(len(t)), 700) * np.exp(-t / 0.04) + np.sin(2 * np.pi * (140 - 120 * t) * t) * np.exp(-t / 0.08))
t = t_(0.4)
save('bookslam', hp(noise(len(t)), 300) * np.exp(-t / 0.015) * 1.2 + lp(noise(len(t)), 400) * np.exp(-t / 0.06))
# dodgeball cannon: rubbery fwomp; ball bounce
t = t_(0.3)
save('shot_dodge', np.sin(sweep(260 - 500 * t, t)) * np.exp(-t / 0.06) + lp(noise(len(t)), 1500) * np.exp(-t / 0.03) * 0.5)
t = t_(0.25)
save('bounce', np.sin(sweep(200 + 300 * np.exp(-t / 0.02), t)) * np.exp(-t / 0.05) + bp(noise(len(t)), 500, 2500) * np.exp(-t / 0.008))
# detention slip: paper whoosh + magical poof
t = t_(0.9)
x = bp(noise(len(t)), 1500, 6000) * np.exp(-((t - 0.1) / 0.08) ** 2)
x += lp(noise(len(t)), 1200) * np.exp(-t / 0.25) * 0.7
for k, f0 in enumerate([1200, 1500, 1800, 2400]):
    tt = t_(0.5); at(x, np.sin(2 * np.pi * f0 * tt) * np.exp(-tt / 0.15) * 0.3, 0.15 + 0.05 * k)
save('poof', x)

# boss taunt sting: short dirty brass stab
t = t_(0.5)
x = sum(saw(sweep(np.full(len(t), f0), t)) for f0 in [98, 116.5, 146.8])
save('sting', lp(x, 1400) * env(len(t), 0.005, 0.25))
# ground pound
t = t_(1.0)
save('pound', lp(noise(len(t)), 220) * np.exp(-t / 0.25) * 1.5 + np.sin(2 * np.pi * (60 - 20 * t) * t) * np.exp(-t / 0.3))
# door slam
t = t_(0.6)
save('slam', lp(noise(len(t)), 900) * np.exp(-t / 0.05) + np.sin(2 * np.pi * 90 * t) * np.exp(-t / 0.15) + bp(noise(len(t)), 2000, 5000) * np.exp(-t / 0.01) * 0.5)

# bus: starter cough (crank crank sputter), engine roar (rising), crash
t = t_(2.6)
x = np.zeros(len(t))
for k in range(5):
    tt = t_(0.32); f = 18 + 4 * np.sin(2 * np.pi * 3 * tt)
    at(x, lp(sq(sweep(f * 6, tt)) * (np.sin(2 * np.pi * 9 * tt) > 0) + noise(len(tt)) * 0.3, 500) * np.exp(-tt / 0.2), 0.05 + k * 0.38)
at(x, lp(noise(int(0.25 * SR)), 300) * 2.0, 2.0)
save('cough', x)
t = t_(4.5)
f = 32 + 55 * (1 - np.exp(-t / 1.2)) + 6 * np.sin(2 * np.pi * 1.3 * t)
ph = sweep(f, t)
x = lp(saw(ph) + 0.6 * sq(ph * 0.5) + 0.3 * noise(len(t)), 900) * (0.6 + 0.4 * t / 4.5)
save('engine', x * env(len(t), 0.05, 0.6))
t = t_(2.4)
x = lp(noise(len(t)), 500) * np.exp(-t / 0.4) * 1.6 + hp(noise(len(t)), 2500) * np.exp(-t / 0.3)
for k in range(10):
    tt = t_(0.5); at(x, np.sin(2 * np.pi * rng.uniform(700, 2200) * tt) * np.exp(-tt / 0.12) * 0.4, rng.uniform(0.0, 1.2))
save('crash', x)
# bite: wet chomp + human scream cut short
t = t_(0.8)
x = lp(noise(len(t)), 1500) * np.exp(-t / 0.05)
scr = np.sin(sweep(700 + 300 * np.sin(np.pi * t / 0.8), t)) * bp(noise(len(t)), 600, 3000) * np.exp(-((t - 0.3) / 0.18) ** 2)
save('bite', x + scr * 0.8)
print('ok')
