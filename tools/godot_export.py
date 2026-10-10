"""Export Dead Shift: Westfield High assets for the Godot port (all units in metres, like the web game)."""
import json, os, sys, math, subprocess, glob as G
import numpy as np
# source data: the web game's export (school_export.json, audio) lives outside the repo; point DEADSHIFT_SRC at it
SP = os.environ.get('DEADSHIFT_SRC', os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(SP, 'roblox'))
import glb as GL

X = json.load(open(os.path.join(SP, 'roblox', 'school_export.json')))
K = X['K']          # studs per metre for map/guns
ZS = 3.0            # studs per metre for zombie samples
PROJ = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'DeadShift')
for d in ['assets/models/guns', 'assets/models/zombies', 'assets/audio/sfx', 'assets/audio/music', 'data']:
    os.makedirs(os.path.join(PROJ, d), exist_ok=True)

def m(v, k=K): return [round(float(x) / k, 4) for x in v]

T = X['textures']; M = X['meshes']; cache = {}
def png_for(c):
    if c.get('tex') and T[c['tex']]['c'] == 4 and not c['cut']:
        c['alpha'] = True          # see-through texture (shadow blobs, decals): blend it
    return GL.tex_image(T, c['tex'], c.get('tint'), c.get('glow'), cache) if c.get('tex') else None
TEXC = {tid: t['c'] for tid, t in T.items()}

# ---------------------------------------------------------------- models
g = GL.GLB(1 / K)
n = 0
# chunks left out: the web's static mystery box at the bus (the Godot box is built in code), Juggernog (cut for now),
# the static barrels (now live ones) and the crates (no collision, can't break)
SKIP = {25, 33, 55, 56, 57, 59, 68, 69, 79, 83, 85, 88, 89, 90, 108, 109, 110, 111}   # 68, 69: the old prop Pack-a-Punch (a working one is built in code)   # 59, 108-111: the static hamster + wheel (now live); 25, 33, 79: glass (now breakable)
WM = []
for ci, c0 in enumerate(M['map']):
    if ci in SKIP: continue
    P, N, U, I = GL.decode_chunk(c0)
    WM.append({'P': P + np.array(c0['c'], np.float32), 'N': N, 'U': U, 'I': I, 'c0': c0})

# ---- second floor rework: knock doorways through the walls between the upstairs rooms (so the rooms
# make a loop with the corridor) and punch a hole in the gym balcony floor (a drop that zombies can climb).
HOLES = [  # axis of the plane's normal, plane coordinate, (u0, u1), (v0, v1) in metres; x walls: u=z v=y, y floors: u=x v=z
    ('x', -16.0, (-36.1, -33.9), (3.7, 6.4)),      # library <-> lab
    ('x', 0.0, (-39.6, -37.4), (3.7, 6.4)),        # lab <-> office
    ('y', 3.86, (-52.0, -48.0), (-20.45, -17.75)), # gym balcony floor
    ('x', 50.0, (24.0, 30.0), (-0.5, 3.6)),        # the front gate in the east fence (the bus escape smashes through it)
]
AX = {'x': (0, 2, 1), 'y': (1, 0, 2)}            # plane axis, u axis, v axis
def _clip(poly, axis, val, keep_less):
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        da = a[0][axis] - val; db = b[0][axis] - val
        ina = da <= 0 if keep_less else da >= 0; inb = db <= 0 if keep_less else db >= 0
        if ina: out.append(a)
        if ina != inb:
            t = da / (da - db)
            out.append(tuple(a[k] + (b[k] - a[k]) * t for k in range(3)))
    return out
