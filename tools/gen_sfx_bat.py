"""Baseball bat: swing whoosh, meaty crack on a zombie, thunk on a wall, home-run crowd."""
import numpy as np, subprocess
from scipy.signal import butter, sosfilt
SR = 44100
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'DeadShift', 'assets', 'audio', 'sfx') + os.sep
rng = np.random.default_rng(21)
def t_(d): return np.arange(int(d * SR)) / SR
def bp(x, lo, hi): return sosfilt(butter(2, [lo / (SR / 2), hi / (SR / 2)], 'band', output='sos'), x)
def lp(x, f): return sosfilt(butter(2, f / (SR / 2), 'low', output='sos'), x)
def hp(x, f): return sosfilt(butter(2, f / (SR / 2), 'high', output='sos'), x)
def save(name, x, peak=0.95):
    x = x / (np.abs(x).max() + 1e-9) * peak
    raw = (np.stack([x, x], 1) * 32767).astype('<i2').tobytes()
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', '-', '-c:a', 'libvorbis', '-q:a', '6', OUT + name + '.ogg'], input=raw, check=True)
n = lambda k: rng.standard_normal(k)

# swing: a band-passed whoosh that sweeps up then down (a heavy object cutting air)
t = t_(0.32)
env = np.sin(np.pi * np.clip(t / 0.3, 0, 1)) ** 2
x = np.zeros(len(t))
for i, f in enumerate(np.linspace(300, 1400, 40)):
    pass
w = n(len(t))
c = 400 + 900 * np.sin(np.pi * np.clip(t / 0.3, 0, 1))
y = np.zeros(len(t)); blk = 256
for i in range(0, len(t), blk):
    f0 = float(np.mean(c[i:i + blk]))
    y[i:i + blk] = bp(w[max(0, i - 2048):i + blk], f0 * 0.6, f0 * 1.6)[-len(w[i:i + blk]):]
save('batSwing', y * env, 0.8)

# crack + meat: a hard wooden crack, a hollow knock, a low body thump and a wet slap
t = t_(0.5)
crack = hp(n(len(t)), 1800) * np.exp(-t / 0.006)
knock = (np.sin(2 * np.pi * 620 * t) + 0.6 * np.sin(2 * np.pi * 1310 * t) + 0.3 * np.sin(2 * np.pi * 2150 * t)) * np.exp(-t / 0.045)
thump = np.sin(2 * np.pi * (95 - 40 * t) * t) * np.exp(-t / 0.09)
slap = bp(n(len(t)), 300, 2200) * np.exp(-((t - 0.012) / 0.03) ** 2)
save('batHit', crack * 1.3 + knock * 0.7 + thump * 1.4 + slap * 0.9)
# the overhead slam: same, heavier and lower
thump2 = np.sin(2 * np.pi * (70 - 30 * t) * t) * np.exp(-t / 0.16)
crunch = bp(n(len(t)), 600, 4000) * np.exp(-t / 0.05) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 70 * t)))
save('batSlam', crack * 1.1 + knock * 0.5 + thump2 * 1.8 + crunch * 0.8)
# bat on a wall / floor: dull wooden thunk with a buzz
t = t_(0.35)
save('batWall', (np.sin(2 * np.pi * 330 * t) + 0.5 * np.sin(2 * np.pi * 870 * t)) * np.exp(-t / 0.05) + lp(n(len(t)), 900) * np.exp(-t / 0.02) + hp(n(len(t)), 2500) * np.exp(-t / 0.004))
# home run: a stadium crowd "ohhh!" swelling and an organ stab
t = t_(1.6)
crowd = np.zeros(len(t))
for k in range(26):
    f0 = rng.uniform(140, 320); vib = rng.uniform(4, 7)
    ph = 2 * np.pi * np.cumsum(f0 * (1 + 0.15 * t) * (1 + 0.02 * np.sin(2 * np.pi * vib * t))) / SR
    v = sum(np.sin(h * ph) / h for h in range(1, 8))
    crowd += bp(v, 400, 1800) * rng.uniform(0.5, 1.0)
crowd += bp(n(len(t)), 300, 3000) * 2.5
crowd *= np.clip(t / 0.25, 0, 1) * np.exp(-np.maximum(t - 0.6, 0) / 0.4)
organ = np.zeros(len(t))
for f0, st in [(523.25, 0.0), (659.25, 0.0), (783.99, 0.0)]:
    tt = t
    organ += (np.sign(np.sin(2 * np.pi * f0 * tt)) * 0.3 + np.sin(2 * np.pi * f0 * tt)) * np.exp(-tt / 0.35)
save('homerun', crowd / np.abs(crowd).max() + organ / np.abs(organ).max() * 0.35, 0.8)
print('bat sfx ok')
