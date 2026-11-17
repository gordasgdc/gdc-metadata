#!/usr/bin/env python3
"""Global-motion metric for the first N frames: phase-correlation shift per frame (480x270 gray). Lower = steadier."""
import sys, subprocess, numpy as np
def run(path, n=250):
    raw = subprocess.run(["ffmpeg","-v","error","-i",path,"-frames:v",str(n),"-vf","scale=480:270,format=gray","-f","rawvideo","-"],capture_output=True).stdout
    a = np.frombuffer(raw, dtype=np.uint8).reshape(-1,270,480).astype(np.float32)
    win = np.outer(np.hanning(270), np.hanning(480)); s = []
    for i in range(1, len(a)):
        R = np.fft.fft2(a[i-1]*win) * np.conj(np.fft.fft2(a[i]*win)); R /= np.abs(R)+1e-9
        y, x = np.unravel_index(np.argmax(np.fft.ifft2(R).real), (270,480)); s.append((x-480 if x>240 else x, y-270 if y>135 else y))
    s = np.array(s, float); return np.sqrt((s**2).mean()), np.cumsum(s,0).std(0)
for p in sys.argv[1:]:
    r, sd = run(p); print(f"{p.split('/')[-1]:34s} frame-to-frame rms {r:5.2f}px  position std x/y {sd[0]:5.1f}/{sd[1]:5.1f}")