def punch(WM, axis, at, ur, vr, tol=0.35):
    pa, ua, va = AX[axis]; at_s = at * K; tol_s = tol * K
    u0, u1 = ur[0] * K, ur[1] * K; v0, v1 = vr[0] * K, vr[1] * K
    cut = 0
    for w in WM:
        P, N, U, I = w['P'], w['N'], w['U'], w['I']
        tri = P[I]
        on = (np.abs(tri[:, :, pa] - at_s).max(1) < tol_s)
        nrm = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]); nl = np.linalg.norm(nrm, axis=1) + 1e-9
        flat = np.abs(nrm[:, pa]) / nl > 0.95
        ov = (tri[:, :, ua].min(1) < u1) & (tri[:, :, ua].max(1) > u0) & (tri[:, :, va].min(1) < v1) & (tri[:, :, va].max(1) > v0)
        sel = np.where(on & flat & ov)[0]
        if not len(sel): continue
        newP, newN, newU, newI = [], [], [], []
        base = len(P)
        for t in sel:
            poly0 = [(P[i].astype(np.float64), N[i].astype(np.float64), U[i].astype(np.float64)) for i in I[t]]
            regions = [[(ua, u0, True)], [(ua, u1, False)], [(ua, u0, False), (ua, u1, True), (va, v0, True)], [(ua, u0, False), (ua, u1, True), (va, v1, False)]]
            for reg in regions:
                poly = poly0
                for (ax, val, less) in reg:
                    if len(poly) < 3: break
                    poly = _clip(poly, ax, val, less)
                if len(poly) < 3: continue
                i0 = base + len(newP)
                for v in poly:
                    newP.append(v[0]); newN.append(v[1]); newU.append(v[2])
                for k in range(1, len(poly) - 1):
                    newI.append([i0, i0 + k, i0 + k + 1])
        keep = np.ones(len(I), bool); keep[sel] = False
        w['P'] = np.concatenate([P, np.array(newP, np.float32).reshape(-1, 3)]); w['N'] = np.concatenate([N, np.array(newN, np.float32).reshape(-1, 3)])
        w['U'] = np.concatenate([U, np.array(newU, np.float32).reshape(-1, 2)])
        w['I'] = np.concatenate([I[keep], np.array(newI, np.int64).reshape(-1, 3)]) if newI else I[keep]
        cut += len(sel)
    return cut
for h in HOLES:
    print('hole', h, 'cut triangles:', punch(WM, *h))

# ---- z-fighting: three.js kept posters, trim, lines and decals off the surface under them with polygonOffset;
# Godot has none, so find triangles from different pieces lying in the same plane and lift the smaller one.
LIFT = 0.035     # studs (1 cm)
def fix_coplanar(WM):
    tris = []
    for k, w in enumerate(WM):
        P, I = w['P'], w['I']
        a, b, c = P[I[:, 0]], P[I[:, 1]], P[I[:, 2]]
        nn = np.cross(b - a, c - a); L = np.linalg.norm(nn, axis=1); ok = L > 1e-6
        nrm = np.zeros_like(nn); nrm[ok] = nn[ok] / L[ok][:, None]
        d = (nrm * a).sum(1)
        w['tn'] = nrm; w['area'] = L / 2; w['lift'] = np.zeros(len(I), np.float32)
        for t in np.where(ok)[0]:
            tris.append((k, int(t)))
    buckets = {}
    for k, t in tris:
        w = WM[k]; nk = tuple(np.round(w['tn'][t] * 40).astype(int)); dk = int(round(float((w['tn'][t] * w['P'][w['I'][t, 0]]).sum()) / 0.05))
        buckets.setdefault((nk, dk), []).append((k, t))
    lifted = 0
    for (nk, dk), lst in buckets.items():
        grp = lst + buckets.get((nk, dk + 1), [])
        if len(set(k for k, _ in grp)) < 2: continue
        nrm = np.array(nk, np.float32); nrm /= np.linalg.norm(nrm)
        ax = np.cross(nrm, [0, 1, 0] if abs(nrm[1]) < 0.9 else [1, 0, 0]); ax /= np.linalg.norm(ax); ay = np.cross(nrm, ax)
        K_ = np.array([k for k, _ in grp]); T_ = np.array([t for _, t in grp])
        pts = np.stack([np.stack([WM[k]['P'][WM[k]['I'][t]] for k, t in grp])])[0]       # (n,3,3)
        u = pts @ ax; v = pts @ ay
        lo = np.stack([u.min(1), v.min(1)], 1); hi = np.stack([u.max(1), v.max(1)], 1)
        ar = np.array([WM[k]['area'][t] for k, t in grp])
        n_ = len(grp)
        for s0 in range(0, n_, 512):
            sl = slice(s0, min(n_, s0 + 512))
            ox = np.minimum(hi[sl, None, 0], hi[None, :, 0]) - np.maximum(lo[sl, None, 0], lo[None, :, 0])
            oy = np.minimum(hi[sl, None, 1], hi[None, :, 1]) - np.maximum(lo[sl, None, 1], lo[None, :, 1])
            ov = np.clip(ox, 0, None) * np.clip(oy, 0, None)
            diff = K_[sl, None] != K_[None, :]
            smaller = (ar[sl, None] < ar[None, :]) | ((ar[sl, None] == ar[None, :]) & (K_[sl, None] > K_[None, :]))
            hit = diff & smaller & (ov > 0.004)
            idx = np.where(hit.any(1))[0] + s0
            for i in idx:
                w = WM[K_[i]]
                if w['lift'][T_[i]] == 0: lifted += 1
                w['lift'][T_[i]] = LIFT
    # give lifted triangles their own vertices and push them out along their normal
    for w in WM:
        L = w['lift']
        if not L.any(): continue
        P, N, U, I = w['P'], w['N'], w['U'], w['I'].astype(np.int64)
        sel = np.where(L > 0)[0]
        newP = (P[I[sel]] + w['tn'][sel][:, None, :] * L[sel][:, None, None]).reshape(-1, 3)
        base = len(P)
        w['P'] = np.concatenate([P, newP]); w['N'] = np.concatenate([N, N[I[sel]].reshape(-1, 3)]); w['U'] = np.concatenate([U, U[I[sel]].reshape(-1, 2)])
        I = I.copy(); I[sel] = base + np.arange(len(sel) * 3).reshape(-1, 3); w['I'] = I
    print('lifted coplanar triangles:', lifted)
