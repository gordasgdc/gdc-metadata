#!/usr/bin/env python3
"""Synthetic, recognisable demo frames (no real footage): sky, sun, hills, small figure."""
import sys, os, math
from PIL import Image, ImageDraw, ImageFilter
W, H = 480, 270
SCENES = [  # sky top, sky bottom, sun, hills far, hills near, figure
    ((34,52,92), (240,160,90), (255,224,160), (60,70,100), (28,36,48), True),
    ((20,40,70), (120,170,200), (255,250,230), (50,90,110), (20,50,55), False),
    ((70,40,80), (250,140,110), (255,210,150), (90,60,90), (35,25,40), True),
    ((30,60,90), (170,210,225), (255,255,240), (70,110,130), (35,70,80), True),
    ((20,20,28), (90,90,110), (230,230,240), (45,45,60), (18,18,24), False),
    ((90,40,40), (240,180,110), (255,235,170), (110,60,55), (45,25,25), True),
]
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
def scene(i):
    top,bot,sun,far,near,fig = SCENES[i]
    im = Image.new("RGB",(W,H)); d = ImageDraw.Draw(im)
    for y in range(H): d.line([(0,y),(W,y)], fill=lerp(top,bot,min(1,y/(H*0.68))))
    sx, sy = 120+i*55, 120
    glow = Image.new("RGB",(W,H),(0,0,0)); g = ImageDraw.Draw(glow); g.ellipse([sx-60,sy-60,sx+60,sy+60], fill=tuple(int(c*0.5) for c in sun))
    im = Image.blend(im, Image.composite(im, im, Image.new("L",(W,H),255)), 0)
    from PIL import ImageChops
    im = ImageChops.add(im, glow.filter(ImageFilter.GaussianBlur(28))); d = ImageDraw.Draw(im)
    d.ellipse([sx-20,sy-20,sx+20,sy+20], fill=sun)
    def ridge(base, amp, ph, col):
        pts=[(0,H)]+[(x, base+amp*math.sin(x/70+ph)+amp*.5*math.sin(x/23+ph*2)) for x in range(0,W+8,8)]+[(W,H)]
        d.polygon(pts, fill=col)
    ridge(170,22,i,far); ridge(205,14,i+2,near)
    if fig:
        fx, fy = 330+(i%3)*30, 200
        d.ellipse([fx-6,fy-34,fx+6,fy-22], fill=(10,10,14)); d.rounded_rectangle([fx-9,fy-22,fx+9,fy+14], 6, fill=(10,10,14))
        d.line([(fx+9,fy-14),(fx+26,fy-22)], fill=(10,10,14), width=4)  # arm with camera
        d.rectangle([fx+24,fy-28,fx+36,fy-20], fill=(10,10,14))
    return im.filter(ImageFilter.GaussianBlur(0.6))
out = sys.argv[1]
for i in range(6): scene(i).save(os.path.join(out, f"thumb_{i}.png"))
