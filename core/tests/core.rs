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

// ---- input gamut / transfer curve (Canon cndm) --------------------------------------------------
use gdc_metadata_core::cndm::Cndm;
use gdc_metadata_core::model::RawTag;
use gdc_metadata_core::normalize::build_fields;

fn tag(group: &str, name: &str, raw: serde_json::Value, printed: &str) -> RawTag {
    RawTag { group: group.into(), name: name.into(), raw, printed: Some(printed.into()) }
}
fn fld<'a>(v: &'a [gdc_metadata_core::model::Field], id: &str) -> &'a gdc_metadata_core::model::Field { v.iter().find(|f| f.id == id).unwrap() }

#[test]
fn cndm_log2_and_log3_are_distinguished_and_independent() {
    let l2 = build_fields(&[], None, Some(&Cndm { curve_code: Some(2), gamut_code: Some(2) }), None, 0, "mp4");
    let l3 = build_fields(&[], None, Some(&Cndm { curve_code: Some(7), gamut_code: Some(2) }), None, 0, "mp4");
    assert_eq!(fld(&l2, "curve").value.as_deref(), Some("Canon Log 2"));
    assert_eq!(fld(&l3, "curve").value.as_deref(), Some("Canon Log 3"));
    assert_eq!(fld(&l2, "gamut").value.as_deref(), Some("Cinema Gamut"));
    // curve present while gamut absent, and the reverse
    let only_curve = build_fields(&[], None, Some(&Cndm { curve_code: Some(2), gamut_code: None }), None, 0, "mp4");
    assert!(fld(&only_curve, "curve").value.is_some() && fld(&only_curve, "gamut").value.is_none());
    let only_gamut = build_fields(&[], None, Some(&Cndm { curve_code: None, gamut_code: Some(2) }), None, 0, "mp4");
    assert!(fld(&only_gamut, "curve").value.is_none() && fld(&only_gamut, "gamut").value.is_some());
}

#[test]
fn unknown_cndm_code_is_reported_not_guessed_and_no_data_stays_unassigned() {
    let f = build_fields(&[], None, Some(&Cndm { curve_code: Some(9), gamut_code: Some(5) }), None, 0, "mp4");
    assert!(fld(&f, "curve").value.is_none()); assert_eq!(fld(&f, "curve").note.as_deref(), Some("cndm_unmapped"));
    assert!(fld(&f, "gamut").value.is_none());
    let none = build_fields(&[], None, None, None, 0, "mp4");
    assert!(fld(&none, "curve").value.is_none() && fld(&none, "gamut").value.is_none());
    // brand/model alone never assigns anything
    let brand = build_fields(&[tag("IFD0", "Make", "Canon".into(), "Canon"), tag("IFD0", "Model", "Canon EOS R5".into(), "Canon EOS R5")], None, None, None, 0, "mp4");
    assert!(fld(&brand, "curve").value.is_none() && fld(&brand, "gamut").value.is_none());
}

#[test]
fn canon_maker_note_hint_is_not_a_detection_and_disagreement_shows_both() {
    let hints = [tag("Canon", "CanonLogVersion", 3.into(), "CLogV3"), tag("Canon", "ColorSpace2", 2.into(), "CinemaGamut")];
    let f = build_fields(&hints, None, None, None, 0, "mp4");
    assert!(fld(&f, "curve").value.is_none()); assert_eq!(fld(&f, "curve").note.as_deref(), Some("maker_hint"));
    assert_eq!(fld(&f, "curve").alternates.len(), 1);
    // cndm says Log 2 while a maker tag says Log 3 -> both values kept, flagged
    let g = build_fields(&hints, None, Some(&Cndm { curve_code: Some(2), gamut_code: Some(2) }), None, 0, "mp4");
    assert_eq!(fld(&g, "curve").value.as_deref(), Some("Canon Log 2"));
    assert_eq!(fld(&g, "curve").status, gdc_metadata_core::model::Status::SourcesDiffer);
    assert_eq!(fld(&g, "curve").alternates.len(), 1);
    // the cndm gamut agrees with the maker tag -> found, not a conflict
    assert_eq!(fld(&g, "gamut").status, gdc_metadata_core::model::Status::Found);
}

#[test]
fn canon_cndm_real_clips_when_mounted() {
    // local-only proof on private clips: GDC_CNDM_CL2 / GDC_CNDM_CL3 point to Canon Log 2 / Canon Log 3 MP4 files
    for (var, want) in [("GDC_CNDM_CL2", Some(2u8)), ("GDC_CNDM_CL3", Some(7u8))] {
        let p_s = std::env::var(var).unwrap_or_default(); let p = Path::new(&p_s);
        if p_s.is_empty() || !p.exists() { eprintln!("skipped {var}"); continue; }
        let c = gdc_metadata_core::cndm::read(p).expect("cndm track");
        assert_eq!(c.curve_code, want); assert_eq!(c.gamut_code, Some(2));
    }
}

#[test]
fn confirmation_overrides_with_provenance_and_maps_resolve_names() {
    use gdc_metadata_core::{export, model::*};
    let mk = |id: &str| Field { id: id.into(), section: "color".into(), value: None, status: Status::Unavailable, primary: None, alternates: vec![], note: None };
    let mut c = Clip { path: "/x/a.mov".into(), dir: "/x".into(), name: "a.mov".into(), ext: "mov".into(), size: 1, mtime_ns: 0, scan_ms: 0, ok: true, error: None, fields: vec![mk("curve"), mk("gamut")], tags: vec![], readers: vec![], motion: None };
    assert!(export::resolve_input_space(&c).is_none());
    export::apply_confirmation(&mut c, Some("S-Log3"), Some("S-Gamut3"));
    let (v, _) = export::resolve_input_space(&c).unwrap();
    assert_eq!(v, "S-Gamut3/S-Log3");
    export::apply_confirmation(&mut c, Some("S-Log3"), Some("S-Gamut3.Cine"));
    assert_eq!(export::resolve_input_space(&c).unwrap().0, "S-Gamut3.Cine/S-Log3");
    assert_eq!(c.fields[1].status, Status::Confirmed);
    export::apply_confirmation(&mut c, Some("N-Log"), Some("Rec.2020"));
    assert!(export::resolve_input_space(&c).is_none());
}