fix_coplanar(WM)

def add_f(g, name, P, N, U, I, look, png):
    """like GLB.add, but from float arrays (studs, world space) so the 1 cm lift survives"""
    if len(I) == 0: return False
    cen = (P.min(0) + P.max(0)) / 2
    Pl = ((P - cen) * g.scale).astype('<f4')
    prim = {'attributes': {'POSITION': g.accessor(Pl, 5126, 'VEC3', 34962, True), 'NORMAL': g.accessor(N.astype('<f4'), 5126, 'VEC3', 34962),
                           'TEXCOORD_0': g.accessor(U.astype('<f4'), 5126, 'VEC2', 34962)},
            'indices': g.accessor(I.reshape(-1).astype('<u2'), 5123, 'SCALAR', 34963), 'material': g.material(look, png)}
    g.meshes.append({'name': name, 'primitives': [prim]})
    g.nodes.append({'name': name, 'mesh': len(g.meshes) - 1, 'translation': [float(v) * g.scale for v in cen]})
    return True

# the school bus becomes its own model so the escape cutscene can drive it away
BUS_LO = np.array([25.9, 0.06, 25.3]) * K; BUS_HI = np.array([39.95, 3.5, 28.75]) * K
gb = GL.GLB(1 / K); nb = 0
for w in WM:
    P, I = w['P'], w['I']
    cen = P[I].mean(1)
    inb = np.all((cen > BUS_LO) & (cen < BUS_HI), axis=1)
    if not inb.any(): continue
    t = I[inb]; used, inv = np.unique(t.reshape(-1), return_inverse=True)
    look = dict(w['c0'])
    nb += 1; add_f(gb, f'bus_{nb:03d}', P[used], w['N'][used], w['U'][used], inv.reshape(-1, 3), look, png_for(look))
    w['I'] = I[~inb]
gb.write(os.path.join(PROJ, 'assets/models/bus.glb'), 'bus')
print('bus pieces', nb)
for w in WM:
    look = dict(w['c0'])
    png = png_for(look)
    P, N, U, I = w['P'], w['N'], w['U'], w['I']
    cen = P[I].mean(1); cell = np.floor(cen[:, [0, 2]] / 64.0).astype(int)
    for key in sorted(set(map(tuple, cell))):
        tt = I[(cell[:, 0] == key[0]) & (cell[:, 1] == key[1])]
        for s0 in range(0, len(tt), 4000):
            t = tt[s0:s0 + 4000]; used, inv = np.unique(t.reshape(-1), return_inverse=True)
            n += 1; add_f(g, f'map_{n:04d}', P[used], N[used], U[used], inv.reshape(-1, 3), look, png)
