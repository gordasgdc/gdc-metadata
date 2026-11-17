#!/usr/bin/env python3
"""Rewrite the synthetic GCSV with a given axis mapping: python3 gcsv_variant.py out.gcsv 'cols' where cols = 3 tokens from {p,y,-p,-y,0} for gx,gy,gz."""
import sys, math
F, HZ, SECS, gs = 960.0, 200, 10, 0.001
def shake(t):
    return (38*math.sin(2*math.pi*1.3*t)+14*math.sin(2*math.pi*4.1*t+1)+6*math.sin(2*math.pi*9.7*t),
            26*math.sin(2*math.pi*1.7*t+2)+10*math.sin(2*math.pi*5.3*t)+4*math.sin(2*math.pi*11.3*t+1))
def ang(t): sx, sy = shake(t); return math.atan(sx/F), math.atan(sy/F)
out, spec = sys.argv[1], sys.argv[2].split(",")
rows = []
for i in range(SECS*HZ):
    t = i/HZ; a0, b0 = ang(t-0.0005); a1, b1 = ang(t+0.0005)
    v = {"y": (a1-a0)/0.001, "p": (b1-b0)/0.001, "0": 0.0}
    def pick(s): return -v[s[1]] if s.startswith("-") else v[s]
    gx, gy, gz = (round(pick(s)/gs) for s in spec)
    rows.append(f"{i*5},{gx},{gy},{gz},0,0,16384")
hdr = ["GYROFLOW IMU LOG","version,1.3","id,gdc_synthetic_logger","orientation,XYZ","note,synthetic_demo","vendor,gdc_demo",
       "videofilename,motion_demo.mp4","tscale,0.001",f"gscale,{gs}","ascale,0.00006103515625","t,gx,gy,gz,ax,ay,az"]
open(out,"w").write("\n".join(hdr+rows)+"\n")
