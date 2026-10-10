"""Paint the set-dressing textures the web game drew on canvases: posters, gym banners, court lines, papers."""
import random, math
from PIL import Image, ImageDraw, ImageFont
random.seed(11)
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'DeadShift', 'assets', 'textures') + os.sep
BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'
SCRAWL = '/usr/share/fonts/truetype/dejavu/DejaVuSerif-Italic.ttf'
def rnd(a, b): return random.uniform(a, b)
def hexc(h, a=255):
    h = h.lstrip('#'); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)
def stain(d, x, y, r, col): d.ellipse([x - r, y - r, x + r, y + r], fill=col)

PCOLS, PROWS, PW, PH = 8, 4, 128, 256
POSTERS = [
  ['#8a1a1e', '#ece4d0', ['GO', 'WILD', 'CATS!'], 'paw'], ['#1e2a5a', '#e8d070', ['HOME', 'COMING', "'99"], 'crown'], ['#1e5a3a', '#e8e8d0', ['SCIENCE', 'FAIR', 'FRI 7PM'], 'atom'], ['#e8e2d0', '#a01818', ['SAY NO', 'TO', 'DRUGS'], 'bar'],
  ['#d8c040', '#1a1a1a', ['VOTE', 'JENNA', 'CLASS PRES'], 'star'], ['#e8a0b0', '#5a1a2a', ['BAKE', 'SALE', '$1'], 'circle'], ['#e8e4d8', '#1a1a1a', ['MISSING', 'KYLE M.', 'AGE 16'], 'photo'], ['#3a6a9a', '#f0e8d0', ['READ!'], 'book'],
  ['#1a1430', '#d8b0f0', ['PROM', 'NIGHT', 'UNDER THE', 'STARS'], 'stars'], ['#6a1a6a', '#f0d040', ['JOIN', 'THE', 'BAND'], 'note'], ['#e8e8e0', '#2a5a8a', ['WASH', 'YOUR', 'HANDS'], 'drops'], ['#d8d0b8', '#8a1a1a', ['NO', 'RUNNING', 'IN HALLS'], 'bar'],
  ['#c8a020', '#1a1a1a', ['QUARAN', 'TINE', 'STAY', 'INDOORS'], 'hazard'], ['#e8e4d8', '#a01818', ['EVAC', 'ROUTE'], 'map'], ['#2a2a2a', '#e8e8e8', ['CHESS', 'CLUB', 'TUES'], 'checker'], ['#f0ecd8', '#1a1a1a', ['MENU', 'MON PIZZA', 'TUE TACO', 'WED ???'], 'none'],
  ['#8a1a1e', '#ece4d0', ['VARSITY', 'TRY', 'OUTS'], 'ball'], ['#3a5a3a', '#e8e0c0', ['STAY', 'IN', 'SCHOOL'], 'bar'], ['#1a1a1a', '#c8a040', ['DRAMA', 'CLUB', 'HAMLET'], 'mask'], ['#f0ecd8', '#1a1a1a', ['LOST', 'CAT', 'MITTENS'], 'photo'],
  ['#d8d0c0', '#5a0a0a', ['THEY', 'ARE IN', 'THE', 'WALLS'], 'scrawl'], ['#2a3a6a', '#e8d070', ['CLASS', 'OF', '1999'], 'star'], ['#c81e24', '#f0e8d0', ['SPIRIT', 'WEEK'], 'paw'], ['#e8e4d8', '#7a0a0a', ['HELP'], 'hands'],
  ['#e8e4d8', '#1a1a1a', ['PERIODIC', 'TABLE'], 'table'], ['#a8c8e0', '#1a1a1a', ['WORLD'], 'world'], ['#f0d0a0', '#5a2a1a', ['BE', 'KIND'], 'circle'], ['#c81e24', '#f0f0f0', ['FIRE', 'DRILL', 'EXIT', 'LEFT'], 'bar'],
  ['#5a3a8a', '#f0e0f0', ['YEAR', 'BOOK', 'PHOTOS'], 'photo'], ['#e8c860', '#1a1a1a', ['STUDENT', 'OF THE', 'MONTH'], 'photo'], ['#1e2a5a', '#f0e8d0', ['WILDCATS', 'VS', 'EAGLES', 'FRI 7'], 'ball'], ['#d8d0c0', '#5a0a0a', ["DON'T", 'GO', 'OUTSIDE'], 'scrawl'],
]
atlas = Image.new('RGBA', (PCOLS * PW, PROWS * PH), (0, 0, 0, 0))
for i, (bg, fg, lines, art) in enumerate(POSTERS):
    im = Image.new('RGB', (PW, PH), hexc(bg)[:3]); g = ImageDraw.Draw(im, 'RGBA')
    g.rectangle([6, 6, PW - 7, PH - 7], outline=hexc(fg, 128), width=3)
    scrawl = art == 'scrawl'
    fs = int(min(34, 220 / max(len(l) for l in lines) * 1.6))
    font = ImageFont.truetype(SCRAWL if scrawl else BOLD, fs)
    while fs > 10 and max(g.textlength(l, font=font) for l in lines) > PW - 16:
        fs -= 1; font = ImageFont.truetype(SCRAWL if scrawl else BOLD, fs)
    for k, l in enumerate(lines):
        y = (40 + k * (fs + 6)) if scrawl else (46 + k * (fs + 8))
        if scrawl:
            t = Image.new('RGBA', (PW, fs + 12), (0, 0, 0, 0)); ImageDraw.Draw(t).text((PW / 2, fs / 2 + 4), l, fill=hexc(fg), font=font, anchor='mm')
            t = t.rotate(rnd(-7, 7), resample=Image.NEAREST); im.paste(t, (0, int(y - fs)), t)
        else:
            g.text((PW / 2, y), l, fill=hexc(fg), font=font, anchor='ms')
    ay = 46 + len(lines) * (fs + 8) + 10; cx = PW / 2; F = hexc(fg); B = hexc(bg)
    if art == 'paw':
        g.ellipse([cx - 20, ay + 18, cx + 20, ay + 50], fill=F)
        for k in range(4): stain(g, cx - 24 + k * 16, ay + 8 + (-4 if k % 3 else 4), 7, F)
    elif art == 'crown': g.polygon([(cx - 30, ay + 40), (cx - 30, ay + 10), (cx - 15, ay + 25), (cx, ay), (cx + 15, ay + 25), (cx + 30, ay + 10), (cx + 30, ay + 40)], fill=F)
    elif art == 'atom':
        for k in range(3):
            t = Image.new('RGBA', (80, 80), (0, 0, 0, 0)); ImageDraw.Draw(t).ellipse([6, 29, 74, 51], outline=F, width=3)
            t = t.rotate(math.degrees(k * 1.05), resample=Image.NEAREST); im.paste(t, (int(cx - 40), int(ay - 10)), t)
        stain(g, cx, ay + 30, 5, F)
    elif art in ('star', 'stars'):
        n = 6 if art == 'stars' else 1
        for k in range(n):
            sx = rnd(20, PW - 20) if n > 1 else cx; sy = rnd(ay, PH - 20) if n > 1 else ay + 30; r = 7 if n > 1 else 24
            g.polygon([(sx + math.cos(j * math.pi / 5 - math.pi / 2) * (r * 0.45 if j % 2 else r), sy + math.sin(j * math.pi / 5 - math.pi / 2) * (r * 0.45 if j % 2 else r)) for j in range(10)], fill=F)
    elif art == 'circle': stain(g, cx, ay + 32, 26, F)
    elif art == 'photo': g.rectangle([cx - 30, ay, cx + 30, ay + 70], fill=hexc('#6a6a66')); stain(g, cx, ay + 26, 14, hexc('#3a3a38')); g.rectangle([cx - 22, ay + 44, cx + 22, ay + 70], fill=hexc('#3a3a38'))
    elif art == 'book': g.rectangle([cx - 34, ay + 10, cx - 2, ay + 54], fill=F); g.rectangle([cx + 2, ay + 10, cx + 34, ay + 54], fill=F)
    elif art == 'note': g.ellipse([cx - 22, ay + 43, cx + 2, ay + 61], fill=F); g.rectangle([cx, ay, cx + 4, ay + 52], fill=F); g.rectangle([cx, ay, cx + 22, ay + 6], fill=F)
    elif art == 'drops':
        for k in range(3): stain(g, cx - 26 + k * 26, ay + 36, 9, F)
    elif art == 'bar': g.rectangle([14, ay + 10, PW - 14, ay + 18], fill=F)
    elif art == 'hazard':
        for k in range(8): g.rectangle([k * 16, PH - 40, k * 16 + 16, PH - 10], fill=F if k % 2 else B)
    elif art == 'map':
        g.rectangle([14, ay, PW - 14, ay + 80], outline=F, width=2); g.line([(30, ay + 70), (30, ay + 20), (100, ay + 20)], fill=F, width=2)
        g.polygon([(100, ay + 12), (112, ay + 20), (100, ay + 28)], fill=hexc('#a01818'))
    elif art == 'checker':
        for y in range(4):
            for x in range(4):
                if (x + y) % 2: g.rectangle([cx - 32 + x * 16, ay + y * 16, cx - 16 + x * 16, ay + 16 + y * 16], fill=F)
    elif art == 'ball': g.ellipse([cx - 34, ay + 10, cx + 34, ay + 50], fill=F); g.line([(cx - 12, ay + 30), (cx + 12, ay + 30)], fill=B, width=3)
    elif art == 'mask': stain(g, cx - 16, ay + 30, 18, F); stain(g, cx + 16, ay + 34, 18, F)
    elif art == 'hands':
        for k in range(5):
            hx, hy = rnd(20, PW - 20), rnd(ay - 40, PH - 40)
            g.ellipse([hx - 14, hy - 18, hx + 14, hy + 18], fill=hexc('#7a0a0a'))
            for f in range(4): g.rectangle([hx - 12 + f * 7, hy - 34, hx - 7 + f * 7, hy - 16], fill=hexc('#7a0a0a'))
    elif art == 'table':
        cs = ['#d86a6a', '#e8c86a', '#7ac87a', '#6a9ad8', '#c88ad8']
        for y in range(7):
            for x in range(9):
                if not (y == 0 and 0 < x < 8) and not (y < 3 and 1 < x < 7 and y > 0):
                    g.rectangle([8 + x * 12.5, 100 + y * 15, 19 + x * 12.5, 113 + y * 15], fill=hexc(cs[(x + y) % 5]))
    elif art == 'world':
        for (x, y, rx, ry) in [(36, 110, 22, 30), (44, 170, 12, 26), (80, 104, 26, 18), (86, 150, 14, 24), (104, 196, 12, 8)]: g.ellipse([x - rx, y - ry, x + rx, y + ry], fill=hexc('#5a8a4a'))
    for k in range(3): stain(g, rnd(0, PW), rnd(0, PH), rnd(14, 40), (60, 45, 20, 56))
    g.rectangle([PW / 2 - 14, 0, PW / 2 + 14, 10], fill=(230, 226, 200, 153))
    if random.random() < 0.35:
        ex, ey = rnd(20, PW - 20), rnd(60, PH - 30); g.ellipse([ex - rnd(8, 20), ey - rnd(10, 30), ex + rnd(8, 20), ey + rnd(10, 30)], fill=(110, 10, 10, 190))
        for k in range(4): x = rnd(10, PW - 10); y = rnd(60, PH - 60); g.rectangle([x, y, x + 2, y + rnd(10, 50)], fill=(110, 10, 10, 190))
    if random.random() < 0.4:
        c = random.randint(0, 3); x0 = PW if c % 2 else 0; y0 = PH if c > 1 else 0; sx = -1 if c % 2 else 1; sy = -1 if c > 1 else 1
        m = Image.new('L', (PW, PH), 0); ImageDraw.Draw(m).polygon([(x0, y0), (x0 + sx * rnd(20, 50), y0), (x0 + sx * rnd(4, 14), y0 + sy * rnd(10, 30)), (x0, y0 + sy * rnd(30, 70))], fill=255)
        im = im.convert('RGBA'); a = im.getchannel('A'); a.paste(0, mask=m); im.putalpha(a)
    atlas.paste(im.convert('RGBA'), ((i % PCOLS) * PW, (i // PCOLS) * PH))
atlas.save(OUT + 'posters.png')

# gym banners: 4 rows
ban = Image.new('RGB', (512, 512), (0, 0, 0)); g = ImageDraw.Draw(ban, 'RGBA'); f = ImageFont.truetype(BOLD, 54); cut = None
for i, (bg, fg, t) in enumerate([['#8a1a1e', '#ece4d0', 'GO WILDCATS!'], ['#1e2a5a', '#e8d070', 'STATE CHAMPS 1998'], ['#ece4d0', '#8a1a1e', 'HOMECOMING 99'], ['#8a1a1e', '#ece4d0', 'BEAT THE EAGLES']]):
    oy = i * 128; g.rectangle([0, oy, 511, oy + 127], fill=hexc(bg))
    tw = g.textlength(t, font=f); fz = f if tw < 490 else ImageFont.truetype(BOLD, int(54 * 490 / tw))
    g.text((256, oy + 84), t, fill=hexc(fg), font=fz, anchor='ms')
    for k in range(5): stain(g, rnd(0, 512), oy + rnd(0, 128), rnd(10, 30), (40, 30, 20, 54))
    if i == 3:
        cut = Image.new('L', (512, 512), 0); ImageDraw.Draw(cut).polygon([(230, oy), (270, oy), (250, oy + 60), (280, oy + 128), (220, oy + 128), (245, oy + 64)], fill=255)
ban = ban.convert('RGBA'); a = ban.getchannel('A'); a.paste(0, mask=cut); ban.putalpha(a)
ban.save(OUT + 'banners.png')

# court lines + paw at centre court
c = Image.new('RGBA', (256, 256), (0, 0, 0, 0)); g = ImageDraw.Draw(c, 'RGBA'); W = (240, 235, 220, 216); R = (160, 20, 20, 216)
g.rectangle([6, 6, 250, 250], outline=W, width=3); g.line([(128, 6), (128, 250)], fill=W, width=3); g.ellipse([98, 98, 158, 158], outline=W, width=3)
g.rectangle([6, 90, 56, 166], outline=R, width=3); g.rectangle([200, 90, 250, 166], outline=R, width=3)
g.arc([6 - 90, 128 - 90, 6 + 90, 128 + 90], -80, 80, fill=R, width=3); g.arc([250 - 90, 128 - 90, 250 + 90, 128 + 90], 100, 260, fill=R, width=3)
P = (150, 20, 24, 204); g.ellipse([108, 120, 148, 152], fill=P)
for k in range(4): stain(g, 104 + k * 16, 112 + (-4 if k % 3 else 4), 7, P)
g.text((128, 172), 'WILDCATS', fill=P, font=ImageFont.truetype(BOLD, 14), anchor='ms')
c.save(OUT + 'court.png')

# loose paper (a few variants on one strip): worksheets, notes, a flyer
pp = Image.new('RGBA', (128, 32), (0, 0, 0, 0)); g = ImageDraw.Draw(pp)
for k in range(4):
    ox = k * 32; base = [(236, 232, 214, 255), (226, 222, 200, 255), (232, 200, 120, 255), (240, 236, 224, 255)][k]
    g.rectangle([ox + 2, 3, ox + 29, 29], fill=base)
    for y in range(8, 27, 3): g.line([(ox + 5, y), (ox + rnd(16, 27), y)], fill=(150, 150, 170, 255))
    if k == 1: g.line([(ox + 6, 3), (ox + 6, 29)], fill=(210, 120, 120, 255))
    stain(g, ox + rnd(6, 26), rnd(6, 26), rnd(2, 5), (200, 180, 140, 255))
    if k == 2: stain(g, ox + rnd(8, 24), rnd(8, 24), rnd(3, 6), (120, 14, 14, 255))
pp.save(OUT + 'paper.png')

# welcome sign
w = Image.new('RGB', (256, 32), (38, 48, 31)); g = ImageDraw.Draw(w)
g.text((128, 22), 'WELCOME TO WESTFIELD HIGH', fill=(216, 207, 168), font=ImageFont.truetype(BOLD, 18), anchor='ms')
w.save(OUT + 'welcome.png')
# cafeteria menu board
mb = Image.new('RGB', (128, 96), (24, 28, 24)); g = ImageDraw.Draw(mb); ff = ImageFont.truetype(BOLD, 11)
g.rectangle([2, 2, 125, 93], outline=(140, 110, 60), width=3)
for k, l in enumerate(['TODAY', 'PIZZA  $1.25', 'TACOS  $1.50', 'MILK   $0.35', 'MYSTERY MEAT', 'RUN']):
    g.text((64, 18 + k * 14), l, fill=(230, 230, 220) if k < 5 else (200, 40, 40), font=ff, anchor='ms')
mb.save(OUT + 'menu.png')
print('dressing textures ok')
