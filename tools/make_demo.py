#!/usr/bin/env python3
"""Generates synthetic demo clips (fictional cameras) in the core's NDJSON shape. No real footage or metadata."""
import json, sys
def ref(group, tag, raw, printed=None, kind="declared", source="exiftool"):
    return {"source": source, "group": group, "tag": tag, "raw": raw, "printed": printed if printed is not None else str(raw), "kind": kind}
def F(id_, section, value, status="found", primary=None, alts=None, note=None):
    return {"id": id_, "section": section, "value": value, "status": status, "primary": primary, "alternates": alts or [], "note": note}
def U(id_, section, note=None): return F(id_, section, None, "unavailable", None, [], note)
SEC = {"make":"camera","camera_model":"camera","lens":"camera","focal_length":"camera","aperture":"exposure","iso":"exposure","shutter":"exposure","wb_mode":"color","wb_temp":"color","tint":"color","picture_profile":"color","curve":"color","gamut":"color","container_primaries":"color","container_transfer":"color","container_matrix":"color","resolution":"file","frame_rate":"file","codec":"file","timecode":"file","audio":"file","date_recorded":"file","file_size":"file"}
ORDER = list(SEC)
def clip(dirn, name, ext, size, fields, ntags=48):
    fl = {f["id"]: f for f in fields}
    full = [fl.get(i) or U(i, SEC[i], "no_source_tag" if i == "tint" else None) for i in ORDER]
    tags = [{"group": g, "name": n, "raw": v, "printed": str(v)} for g, n, v in [
        ("Aurora", "ModelID", 1017), ("Aurora", "FirmwareVersion", "2.1.0"), ("Aurora", "SensorMode", "S35 6K"), ("Aurora", "RecFormat", "XQ 10-bit 4:2:2"),
        ("ExifIFD", "ExposureProgram", 1), ("ExifIFD", "MeteringMode", 5), ("ExifIFD", "ColorSpace", 1), ("QuickTime", "MajorBrand", "qt  "),
        ("Track1", "ImageWidth", 3840), ("Track1", "ImageHeight", 2160), ("Track1", "BitDepth", 10), ("Track2", "AudioSampleRate", 48000)] + [("Aurora", f"Custom{i:02d}", i * 7) for i in range(ntags)]]
    return {"path": f"/Demo/{dirn}/{name}", "dir": f"/Demo/{dirn}", "name": name, "ext": ext, "size": size, "ok": True, "error": None, "fields": full, "tags": tags, "readers": ["exiftool", "gdc-tmcd"] if any(f["id"] == "timecode" and f["value"] for f in fields) else ["exiftool"], "mtime_ns": 0, "scan_ms": 12}

def common(res, fps, codec, tc, container="Unspecified"):
    return [F("resolution","file",res,primary=ref("Composite","ImageSize",res.replace("x"," "),res,"container")),
            F("frame_rate","file",f"{fps} fps",primary=ref("Track1","VideoFrameRate",fps,None,"container")),
            F("codec","file",codec,primary=ref("Track1","CompressorID",codec,None,"container")),
            F("timecode","file",tc,primary=ref("QuickTime","tmcd",0,"25 fps","decoded","gdc-tmcd")) if tc else U("timecode","file"),
            F("audio","file","4 ch · 48 kHz · 24-bit",primary=ref("Track2","AudioSampleRate",48000,None,"container")),
            F("container_primaries","color",container,primary=ref("Track1","ColorPrimaries",2,container,"container"),note="container_label"),
            F("container_transfer","color",container,primary=ref("Track1","TransferCharacteristics",2,container,"container"),note="container_label"),
            F("container_matrix","color","BT.709",primary=ref("Track1","MatrixCoefficients",1,"BT.709","container"),note="container_label")]

