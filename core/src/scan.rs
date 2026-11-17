use crate::{exiftool, model::*, normalize, tmcd};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

const EXTS: &[&str] = &["mov", "mp4", "m4v", "mxf", "braw", "r3d", "crm", "mts", "m2ts", "avi", "mkv", "ari", "mpg", "mpeg", "dng"];

pub fn is_media(p: &Path) -> bool {
    let n = p.file_name().and_then(|s| s.to_str()).unwrap_or("");
    if n.starts_with('.') { return false; }
    p.extension().and_then(|e| e.to_str()).map(|e| EXTS.contains(&e.to_lowercase().as_str())).unwrap_or(false)
}

pub fn walk(root: &Path) -> Vec<PathBuf> {
    let mut out = vec![];
    let mut stack = vec![root.to_path_buf()];
    if root.is_file() { return if is_media(root) { vec![root.to_path_buf()] } else { vec![] }; }
    while let Some(d) = stack.pop() {
        let Ok(rd) = fs::read_dir(&d) else { continue };
        for e in rd.flatten() {
            let p = e.path();
            let n = e.file_name().to_string_lossy().to_string();
            if n.starts_with('.') { continue; }
            let Ok(ft) = e.file_type() else { continue };
            if ft.is_dir() { stack.push(p); } else if (ft.is_file() || (ft.is_symlink() && p.is_file())) && is_media(&p) { out.push(p); }
        }
    }
    out.sort();
    out
}

pub enum Event<'a> { Found(usize), Clip(&'a Clip), Rejected(&'a str, &'a str), Done { clips: usize, errors: usize, ms: u128 } }

/// Several roots (files and/or folders) in one pass: duplicates are dropped, anything that cannot be used is reported with a reason.
pub fn collect(roots: &[PathBuf]) -> (Vec<PathBuf>, Vec<(String, &'static str)>) {
    let mut files: Vec<PathBuf> = vec![];
    let mut rejected: Vec<(String, &'static str)> = vec![];
    let mut seen = std::collections::HashSet::new();
    for r in roots {
        let found = walk(r);
        if !r.exists() { rejected.push((r.to_string_lossy().to_string(), "missing")); continue; }
        if found.is_empty() { rejected.push((r.to_string_lossy().to_string(), if r.is_file() { "unsupported_type" } else { "no_media" })); continue; }
        for f in found { if seen.insert(f.clone()) { files.push(f); } }
    }
    (files, rejected)
}

pub fn scan(root: &Path, on: impl FnMut(Event)) -> Vec<Clip> { scan_many(&[root.to_path_buf()], on) }

pub fn scan_many(roots: &[PathBuf], mut on: impl FnMut(Event)) -> Vec<Clip> {
    let (files, rejected) = collect(roots);
    for (p, why) in &rejected { on(Event::Rejected(p, why)); }
    on(Event::Found(files.len()));
    let t0 = Instant::now();
    let bin = exiftool::locate();
    let mut clips = vec![];
    let mut errors = 0;
    for chunk in files.chunks(16) {
        let t1 = Instant::now();
        let mut batch = match &bin { Some(b) => exiftool::read_batch(b, chunk), None => Default::default() };
        let per = t1.elapsed().as_millis() / chunk.len().max(1) as u128;
        for f in chunk {
            let meta = fs::metadata(f).ok();
            let key = f.to_string_lossy().to_string();
            let (tags, err) = match batch.remove(&key) {
                Some(Ok(t)) => (t, None),
                Some(Err(e)) => (vec![], Some(e)),
                None => (vec![], Some(if bin.is_none() { "exiftool not found".to_string() } else { "no result for file".to_string() })),
            };
            let size = meta.as_ref().map(|m| m.len()).unwrap_or(0);
            let mtime = meta.as_ref().and_then(|m| m.modified().ok()).and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_nanos()).unwrap_or(0);
            let ext = f.extension().and_then(|e| e.to_str()).unwrap_or("").to_string();
            let tc = if matches!(ext.to_lowercase().as_str(), "mov" | "mp4" | "m4v") { tmcd::read_start_timecode(f) } else { None };
            let ok = err.is_none();
            if !ok { errors += 1; }
            let mut readers = vec![];
            if ok { readers.push("exiftool".to_string()); }
            if tc.is_some() { readers.push("gdc-tmcd".to_string()); }
            let cn = if matches!(ext.to_lowercase().as_str(), "mov" | "mp4" | "m4v") { crate::cndm::read(f) } else { None };
            if cn.as_ref().map_or(false, |c| c.curve_code.is_some() || c.gamut_code.is_some()) { readers.push("gdc-cndm".to_string()); }
            let fields = normalize::build_fields(&tags, tc.as_ref(), cn.as_ref(), size, &ext);
            let clip = Clip {
                path: key, dir: f.parent().map(|p| p.to_string_lossy().to_string()).unwrap_or_default(),
                name: f.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default(),
                ext, size, mtime_ns: mtime, ok, error: err, fields, motion: Some(crate::motion::detect(f, &tags)), tags, readers, scan_ms: per,
            };
            on(Event::Clip(&clip));
            clips.push(clip);
        }
    }
    on(Event::Done { clips: clips.len(), errors, ms: t0.elapsed().as_millis() });
    clips
}
