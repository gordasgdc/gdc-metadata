//! Detects motion data that Gyroflow could consume. Detection only: no Gyroflow code or dependency.
//! Format hints come from public docs (docs.gyroflow.xyz "parsing gyro data"); "ready" stays false
//! until a project/profile/sync state is confirmed on a real sample.
use crate::model::RawTag;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct Embedded { pub kind: String, pub evidence: String, pub confidence: String }
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct External { pub path: String, pub kind: String }
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct GyroProject { pub path: String, pub valid_json: bool, pub has_videofile: bool, #[serde(default)] pub has_sync: bool, #[serde(default)] pub has_lens: bool, pub keys: Vec<String> }
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct GyroLog { pub path: String, pub kind: String, pub samples: u64, pub rate_hz: f64, pub duration_s: f64, pub vendor: String }
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct Motion {
    pub embedded: Vec<Embedded>,
    pub external: Vec<External>,
    pub project: Option<GyroProject>,
    /// External IMU log parsed and checked (not just present): only then is gyro "confirmed".
    #[serde(default)]
    pub gyro: Option<GyroLog>,
    /// "detected" data exists vs "ready" to stabilise (lens profile + sync confirmed). Never inferred.
    pub ready: bool,
    pub notes: Vec<String>,
}

const EXTERNAL_EXT: &[(&str, &str)] = &[("gcsv", "Gyroflow CSV"), ("bbl", "Betaflight blackbox"), ("bfl", "Betaflight blackbox")];

pub fn detect(clip: &Path, tags: &[RawTag]) -> Motion {
    let mut m = Motion::default();
    let dir = clip.parent().unwrap_or(Path::new("."));
    let stem = clip.file_stem().and_then(|s| s.to_str()).unwrap_or("");
    let name = clip.file_name().and_then(|s| s.to_str()).unwrap_or("");
    for cand in [format!("{stem}.gyroflow"), format!("{name}.gyroflow")] {
        let p = dir.join(&cand);
        if p.is_file() {
            let txt = std::fs::read_to_string(&p).ok();
            let v: Option<serde_json::Value> = txt.as_deref().and_then(|t| serde_json::from_str(t).ok());
            m.project = Some(GyroProject {
                path: p.to_string_lossy().to_string(), valid_json: v.is_some(),
                has_videofile: v.as_ref().and_then(|j| j.get("videofile")).is_some(),
                // real Gyroflow 1.7 projects always carry a `synchronization` settings block; only a non-empty `offsets` map means a sync result exists
                has_sync: v.as_ref().and_then(|j| j.get("offsets")).and_then(|o| o.as_object()).map_or(false, |m| !m.is_empty()),
                // a generic "no distortion, focal length only" profile (empty brand/model/lens) is not a lens profile
                has_lens: v.as_ref().and_then(|j| j.get("calibration_data")).map_or(false, |c| ["camera_model", "lens_model"].iter().any(|k| c.get(*k).and_then(|x| x.as_str()).map_or(false, |s| !s.trim().is_empty()))),
                keys: v.as_ref().and_then(|j| j.as_object()).map(|o| o.keys().take(12).cloned().collect()).unwrap_or_default(),
            });
            break;
        }
    }
    if let Ok(rd) = std::fs::read_dir(dir) {
        for e in rd.flatten() {
            let p = e.path();
            let fs = p.file_stem().and_then(|s| s.to_str()).unwrap_or("");
            let ext = p.extension().and_then(|s| s.to_str()).unwrap_or("").to_lowercase();
            if fs == stem || fs == name {
                if let Some((_, k)) = EXTERNAL_EXT.iter().find(|(x, _)| *x == ext) { m.external.push(External { path: p.to_string_lossy().to_string(), kind: k.to_string() }); }
            }
        }
    }
    // embedded telemetry hints: container metadata formats / vendor groups that carry IMU streams
    for t in tags {
        let v = t.printed.clone().unwrap_or_default().to_lowercase();
        let g = t.group.to_lowercase();
        let n = t.name.to_lowercase();
        let hint = if n == "metaformat" && matches!(v.as_str(), "gpmd" | "djmd" | "camm" | "rtmd") { Some(("stream", format!("{}:{} = {}", t.group, t.name, v), "hint")) }
            else if g.starts_with("gopro") || g.starts_with("insta360") { Some(("vendor group", format!("{}:{}", t.group, t.name), "hint")) }
            else if n.contains("gyro") { Some(("tag", format!("{}:{}", t.group, t.name), "hint")) }
            else { None };
        if let Some((k, ev, c)) = hint {
            if !m.embedded.iter().any(|e| e.evidence == ev) && m.embedded.len() < 6 { m.embedded.push(Embedded { kind: k.into(), evidence: ev, confidence: c.into() }); }
        }
        if n.starts_with("accelerometer") && !m.notes.iter().any(|x| x == "accel_snapshot") { m.notes.push("accel_snapshot".into()); }
    }
    for e in &m.external {
        if e.kind == "Gyroflow CSV" { if let Some(g) = parse_gcsv(Path::new(&e.path)) { m.gyro = Some(g); break; } }
    }
    // ready = confirmed IMU + a project for this clip that carries both sync and lens data
    m.ready = m.gyro.is_some() && m.project.as_ref().map_or(false, |p| p.valid_json && p.has_videofile && p.has_sync && p.has_lens);
    if m.gyro.is_some() && !m.ready { m.notes.push("gyro_needs_project".into()); }
    if m.embedded.is_empty() && m.external.is_empty() && m.project.is_none() { m.notes.push("none_detected".into()); }
    m
}

/// Parses a GCSV (docs.gyroflow.xyz "GCSV format"): header + monotonic timestamps + finite numeric rows.
pub fn parse_gcsv(p: &Path) -> Option<GyroLog> {
    let txt = std::fs::read_to_string(p).ok()?;
    let mut lines = txt.lines();
    let first = lines.next()?.trim();
    if first != "GYROFLOW IMU LOG" && first != "CAMERA IMU LOG" { return None; }
    let (mut tscale, mut vendor, mut cols) = (None::<f64>, String::new(), 0usize);
    let mut seen_header = false;
    let (mut n, mut t0, mut tlast, mut prev) = (0u64, None::<f64>, 0f64, f64::MIN);
    for l in lines {
        let l = l.trim(); if l.is_empty() { continue; }
        if !seen_header {
            if l.starts_with("t,") { cols = l.split(',').count(); seen_header = true; continue; }
            let mut it = l.splitn(2, ','); let k = it.next()?; let v = it.next().unwrap_or("");
            match k { "tscale" => tscale = v.parse().ok(), "vendor" => vendor = v.to_string(), _ => {} }
            continue;
        }
        let f: Vec<&str> = l.split(',').collect();
        if f.len() != cols { return None; }
        let t: f64 = f[0].parse().ok()?;
        if t < prev { return None; }
        if f[1..].iter().any(|x| x.parse::<f64>().map_or(true, |v| !v.is_finite())) { return None; }
        prev = t; if t0.is_none() { t0 = Some(t); } tlast = t; n += 1;
    }
    let ts = tscale?; if !seen_header || n < 20 { return None; }
    let dur = (tlast - t0?) * ts; if dur <= 0.0 { return None; }
    Some(GyroLog { path: p.to_string_lossy().into(), kind: "GCSV".into(), samples: n, rate_hz: (n as f64 - 1.0) / dur, duration_s: dur, vendor })
}