clips = []
# 0: rich data
clips.append(clip("CAM_A","C0001.mov","mov",812_000_000,[
    F("make","camera","Aurora",primary=ref("IFD0","Make","Aurora")), F("camera_model","camera","Aurora Cine C1",primary=ref("IFD0","Model","Aurora Cine C1")),
    F("lens","camera","AU 35mm T1.5 Prime",primary=ref("Aurora","LensModel","AU 35mm T1.5 Prime")), F("focal_length","camera","35 mm",primary=ref("ExifIFD","FocalLength",35)),
    F("aperture","exposure","f/1.5",primary=ref("ExifIFD","FNumber",1.5)), F("iso","exposure","ISO 800",primary=ref("ExifIFD","ISO",800)), F("shutter","exposure","1/50 s",primary=ref("ExifIFD","ExposureTime",0.02,"1/50")),
    F("wb_mode","color","Kelvin",primary=ref("Aurora","WhiteBalance","Manual Temperature (Kelvin)")), F("wb_temp","color","5600 K",primary=ref("Aurora","ColorTemperature",5600)),
    F("picture_profile","color","Aurora Log",primary=ref("Aurora","PictureProfile","Aurora Log")), F("curve","color","Aurora Log",primary=ref("Aurora","GammaCurve","Aurora Log")), F("gamut","color","Aurora Wide Gamut",primary=ref("Aurora","ColorGamut","Aurora Wide Gamut")),
    F("date_recorded","file","2026:03:14 10:22:41",primary=ref("ExifIFD","DateTimeOriginal","2026:03:14 10:22:41")), F("file_size","file","774.3 MB","computed",note="mov"),
] + common("3840x2160",25,"hvc1","10:22:41:00")))
# 1: auto WB, close values, profile unavailable
clips.append(clip("CAM_A","C0002.mov","mov",430_000_000,[
    F("make","camera","Aurora",primary=ref("IFD0","Make","Aurora")), F("camera_model","camera","Aurora Cine C1",primary=ref("IFD0","Model","Aurora Cine C1")),
    F("lens","camera","AU 50mm T1.5 Prime",primary=ref("Aurora","LensModel","AU 50mm T1.5 Prime")), F("focal_length","camera","50 mm",primary=ref("ExifIFD","FocalLength",50)),
    F("aperture","exposure","f/1.4","found",ref("ExifIFD","FNumber",1.4),[ref("Aurora","FNumber",1.4768)],"close_values"), F("iso","exposure","ISO 800",primary=ref("ExifIFD","ISO",800)),
    F("shutter","exposure","1/100 s","found",ref("ExifIFD","ExposureTime",0.01,"1/100"),[ref("Aurora","ExposureTime",0.00984)],"close_values"),
    F("wb_mode","color","Auto",primary=ref("Aurora","WhiteBalance",0,"Auto")), F("wb_temp","color","5100 K",primary=ref("Aurora","ColorTemperature",5100)),
    F("date_recorded","file","2026:03:14 10:31:02",primary=ref("ExifIFD","DateTimeOriginal","2026:03:14 10:31:02")), F("file_size","file","410.0 MB","computed",note="mov"),
] + common("3840x2160",25,"hvc1","10:31:02:12")))
# 2: same name A001.mov in CAM_A, little data
clips.append(clip("CAM_A","A001.mov","mov",210_000_000,[
    F("make","camera","Meridian",primary=ref("IFD0","Make","Meridian")), F("camera_model","camera","Meridian X3",primary=ref("IFD0","Model","Meridian X3")),
    F("iso","exposure","ISO 400",primary=ref("ExifIFD","ISO",400)),
    F("wb_mode","color","Kelvin","sources_differ",ref("Meridian","WhiteBalance","Manual Temperature (Kelvin)","Kelvin"),[ref("ExifIFD","WhiteBalance",0,"Auto")],"differs"),
    F("wb_temp","color","3200 K",primary=ref("Meridian","ColorTemperature",3200)),
    F("file_size","file","200.3 MB","computed",note="mov"),
] + common("1920x1080",24,"avc1",None,"BT.709"), ntags=20))
# 3: same name in CAM_B
clips.append(clip("CAM_B","A001.mov","mov",305_000_000,[
    F("make","camera","Meridian",primary=ref("IFD0","Make","Meridian")), F("camera_model","camera","Meridian X3",primary=ref("IFD0","Model","Meridian X3")),
    F("lens","camera","MX 24-70mm F2.8",primary=ref("Meridian","LensModel","MX 24-70mm F2.8")), F("focal_length","camera","24 mm",primary=ref("ExifIFD","FocalLength",24)),
    F("aperture","exposure","f/2.8",primary=ref("ExifIFD","FNumber",2.8)), F("iso","exposure","ISO 800",primary=ref("ExifIFD","ISO",800)), F("shutter","exposure","1/48 s",primary=ref("ExifIFD","ExposureTime",0.0208,"1/48")),
    F("wb_mode","color","Kelvin",primary=ref("Meridian","WhiteBalance","Kelvin")), F("wb_temp","color","4300 K",primary=ref("Meridian","ColorTemperature",4300)),
    F("picture_profile","color","M-Log",primary=ref("Meridian","PictureProfile","M-Log")), F("curve","color","M-Log",primary=ref("Meridian","GammaCurve","M-Log")),
    F("gamut","color","M-Gamut","computed",ref("","M-Log->M-Gamut","M-Log","M-Log","computed","gdc-rule"),[ref("Meridian","PictureProfile","M-Log")],"pair_rule"),
    F("file_size","file","291.1 MB","computed",note="mov"),
] + common("3840x2160",24,"apcn","01:00:00:00","BT.709")))
# 4: nothing but container (e.g. transcode)
clips.append(clip("TRANSCODES","Interview_v2.mov","mov",1_900_000_000,[F("file_size","file","1812.0 MB","computed",note="mov")] + common("1920x1080",25,"apch","00:00:00:00"), ntags=10))
# 5: raw-like
clips.append(clip("CAM_B","R0010.mxf","mxf",2_400_000_000,[
    F("camera_model","camera","Meridian X3",primary=ref("MXF","Model","Meridian X3")),
    F("curve","color",None,"unavailable",None,[ref("Track5","CaptureGammaEquation","060e2b34.0401.010d.0e170102.04","060e2b34.0401.010d.0e170102.04","container")],"ul_unmapped"),
    F("file_size","file","2289.0 MB","computed",note="mxf"),
] + common("4096x2160",24,"mxf",None), ntags=30))
G = lambda n, d: {"path": f"/Demo/{d}/{n}.gcsv", "kind": "GCSV", "samples": 6000, "rate_hz": 200.0, "duration_s": 30.0, "vendor": "demo"}
clips[0]["motion"] = {"embedded": [], "external": [{"path": "/Demo/CAM_A/C0001.gcsv", "kind": "Gyroflow CSV"}], "gyro": G("C0001", "CAM_A"), "project": {"path": "/Demo/CAM_A/C0001.gyroflow", "valid_json": True, "has_videofile": True, "has_sync": True, "has_lens": True, "keys": ["videofile", "calibration_data", "offsets", "stabilization"]}, "ready": True, "notes": []}
clips[1]["motion"] = {"embedded": [{"kind": "stream", "evidence": "Track7:MetaFormat = gpmd", "confidence": "hint"}], "external": [], "gyro": None, "project": None, "ready": False, "notes": []}
clips[2]["motion"] = {"embedded": [], "external": [{"path": "/Demo/CAM_A/A001.gcsv", "kind": "Gyroflow CSV"}], "gyro": G("A001", "CAM_A"), "project": None, "ready": False, "notes": ["gyro_needs_project"]}
for c in clips[3:]: c["motion"] = {"embedded": [], "external": [], "gyro": None, "project": None, "ready": False, "notes": ["none_detected"]}
with open(sys.argv[1], "w") as f:
    for c in clips: f.write(json.dumps(c) + "\n")
print(len(clips), "demo clips")
