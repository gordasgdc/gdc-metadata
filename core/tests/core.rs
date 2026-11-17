use gdc_metadata_core::{export, scan, tmcd};
use std::path::Path;

#[test]
fn counter_formats() {
    assert_eq!(tmcd::counter_to_tc(596736, 50, false), "03:18:54:36");
    assert_eq!(tmcd::counter_to_tc(0, 25, false), "00:00:00:00");
    // 29.97 DF: frame 1800 is 00:01:00;02 (frames 00 and 01 dropped at minute 1)
    assert_eq!(tmcd::counter_to_tc(1800, 30, true), "00:01:00;02");
    assert_eq!(tmcd::counter_to_tc(17982, 30, true), "00:10:00;00");
}

#[test]
fn canon_c533_timecode_matches_resolve() {
    let p_s = std::env::var("GDC_SAMPLE_CLIP").unwrap_or_default(); let p = Path::new(&p_s);
    if p_s.is_empty() || !p.exists() { eprintln!("skipped: sample not mounted"); return; }
    let tc = tmcd::read_start_timecode(p).expect("tmcd");
    assert_eq!(tc.text, "03:18:54:36");
    assert_eq!(tc.fps, 50);
}

#[test]
fn same_name_different_dirs_are_distinct_and_sidecar_is_safe() {
    let root_s = std::env::var("GDC_SYNTH_DIR").unwrap_or_default(); let root = Path::new(&root_s);
    if root_s.is_empty() || !root.exists() { return; }
    let clips = scan::scan(root, |_| {});
    assert_eq!(clips.len(), 2);
    assert_ne!(clips[0].path, clips[1].path);
    let tmp = std::env::temp_dir().join("gdcmeta_test_out");
    let _ = std::fs::remove_dir_all(&tmp);
    for c in &clips {
        match export::write_sidecar(c, root, Some(&tmp), "test", false) { export::WriteResult::Written(p) => assert!(p.exists()), r => panic!("{:?}", r) }
    }
    assert!(tmp.join("dirA/A001.mov.gdc-metadata.json").exists());
    assert!(tmp.join("dirB/A001.mov.gdc-metadata.json").exists());
    // a foreign file with the sidecar name must never be overwritten
    let foreign = tmp.join("dirA/A001.mov.gdc-metadata.json");
    std::fs::write(&foreign, "{\"mine\":true}").unwrap();
    assert!(matches!(export::write_sidecar(&clips[0], root, Some(&tmp), "test", false), export::WriteResult::RefusedForeign(_)));
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn share_mode_strips_serials() {
    let p_s = std::env::var("GDC_SAMPLE_CLIP").unwrap_or_default(); let p = Path::new(&p_s);
    if !p.exists() { return; }
    let clips = scan::scan(p, |_| {});
    let full = serde_json::to_string(&export::sidecar_json(&clips[0], "t", false)).unwrap();
    let shared = serde_json::to_string(&export::sidecar_json(&clips[0], "t", true)).unwrap();
    assert!(full.contains("LensSerialNumber"));
    assert!(!shared.to_lowercase().contains("serial"));
    assert!(!shared.contains("/Volumes/"));
}

#[test]
fn resolve_csv_is_utf16_with_bom() {
    let p_s = std::env::var("GDC_SAMPLE_CLIP").unwrap_or_default(); let p = Path::new(&p_s);
    if !p.exists() { return; }
    let clips = scan::scan(p, |_| {});
    let b = export::resolve_csv(&clips);
    assert_eq!(&b[..2], &[0xFF, 0xFE]);
}

#[test]
fn motion_levels_follow_real_gyroflow_project() {
    use gdc_metadata_core::motion;
    let dir = std::env::temp_dir().join(format!("gdcmeta_motion_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir); std::fs::create_dir_all(&dir).unwrap();
    let clip = dir.join("m.mp4"); std::fs::write(&clip, b"x").unwrap();
    let mut g = String::from("GYROFLOW IMU LOG\nversion,1.3\nid,t\ntscale,0.001\ngscale,0.001\nt,gx,gy,gz\n");
    for i in 0..100 { g.push_str(&format!("{},1,2,3\n", i * 5)); }
    std::fs::write(dir.join("m.gcsv"), g).unwrap();
    // 1) log only -> confirmed, not ready
    let m = motion::detect(&clip, &[]);
    assert!(m.gyro.is_some() && !m.ready);
    // 2) real Gyroflow 1.7 project saved without sync -> still not ready
    let proj = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/data/gyroflow17_unsynced.gyroflow")).unwrap();
    std::fs::write(dir.join("m.gyroflow"), &proj).unwrap();
    let m = motion::detect(&clip, &[]);
    let p = m.project.as_ref().unwrap();
    assert!(p.valid_json && p.has_videofile && !p.has_sync && !p.has_lens && !m.ready);
    // 3) same project with a sync result and a named lens -> ready
    let mut j: serde_json::Value = serde_json::from_str(&proj).unwrap();
    j["offsets"] = serde_json::json!({"1000": 12.5});
    j["calibration_data"]["lens_model"] = serde_json::json!("Demo 24mm");
    std::fs::write(dir.join("m.gyroflow"), j.to_string()).unwrap();
    assert!(motion::detect(&clip, &[]).ready);
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn multi_root_scan_rejects_with_reason_and_dedupes() {
    let base = std::env::temp_dir().join("gdcmeta_multi");
    let _ = std::fs::remove_dir_all(&base);
    std::fs::create_dir_all(base.join("a")).unwrap(); std::fs::create_dir_all(base.join("b")).unwrap(); std::fs::create_dir_all(base.join("empty")).unwrap();
    std::fs::write(base.join("a/C1.mov"), b"x").unwrap();
    std::fs::write(base.join("b/C1.mov"), b"x").unwrap();
    std::fs::write(base.join("notes.txt"), b"x").unwrap();
    let roots = vec![base.join("a/C1.mov"), base.join("b"), base.join("a/C1.mov"), base.join("notes.txt"), base.join("empty"), base.join("missing.mov")];
    let (files, rejected) = scan::collect(&roots);
    assert_eq!(files.len(), 2, "same name in two folders = two clips, duplicate root skipped");
    assert_eq!(rejected.len(), 3, "txt, empty folder, missing file: {:?}", rejected);
    let mut n = 0; let clips = scan::scan_many(&roots, |e| if let scan::Event::Rejected(..) = e { n += 1 });
    assert_eq!(n, 3); assert_eq!(clips.len(), 2);
    assert_eq!(export::common_ancestor(&clips), base);
    let _ = std::fs::remove_dir_all(&base);
}
