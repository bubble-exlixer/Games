"""Sounds for list 4: death-cam record scratch, Volcano Launcher, the mascot zombie."""
import numpy as np, subprocess, os
from scipy.signal import butter, sosfilt
SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'DeadShift', 'assets', 'audio', 'sfx') + os.sep
rng = np.random.default_rng(33)
def t_(d): return np.arange(int(d * SR)) / SR
def bp(x, lo, hi): return sosfilt(butter(2, [lo / (SR / 2), hi / (SR / 2)], 'band', output='sos'), x)
def lp(x, f): return sosfilt(butter(2, f / (SR / 2), 'low', output='sos'), x)
def hp(x, f): return sosfilt(butter(2, f / (SR / 2), 'high', output='sos'), x)
def save(name, x, peak=0.9):
    x = x / (np.abs(x).max() + 1e-9) * peak
    raw = (np.stack([x, x], 1) * 32767).astype('<i2').tobytes()
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', '-', '-c:a', 'libvorbis', '-q:a', '6', OUT + name + '.ogg'], input=raw, check=True)
n = lambda k: rng.standard_normal(k)

# record scratch: a forward-back-forward drag of a tone-rich groove through a band-pass
t = t_(0.55)
rate = np.interp(t, [0, 0.12, 0.2, 0.32, 0.42, 0.55], [1.6, 2.4, -1.8, 2.2, 0.4, 0.0])
ph = np.cumsum(rate) / SR
groove = np.sin(2 * np.pi * 900 * ph) + 0.5 * np.sin(2 * np.pi * 1700 * ph) + 0.4 * n(len(t)) * np.abs(rate) / 2.4
save('scratch', bp(groove, 300, 4000) * np.minimum(1, np.abs(rate)) * np.exp(-np.maximum(t - 0.42, 0) / 0.05))

# volcano launcher: a hollow pump "thoomp" with a wet glug
t = t_(0.4)
thoomp = np.sin(2 * np.pi * (180 - 260 * t) * t) * np.exp(-t / 0.07)
glug = bp(n(len(t)), 250, 900) * np.exp(-((t - 0.05) / 0.04) ** 2)
air = bp(n(len(t)), 800, 3000) * np.exp(-t / 0.03) * 0.5
save('shot_volc', thoomp * 1.2 + glug + air)
# eruption: a fizzing burst with bubbling pops
t = t_(1.4)
fizz = hp(n(len(t)), 2500) * (np.exp(-t / 0.5)) * 0.6
burst = lp(n(len(t)), 600) * np.exp(-t / 0.08) * 1.5
bub = np.zeros(len(t))
for k in range(45):
    s = int(rng.uniform(0, 1.2) * SR); m = int(0.025 * SR); f0 = rng.uniform(300, 1000)
    tt = np.arange(min(m, len(t) - s)) / SR
    bub[s:s + len(tt)] += np.sin(2 * np.pi * f0 * (1 + 4 * tt) * tt) * np.exp(-tt / 0.008)
save('erupt', burst + fizz + bub * 0.7)

# the mascot: a goofy costumed roar (a growl through a muffled foam head) and a pounce grunt
t = t_(0.8)
f = 140 + 60 * np.sin(np.pi * t / 0.8)
ph = 2 * np.pi * np.cumsum(f * (1 + 0.04 * np.sin(2 * np.pi * 28 * t))) / SR
voice = sum(np.sin(h * ph) / h for h in range(1, 10)) * (0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 31 * t)))
save('mascotRoar', lp(voice + 0.3 * n(len(t)), 1300) * np.sin(np.pi * t / 0.8) ** 0.6)
t = t_(0.3)
ph = 2 * np.pi * np.cumsum(220 - 120 * t / 0.3) / SR
save('mascotHup', lp(sum(np.sin(h * ph) / h for h in range(1, 8)), 1500) * np.sin(np.pi * t / 0.3))
print('sfx4 ok')