door_nodes = {}
for did, lst in M['doors'].items():
    door_nodes[did] = []
    for i, c in enumerate(lst):
        name = f'door_{did}_{i}'; door_nodes[did].append(name); g.add(name, c, png_for(c))
g.write(os.path.join(PROJ, 'assets/models/map.glb'), 'map')
os.makedirs(os.path.join(PROJ, 'assets/textures'), exist_ok=True)
open(os.path.join(PROJ, 'assets/textures/box.png'), 'wb').write(GL.tex_image(T, M['map'][88]['tex'], None, False, {}))
if os.environ.get('ONLY_MAP'): sys.exit(0)
for gid, lst in M['guns'].items():
    g = GL.GLB(1 / K)
    for i, c in enumerate(lst): g.add(f'{gid}_{i}', c, png_for(c))
    g.write(os.path.join(PROJ, f'assets/models/guns/{gid}.glb'), gid)
samples = []
for zi, z in enumerate(M['zombies']):
    g = GL.GLB(1 / ZS); parts = []
    for i, c in enumerate(z['parts']):
        flags = ('h' if c.get('head') else '') + ('a' if c.get('armor') else '')
        name = f"{c['joint']}__{flags or 'x'}__{i}"
        if g.add(name, c, png_for(c)):
            parts.append({'node': name, 'joint': c['joint'], 'head': bool(c.get('head')), 'armor': bool(c.get('armor')), 'c': m(c['c'], ZS),
                          'alpha': bool(c.get('tex') and TEXC[c['tex']] == 4 and not c['cut'])})
    g.write(os.path.join(PROJ, f'assets/models/zombies/z{zi:02d}.glb'), f'z{zi:02d}')
    samples.append({'kind': z['kind'], 'look': z['look'], 'scale': z['scale'], 'arm_style': z['armStyle'], 'lean': z['lean'], 'sway': z['sway'],
                    'joints': [{'n': j['n'], 'parent': j['parent'], 'pos': m(j['pos'], ZS)} for j in z['joints']], 'parts': parts})

# ---------------------------------------------------------------- map data
floors = []
for p in X['parts']:
    if p['collide']:
        floors.append({'pos': m(p['pos']), 'size': m(p['size']), 'rot': p['rot']})
ceilings = []
for p in X['parts']:
    if not p['collide'] and p['material'] != 'Glass' and abs(p['size'][2] - 0.4) < 1e-6 and p['size'][0] > 3 and p['size'][1] > 3:
        ceilings.append({'pos': m(p['pos']), 'size': m(p['size']), 'rot': p['rot']})
def ramp(x0, x1, zb, zt, rise=4.0):
    return {'x0': x0, 'x1': x1, 'z_bottom': zb, 'z_top': zt, 'rise': rise}
FLASH = {'pistol': [0, 0.02, -0.36], 'revolver': [-0.02, 0.04, -0.36], 'dmr': [-0.02, 0.05, -0.86], 'smg': [-0.02, 0.04, -0.4],
         'lmg': [-0.02, 0.05, -0.88], 'sawed': [-0.02, 0.04, -0.42], 'shotgun': [-0.04, 0.05, -0.82], 'flamer': [-0.02, -0.02, -0.72],
         'xbow': [0, 0.06, -0.62], 'bayonet': [-0.02, 0.03, -0.8], 'ak': [-0.02, 0.03, -0.62]}
ADS = {'pistol': [1.25, -0.105], 'shotgun': [1.15, -0.13], 'ak': [1.4, -0.115], 'revolver': [1.3, -0.1], 'dmr': [3.2, -0.16], 'smg': [1.35, -0.105],
       'lmg': [1.35, -0.16], 'sawed': [1.1, -0.11], 'flamer': [1.1, -0.12], 'xbow': [1.5, -0.13], 'bayonet': [1.6, -0.13]}
