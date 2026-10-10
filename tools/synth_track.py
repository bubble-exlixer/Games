"""NIGHT SCHOOL: a retro horror synth loop for waves 1-3 (replaces the lo-fi track).
Carpenter-style: pulsing eighth-note bass, a filtered arpeggio, slow pads, gated drums, a sparse lead,
tape wobble. Mid-tempo and soft on top so gunfire and zombies sit over it."""
import numpy as np, subprocess, sys
from scipy.signal import butter, lfilter, sosfilt

SR = 44100
BPM = 104
BEAT = 60 / BPM
BAR = 4 * BEAT
BARS = 32
L = int(round(BARS * BAR * SR))
rng = np.random.default_rng(13)
OUT = sys.argv[1] if len(sys.argv) > 1 else 'night.ogg'

def hz(n): return 440.0 * 2 ** ((n - 69) / 12)
def lp(x, f, o=2): return sosfilt(butter(o, min(f, SR / 2 - 100) / (SR / 2), 'low', output='sos'), x)
def hp(x, f, o=2): return sosfilt(butter(o, f / (SR / 2), 'high', output='sos'), x)
def bp(x, lo, hi): return sosfilt(butter(2, [lo / (SR / 2), hi / (SR / 2)], 'band', output='sos'), x)

def saw(f, n, ph=0.0):
    t = np.arange(n) / SR
    # band-limited-ish saw: a few harmonics fade with frequency
    out = np.zeros(n)
    k = 1
    while k * f < 9000 and k < 40:
        out += np.sin(2 * np.pi * k * f * t + ph * k) / k
        k += 1
    return out * 0.6

def pulse(f, n, w=0.5):
    t = np.arange(n) / SR
    out = np.zeros(n); k = 1
    while k * f < 7000 and k < 30:
        out += np.sin(np.pi * k * w) / k * np.cos(2 * np.pi * k * f * t)
        k += 1
    return out * 0.9

def env(n, a, d, s, r, hold):
    e = np.zeros(n); ai = int(a * SR); di = int(d * SR); hi = int(hold * SR); ri = int(r * SR)
    ai = max(ai, 1)
    e[:min(ai, n)] = np.linspace(0, 1, ai)[:min(ai, n)]
    if ai < n:
        seg = np.linspace(1, s, max(di, 1)); e[ai:ai + len(seg)] = seg[:max(0, n - ai)]
    if ai + di < n: e[ai + di:min(hi, n)] = s
    if hi < n:
        seg = s * np.exp(-np.arange(n - hi) / max(ri * 0.3, 1)); e[hi:] = seg
    return e

mix_bass = np.zeros(L + SR * 4); mix_arp = np.zeros_like(mix_bass); mix_pad = np.zeros_like(mix_bass)
mix_drum = np.zeros_like(mix_bass); mix_lead = np.zeros_like(mix_bass); mix_snr = np.zeros_like(mix_bass)
def put(buf, x, t0, g=1.0):
    i = int(t0 * SR); j = min(len(buf), i + len(x)); buf[i:j] += x[:j - i] * g

