#!/usr/bin/env python3
"""Synthetic shaky clip + matching GCSV (official format) for Gyroflow probes. No real footage."""
import sys, os, math, random, subprocess
from PIL import Image, ImageDraw, ImageFilter
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
W, H, FPS, SECS, F = 1920, 1080, 25, 10, 960.0
random.seed(7)
# textured scene bigger than the frame so the shake crop never leaves it
S = Image.new("RGB", (2600, 1500)); d = ImageDraw.Draw(S)
for y in range(1500): d.line([(0, y), (2600, y)], fill=(int(40+150*y/1500), int(70+90*y/1500), int(120+40*y/1500)))
for _ in range(900):
    x, y = random.randrange(2600), random.randrange(1500); r = random.randrange(6, 40)
    c = tuple(random.randrange(30, 255) for _ in range(3)); d.rectangle([x, y, x+r, y+r*random.choice([1,2])], fill=c)
d.ellipse([1500, 250, 1700, 450], fill=(255, 230, 170))
S = S.filter(ImageFilter.GaussianBlur(1.2)); S.save(os.path.join(out, "_scene.png"))
def shake(t):  # pixels
    return (38*math.sin(2*math.pi*1.3*t)+14*math.sin(2*math.pi*4.1*t+1)+6*math.sin(2*math.pi*9.7*t),
            26*math.sin(2*math.pi*1.7*t+2)+10*math.sin(2*math.pi*5.3*t)+4*math.sin(2*math.pi*11.3*t+1))
ex = "+".join(f"{a}*sin(2*PI*{f}*t+{p})" for a, f, p in [(38,1.3,0),(14,4.1,1),(6,9.7,0)])
ey = "+".join(f"{a}*sin(2*PI*{f}*t+{p})" for a, f, p in [(26,1.7,2),(10,5.3,0),(4,11.3,1)])
vf = f"crop={W}:{H}:x='340+{ex}':y='210+{ey}':exact=1,format=yuv420p"
mp4 = os.path.join(out, "motion_demo.mp4")
subprocess.run(["ffmpeg","-v","error","-y","-loop","1","-framerate",str(FPS),"-i",os.path.join(out,"_scene.png"),"-t",str(SECS),
                "-vf",vf,"-c:v","libx264","-crf","18","-metadata","title=GDC synthetic gyro demo",mp4],check=True)
# no-gyro control: the same picture, no sidecar
subprocess.run(["ffmpeg","-v","error","-y","-i",mp4,"-c","copy",os.path.join(out,"nogyro_demo.mp4")],check=True)
# GCSV: yaw/pitch angular rates from the pixel shake (small-angle), 200 Hz
HZ = 200; gs = 0.001; rows = []
def ang(t): sx, sy = shake(t); return math.atan(sx/F), math.atan(sy/F)
for i in range(SECS*HZ):
    t = i/HZ; a0, b0 = ang(t-0.0005); a1, b1 = ang(t+0.0005)
    gz = (a1-a0)/0.001; gx = (b1-b0)/0.001   # rad/s
    rows.append(f"{i*5},{round(gx/gs)},{round(0)},{round(gz/gs)},0,0,16384")
hdr = ["GYROFLOW IMU LOG","version,1.3","id,gdc_synthetic_logger","orientation,YxZ","note,synthetic_demo","vendor,gdc_demo",
       "videofilename,motion_demo.mp4","tscale,0.001",f"gscale,{gs}","ascale,0.00006103515625","t,gx,gy,gz,ax,ay,az"]
open(os.path.join(out,"motion_demo.gcsv"),"w").write("\n".join(hdr+rows)+"\n")
print("ok")