ADSX = {'pistol': 0, 'shotgun': 0.04}
POWER = {'pistol': 4, 'revolver': 5.5, 'dmr': 6, 'smg': 4, 'lmg': 5.5, 'sawed': 8, 'shotgun': 7, 'flamer': 1, 'xbow': 5, 'bayonet': 6.5, 'ak': 5}
BOX_RES = {'flamer': 480, 'xbow': 24, 'bayonet': 60, 'shotgun': 48, 'ak': 240, 'revolver': 72, 'dmr': 120, 'smg': 320, 'lmg': 400, 'sawed': 48}   # doubled for the Godot port
RELOAD_SND = {'pistol': 'reload', 'revolver': 'revReload', 'ak': 'akReload', 'lmg': 'lmgReload', 'shotgun': 'sgReload', 'sawed': 'breakOpen',
              'flamer': 'flameReload', 'xbow': 'xbowReload', 'bayonet': 'boltReload', 'dmr': 'reload', 'smg': 'reload'}
weapons = {}
for wid, w in X['weapons'].items():
    e = dict(w)
    e.update({'flash': FLASH[wid], 'ads_zoom': ADS[wid][0], 'ads_y': ADS[wid][1], 'ads_x': ADSX.get(wid, 0.02), 'power': POWER[wid],
              'box_reserve': BOX_RES.get(wid, -1), 'reload_snd': RELOAD_SND[wid], 'shot_snd': 'shot_' + wid})
    if wid == 'flamer': e['flame'] = True; e['range'] = 7.0
    if wid == 'xbow': e['bolt'] = True; e['blast_r'] = 4.2
    if wid == 'sawed': e['fov'] = 9
    weapons[wid] = e
WALL_RES = {'sawed': 48, 'shotgun': 36, 'revolver': 72, 'ak': 240, 'dmr': 120, 'smg': 320, 'lmg': 400}   # doubled for the Godot port
data = {
    'collision': [{'pos': m(c['pos']), 'size': m(c['size'])} for c in X['collision']],
    'floors': floors,
    'ceilings': ceilings,
    'ramps': [ramp(0.25, 3.0, -16.85, -24.0), ramp(-35.55, -32.3, -10.25, -17.4)],
    'doors': [{'id': d['id'], 'cost': d['cost'], 'label': d['label'], 'nodes': door_nodes.get(d['id'], []),
               'barriers': [{'pos': m(b['pos']), 'size': m(b['size'])} for b in d['barriers']], 'spots': [m(s) for s in d['spots']]} for d in X['doors']],
    'spawns': [{'area': s['area'], 'pos': m(s['pos'])} for s in X['spawns']],
    'wallbuys': [{'id': w['id'], 'cost': w['cost'], 'ammo': w['ammo'], 'reserve': WALL_RES[w['id']], 'spot': m(w['spot']), 'show': m(w['show'][:3])} for w in X['wallbuys']],
    'boxes': [{'name': b['name'], 'pos': m(b['pos']), 'ry': b['ry']} for b in X['boxes']],
    'start': m(X['start'][:3]) + [X['start'][3]],
    'lights': [{'pos': m(l['pos']), 'color': l['color'], 'energy': l['brightness'], 'range': round(l['range'] / K / 0.9, 2)} for l in X['lights']],
    'shafts': [{'a': m(s['a']), 'b': m(s['b']), 'r': round(s['r'] / K, 3), 'color': s['color'], 'op': s['op']} for s in M['shafts']],
    'fires': [m(f[:3]) + [f[3]] for f in X['fires']],
    'weapons': weapons,
    'box_pool': ['flamer', 'xbow', 'bayonet', 'flamer', 'xbow', 'bayonet', 'lmg', 'dmr', 'smg', 'ak', 'shotgun', 'revolver', 'sawed'],
    'zombie_samples': samples,
}
def split_for_holes(lst):
    """cut axis-aligned colliders around the HOLES so the new doorways and the balcony drop are open"""
    out = []
    for e in lst:
        p, sz = e['pos'], e['size']
        if 'rot' in e and e['rot'] != [1, 0, 0, 0, 1, 0, 0, 0, 1]:
            R = np.array(e['rot']).reshape(3, 3); ext = np.abs(R) @ np.array(sz)
        else:
            ext = np.array(sz)
        lo = np.array(p) - ext / 2; hi = np.array(p) + ext / 2
        hit = None
        for (axis, at, ur, vr) in HOLES:
            pa, ua, va = AX[axis]
            if hi[pa] - lo[pa] < 1.0 and lo[pa] - 0.05 <= at <= hi[pa] + 0.05 and lo[ua] < ur[1] and hi[ua] > ur[0] and lo[va] < vr[1] and hi[va] > vr[0]:
                hit = (pa, ua, va, ur, vr); break
        if not hit:
            out.append(e); continue
        pa, ua, va, ur, vr = hit
        pieces = [((lo[ua], ur[0]), (lo[va], hi[va])), ((ur[1], hi[ua]), (lo[va], hi[va])),
                  ((max(lo[ua], ur[0]), min(hi[ua], ur[1])), (lo[va], vr[0])), ((max(lo[ua], ur[0]), min(hi[ua], ur[1])), (vr[1], hi[va]))]
        for (a0, a1), (b0, b1) in pieces:
            if a1 - a0 < 0.05 or b1 - b0 < 0.05: continue
            nlo = lo.copy(); nhi = hi.copy(); nlo[ua], nhi[ua], nlo[va], nhi[va] = a0, a1, b0, b1
            out.append({'pos': [round(float(v), 4) for v in (nlo + nhi) / 2], 'size': [round(float(v), 4) for v in (nhi - nlo)], **({'rot': [1, 0, 0, 0, 1, 0, 0, 0, 1]} if 'rot' in e else {})})
    return out