# A minor: Am | F | Dm | E  (the E major is the dread)
PROG = [[57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59]]
ROOT = [45, 41, 38, 40]
# sections (8 bars each): A intro (bass+pad+arp), B drums in, C lead, D breakdown (pad+arp, half drums)
def section(bar): return 'ABCD'[(bar // 8) % 4]

for bar in range(BARS):
    sec = section(bar); ch = bar % 4; t_bar = bar * BAR
    chord = PROG[ch]; root = ROOT[ch]
    # pad: three detuned saws per chord note, slow swell, dark
    n = int(BAR * SR) + SR
    pad = np.zeros(n)
    for note in chord:
        for det in (-0.12, 0.0, 0.11):
            pad += saw(hz(note + det), n, rng.uniform(0, 6))
    pad = lp(pad, 900 if sec != 'D' else 1300) * env(n, 0.9, 0.5, 0.8, 1.0, BAR)
    put(mix_pad, pad, t_bar, 0.06)
    # bass: the pulse. eighth notes, octave jump on the "and" of 4
    if True:
        for e8 in range(8):
            nn = root + (12 if e8 == 7 else 0)
            m = int(BEAT / 2 * SR * 0.92)
            x = saw(hz(nn), m) * 0.7 + pulse(hz(nn) * 0.5, m, 0.35) * 0.5
            cut = 380 + 900 * np.exp(-np.arange(m) / (SR * 0.05))
            x = lp(x, 900) * env(m, 0.004, 0.08, 0.6, 0.05, BEAT / 2 * 0.85)
            # crude filter envelope: blend a darker copy over time
            dark = lp(x, 300)
            k = np.exp(-np.arange(m) / (SR * 0.06))
            x = x * k + dark * (1 - k)
            put(mix_bass, x, t_bar + e8 * BEAT / 2, (0.5 if sec != 'D' else 0.3) * (1.0 if e8 % 2 == 0 else 0.8))
    # arp: sixteenths up and down the chord over two octaves, through a soft filter
    arp_notes = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[0] + 24, chord[2] + 12, chord[1] + 12]
    if sec in 'ABCD':
        for s16 in range(16):
            nn = arp_notes[s16 % len(arp_notes)]
            m = int(BEAT / 4 * SR * 0.8)
            x = pulse(hz(nn), m, 0.25) * env(m, 0.003, 0.05, 0.3, 0.05, BEAT / 4 * 0.6)
            sweep = 1200 + 900 * np.sin(2 * np.pi * (bar * 16 + s16) / 128)
            x = lp(x, sweep)
            put(mix_arp, x, t_bar + s16 * BEAT / 4, 0.12 if sec != 'A' else 0.09)
    # drums: kick on 1 and 3 (and a ghost), gated snare on 2 and 4, soft hats only in C
    if sec in 'BC' or (sec == 'D' and bar % 2 == 1):
        for b4 in range(4):
            tb = t_bar + b4 * BEAT
            if b4 in (0, 2) or (b4 == 3 and bar % 4 == 3):
                m = int(0.35 * SR); tt = np.arange(m) / SR
                f = 45 + 90 * np.exp(-tt / 0.03)
                kick = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.16)
                put(mix_drum, kick, tb + (BEAT / 2 if b4 == 3 else 0), 0.5)
            if b4 in (1, 3) and sec != 'D':
                m = int(0.28 * SR); tt = np.arange(m) / SR
                nz = rng.standard_normal(m)
                sn = bp(nz, 900, 5000) * 0.6 + np.sin(2 * np.pi * 190 * tt) * np.exp(-tt / 0.04) * 0.5
                gate = np.where(tt < 0.22, 1.0, np.exp(-(tt - 0.22) / 0.01)) * (0.6 + 0.4 * np.exp(-tt / 0.05))
                put(mix_snr, sn * gate, tb, 0.22)
            if sec == 'C':
                for h in range(2):
                    m = int(0.05 * SR); hh = hp(rng.standard_normal(m), 7000) * np.exp(-np.arange(m) / (SR * 0.012))
                    put(mix_drum, hh, tb + h * BEAT / 2, 0.035)
    # lead: only in C, a slow three-note motif every other bar, glide and vibrato, never shrill
    if sec == 'C' and bar % 2 == 0:
        motif = [(chord[2] + 12, 0, 1.5), (chord[1] + 12, 1.5, 1.0), (chord[0] + 12, 2.5, 1.5)] if ch < 3 else [(68, 0, 1.0), (69, 1.0, 1.0), (71, 2.0, 2.0)]
        for nn, st, dur in motif:
            m = int(dur * BEAT * SR); tt = np.arange(m) / SR
            vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * tt) * np.clip(tt / 0.4, 0, 1)
            ph = 2 * np.pi * np.cumsum(hz(nn) * vib) / SR
            x = (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.18 * np.sin(3 * ph)) * env(m, 0.05, 0.2, 0.7, 0.3, dur * BEAT * 0.85)
            put(mix_lead, lp(x, 2400), t_bar + st * BEAT, 0.07)

def delay(x, t, fb, mix):
    d = int(t * SR); y = x.copy()
    for k in range(1, 6):
        y[d * k:] += x[:-d * k] * (fb ** k) * mix if d * k < len(x) else 0
    return y
def reverb(x, t60=1.8, mix=0.25):
    n = int(t60 * SR); ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * t60 / 6.9))
    ir = lp(ir, 4000); ir /= np.sqrt((ir ** 2).sum())
    from scipy.signal import fftconvolve
    return x + fftconvolve(x, ir)[:len(x)] * mix

arp = delay(mix_arp, BEAT * 0.75, 0.45, 1.0)
lead = delay(mix_lead, BEAT * 0.5, 0.35, 0.8)
snr = reverb(mix_snr, 0.9, 0.6)
bus = mix_bass + reverb(arp + mix_pad + lead, 2.4, 0.35) + mix_drum + snr
# stereo: arp and pad wider than the bass
left = bus + reverb(arp, 1.2, 0.2) * 0.15
right = bus + reverb(np.roll(arp, int(0.013 * SR)), 1.2, 0.2) * 0.15
st = np.stack([left, right], 1)
# tape wobble: slow wow + a little flutter, applied as a time warp
tt = np.arange(st.shape[0]) / SR
warp = tt + 0.0018 * np.sin(2 * np.pi * 0.31 * tt) + 0.00006 * np.sin(2 * np.pi * 6.1 * tt)
for c in range(2):
    st[:, c] = np.interp(np.clip(warp, 0, tt[-1]), tt, st[:, c])
# soft top end, gentle saturation
for c in range(2):
    st[:, c] = lp(st[:, c], 7500, 2)
st = np.tanh(st * 1.4) / 1.4
# loop: fold the tail back over the start so the seam is seamless
body = st[:L].copy(); tail = st[L:]; k = min(len(tail), L); body[:k] += tail[:k]
body /= np.abs(body).max() / 0.85
body *= 10 ** ((-19.5 - 20 * np.log10(np.sqrt(np.mean(body ** 2)))) / 20)   # sit at the other tracks' level
raw = (body * 32767).astype('<i2').tobytes()
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', '-', '-c:a', 'libvorbis', '-q:a', '5', OUT], input=raw, check=True)
print('wrote', OUT, round(L / SR, 1), 's')