def _cut(e):   # Juggernog and the static bus box are gone, so are their colliders
    x, z = e['pos'][0], e['pos'][2]
    if abs(x + 4.5) < 0.2 and abs(z + 43.3) < 0.2: return True     # the old prop Pack-a-Punch
    return (abs(x - 31.6) < 0.2 and abs(z + 26.45) < 0.2) or (abs(x - 30.0) < 0.2 and abs(z - 29.4) < 0.2 and e['pos'][1] < 1)
data['collision'] = [e for e in data['collision'] if not _cut(e)]
data['collision'] = split_for_holes(data['collision'])
data['floors'] = split_for_holes(data['floors'])
data['boxes'].append({'name': 'library', 'pos': [-26.6, 4.0, -32.65], 'ry': 3.141592653589793})
PI = 3.141592653589793
data['boxes'] += [{'name': 'classroom', 'pos': [20.65, 0.0, 4.5], 'ry': PI / 2}, {'name': 'boiler room', 'pos': [16.5, 4.0, -43.38], 'ry': 0.0},
                  {'name': 'west hall', 'pos': [-27.5, 0.0, -6.24], 'ry': PI}]
# the Staple Cannon: a jury-rigged office stapler, sold in the upstairs office
data['weapons']['staple'] = {'name': 'STAPLE CANNON', 'mag': 40, 'rate': 0.075, 'dmg': 16, 'pellets': 3, 'spread': 0.045, 'reload': 2.1, 'kick': 0.55,
    'pierce': 1, 'bloom': 0.002, 'bloomMax': 0.02, 'auto': True, 'flash': [0.0, 0.02, -0.42], 'ads_zoom': 1.3, 'ads_y': -0.1, 'ads_x': 0.0,
    'power': 4.5, 'box_reserve': 360, 'reload_snd': 'reload', 'shot_snd': 'shot_staple', 'staple': True}
data['box_pool'].append('staple')
# the silly weapons: Textbook Launcher (box), Dodgeball Cannon (gym + box), Trombone (band room), Detention Slip (box only, refills each wave)
W = data['weapons']
W['book'] = {'name': 'TEXTBOOK LAUNCHER', 'mag': 4, 'rate': 0.7, 'dmg': 240, 'pellets': 1, 'spread': 0.0, 'reload': 2.6, 'kick': 1.6, 'pierce': 0,
    'bloom': 0.0, 'bloomMax': 0.0, 'auto': False, 'flash': [0.0, 0.02, -0.58], 'ads_zoom': 1.15, 'ads_y': -0.11, 'ads_x': 0.0, 'power': 8,
    'box_reserve': 40, 'reload_snd': 'reload', 'shot_snd': 'shot_book', 'proj': 'book', 'fov': 5}
W['dodge'] = {'name': 'DODGEBALL CANNON', 'mag': 6, 'rate': 0.42, 'dmg': 95, 'pellets': 1, 'spread': 0.0, 'reload': 2.2, 'kick': 1.0, 'pierce': 0,
    'bloom': 0.0, 'bloomMax': 0.0, 'auto': False, 'flash': [0.0, 0.03, -0.62], 'ads_zoom': 1.2, 'ads_y': -0.1, 'ads_x': 0.0, 'power': 6,
    'box_reserve': 48, 'reload_snd': 'reload', 'shot_snd': 'shot_dodge', 'proj': 'dodge'}
W['bone'] = {'name': 'TROMBONE', 'mag': 10, 'rate': 0.62, 'dmg': 80, 'pellets': 1, 'spread': 0.0, 'reload': 1.8, 'kick': 0.9, 'pierce': 0,
    'bloom': 0.0, 'bloomMax': 0.0, 'auto': False, 'flash': [0.0, 0.05, -0.72], 'ads_zoom': 1.1, 'ads_y': -0.08, 'ads_x': 0.0, 'power': 6,
    'box_reserve': 60, 'reload_snd': 'reload', 'shot_snd': 'blat', 'cone': True}
W['slip'] = {'name': 'DETENTION SLIP', 'mag': 3, 'rate': 0.8, 'dmg': 0, 'pellets': 1, 'spread': 0.0, 'reload': 1.0, 'kick': 0.3, 'pierce': 0,
    'bloom': 0.0, 'bloomMax': 0.0, 'auto': False, 'flash': [0.0, 0.03, -0.3], 'ads_zoom': 1.1, 'ads_y': -0.09, 'ads_x': 0.0, 'power': 1,
    'box_reserve': 0, 'reload_snd': 'reload', 'shot_snd': 'poof', 'proj': 'slip', 'wonder': True}
W['bat'] = {'name': 'WILDCATS BAT', 'mag': 1, 'rate': 0.5, 'dmg': 150, 'pellets': 1, 'spread': 0.0, 'reload': 0.1, 'kick': 0.0, 'pierce': 0,
    'bloom': 0.0, 'bloomMax': 0.0, 'auto': True, 'flash': [0.0, 0.0, 0.0], 'ads_zoom': 1.0, 'ads_y': -0.27, 'ads_x': 0.27, 'power': 6,
    'box_reserve': -1, 'reload_snd': 'reload', 'shot_snd': 'batSwing', 'melee': True}
data['box_pool'] += ['book', 'dodge', 'slip', 'bat']
# Pack-a-Punch upgrades (the web game's names; magazines and reserves scaled to this port's doubled ammo)
UP = {'pistol': ('MR. BLACK', 18, -1), 'shotgun': ('GRAVEDIGGER', 8, 54), 'ak': ('RED HAND', 45, 360), 'revolver': ('THE JUDGE', 8, 108), 'dmr': ('LONG GOODBYE', 15, 180),
      'smg': ('HORNET NEST', 48, 480), 'lmg': ('IRON CHOIR', 150, 600), 'sawed': ('DOUBLE TROUBLE', 4, 72), 'flamer': ('HELLMOUTH', 180, 1200),
      'xbow': ('WIDOWMAKER', 3, 60), 'bayonet': ('LAST RITES', 8, 128), 'staple': ('STAPLE STORM', 60, 540),
      'book': ('THE ENCYCLOPEDIA', 6, 60), 'dodge': ('DOUBLEMINT DODGE', 8, 64), 'bone': ('SEVENTY-SIX TROMBONES', 14, 84), 'slip': ('SUSPENSION', 4, 0), 'bat': ('GRAND SLAM', 1, -1)}
for wid, (nm, mg, rs) in UP.items():
    data['weapons'][wid].update({'up_name': nm, 'up_mag': mg, 'up_reserve': rs})
# upstairs wall-buys: library, lab, office
data['wallbuys'] += [
    {'id': 'bayonet', 'cost': 1600, 'ammo': 800, 'reserve': 60, 'spot': [-34.4, 4.0, -34.5], 'show': [-35.72, 5.5, -34.5], 'face': [1, 0, 0], 'built': True},
    {'id': 'smg', 'cost': 1500, 'ammo': 750, 'reserve': 320, 'spot': [-8.0, 4.0, -42.4], 'show': [-8.0, 5.5, -43.72], 'face': [0, 0, 1], 'built': True},
    {'id': 'staple', 'cost': 2000, 'ammo': 1000, 'reserve': 360, 'spot': [7.5, 4.0, -42.4], 'show': [7.5, 5.5, -43.72], 'face': [0, 0, 1], 'built': True},
    {'id': 'bone', 'cost': 1200, 'ammo': 600, 'reserve': 60, 'spot': [19.5, 4.0, -42.4], 'show': [19.5, 5.5, -43.72], 'face': [0, 0, 1], 'built': True},
    {'id': 'bat', 'cost': 1250, 'ammo': 0, 'reserve': -1, 'spot': [11.8, 0.0, 16.6], 'show': [11.8, 1.6, 15.28], 'face': [0, 0, 1], 'built': True},
    {'id': 'dodge', 'cost': 1400, 'ammo': 700, 'reserve': 48, 'spot': [-55.0, 0.0, 4.3], 'show': [-55.0, 1.6, 5.62], 'face': [0, 0, -1], 'built': True},
]
data['floors'] = [e for e in data['floors'] if not _cut(e)]
json.dump(data, open(os.path.join(PROJ, 'data/map.json'), 'w'), separators=(',', ':'))

# ---------------------------------------------------------------- audio (one .ogg per sound)
AU = os.path.join(SP, 'roblox', 'audio'); SR = 44100
meta = json.load(open(os.path.join(AU, 'meta.json')))
def load(nm): return np.frombuffer(open(os.path.join(AU, nm + '.pcm'), 'rb').read(), dtype=np.int16).reshape(-1, 2).astype(np.float32) / 32767
def ogg(a, path):
    raw = (np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes()
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', '-', '-c:a', 'libvorbis', '-q:a', '5', path], input=raw, check=True)
nsfx = 0
for f in sorted(G.glob(os.path.join(AU, '*.pcm'))):
    nm = os.path.basename(f)[:-4]
    if nm.startswith('music_') or nm == 'ambience': continue
    a = load(nm); env = np.abs(a).max(1); nz = np.where(env > 0.002)[0]
    if not len(nz): continue
    end = min(len(a), nz[-1] + int(0.06 * SR), int(3.0 * SR)); a = a[:end].copy(); fl = min(len(a), int(0.03 * SR)); a[-fl:] *= np.linspace(1, 0, fl)[:, None]
    ogg(a, os.path.join(PROJ, 'assets/audio/sfx', nm + '.ogg')); nsfx += 1
for nm, mt in meta.items():
    if mt['kind'] != 'music': continue
    a = load(nm); s0 = int(mt['start'] * SR); L = int(mt['loop'] * SR)
    body = a[s0:s0 + L].copy(); tail = a[s0 + L:]; t = min(len(tail), L); body[:t] += tail[:t]
    ogg(body, os.path.join(PROJ, 'assets/audio/music', nm[6:] + '.ogg'))
a = load('ambience'); s0 = 2 * SR; L = 28 * SR; Xf = 2 * SR
body = a[s0:s0 + L].copy(); over = a[s0 + L:s0 + L + Xf]; k = np.linspace(0, 1, Xf)[:, None]
body[:Xf] = body[:Xf] * np.sqrt(k) + over * np.sqrt(1 - k)
ogg(body, os.path.join(PROJ, 'assets/audio/music', 'ambience.ogg'))
print('map tiles', n, 'samples', len(samples), 'sfx', nsfx, 'floors', len(floors), 'collision', len(data['collision']))
