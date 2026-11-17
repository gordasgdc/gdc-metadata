use crate::model::*;
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};

pub const SCHEMA: &str = "gdc-metadata/1";
pub const SUFFIX: &str = ".gdc-metadata.json";

fn sensitive(t: &RawTag) -> bool {
    let n = t.name.to_lowercase();
    n.contains("serial") || n == "directory" || n == "sourcefile" || n.contains("filepath") || n.contains("gps") || n.contains("owner") || n.contains("ownername") || n.contains("userid") || t.group.to_lowercase().contains("gps")
}

/// Nearest folder that contains every clip's folder (used to lay out `--out-dir` exports without name collisions).
pub fn common_ancestor(clips: &[Clip]) -> PathBuf {
    let mut it = clips.iter().map(|c| PathBuf::from(&c.dir));
    let Some(mut acc) = it.next() else { return PathBuf::new() };
    for d in it { while !d.starts_with(&acc) { if !acc.pop() { break; } } }
    acc
}

pub fn sidecar_path(clip: &Clip, root: &Path, out_dir: Option<&Path>) -> PathBuf {
    let name = format!("{}{}", clip.name, SUFFIX);
    match out_dir {
        None => Path::new(&clip.dir).join(name),
        Some(o) => {
            let rel = Path::new(&clip.dir).strip_prefix(root).unwrap_or(Path::new(""));
            o.join(rel).join(name)
        }
    }
}

pub fn sidecar_json(clip: &Clip, exiftool_ver: &str, share: bool) -> Value {
    let tags: Vec<&RawTag> = clip.tags.iter().filter(|t| !(share && sensitive(t))).collect();
    let fields: Vec<&Field> = clip.fields.iter().collect();
    let mut src = json!({ "name": clip.name, "size": clip.size, "mtime_ns": clip.mtime_ns.to_string() });
    if !share { src["dir"] = json!(clip.dir); }
    json!({
        "schema": SCHEMA,
        "generator": { "app": "GDC Metadata", "version": env!("CARGO_PKG_VERSION"), "exiftool": exiftool_ver },
        "shared": share,
        "source": src,
        "readers": clip.readers,
        "fields": fields,
        "tags": tags,
    })
}

#[derive(Debug)]
pub enum WriteResult { Written(PathBuf), RefusedForeign(PathBuf), Error(String) }

/// Never overwrites a file that is not a GDC sidecar; never touches the video.
pub fn write_sidecar(clip: &Clip, root: &Path, out_dir: Option<&Path>, exiftool_ver: &str, share: bool) -> WriteResult {
    let p = sidecar_path(clip, root, out_dir);
    if let Ok(prev) = fs::read_to_string(&p) {
        let ours = serde_json::from_str::<Value>(&prev).ok().and_then(|v| v.get("schema").and_then(|s| s.as_str()).map(|s| s.starts_with("gdc-metadata/"))).unwrap_or(false);
        if !ours { return WriteResult::RefusedForeign(p); }
    }
    if let Some(parent) = p.parent() { if let Err(e) = fs::create_dir_all(parent) { return WriteResult::Error(e.to_string()); } }
    let body = serde_json::to_string_pretty(&sidecar_json(clip, exiftool_ver, share)).unwrap();
    let tmp = p.with_extension("json.tmp");
    match fs::write(&tmp, body).and_then(|_| fs::rename(&tmp, &p)) { Ok(_) => WriteResult::Written(p), Err(e) => WriteResult::Error(e.to_string()) }
}

fn num_of(f: &Field) -> Option<String> {
    let v = f.value.as_ref()?;
    let d: String = v.chars().skip_while(|c| !c.is_ascii_digit()).take_while(|c| c.is_ascii_digit() || *c == '.').collect();
    if d.is_empty() { None } else { Some(d) }
}

/// Resolve Media Pool metadata keys whose write path was demonstrated (SetMetadata, persisted after reopening).
/// Returns (resolve_key, value). Gamma/Color notes only from declared (not rule-derived) values.
pub fn resolve_values(clip: &Clip) -> Vec<(String, String)> {
    let get = |id: &str| clip.fields.iter().find(|f| f.id == id);
    let mut v = vec![];
    let mut put = |k: &str, val: Option<String>| { if let Some(x) = val { v.push((k.to_string(), x)); } };
    put("Camera Manufacturer", get("make").and_then(|f| f.value.clone()));
    put("Camera Type", get("camera_model").and_then(|f| f.value.clone()));
    put("Lens Type", get("lens").and_then(|f| f.value.clone()));
    put("Focal Point (mm)", get("focal_length").and_then(num_of));
    put("ISO", get("iso").and_then(num_of));
    put("White Point (Kelvin)", get("wb_temp").and_then(num_of));
    if let Some(f) = get("curve") { if f.status == Status::Found && f.note.as_deref() != Some("viewing_metadata") { put("Gamma Notes", f.value.clone()); } }
    if let Some(f) = get("gamut") { if f.status == Status::Found && f.note.as_deref() != Some("viewing_metadata") { put("Color Space Notes", f.value.clone()); } }
    v
}

pub const RESOLVE_KEYS: &[&str] = &["Camera Manufacturer", "Camera Type", "Lens Type", "Focal Point (mm)", "ISO", "White Point (Kelvin)", "Gamma Notes", "Color Space Notes"];

fn q(s: &str) -> String { if s.contains([',', '"', '\n']) { format!("\"{}\"", s.replace('"', "\"\"")) } else { s.to_string() } }

/// Resolve "Import Metadata to Media Pool" CSV: UTF-16 LE with BOM, as exported by Resolve 21.2.
pub fn resolve_csv(clips: &[Clip]) -> Vec<u8> {
    let mut s = String::new();
    let mut hdr = vec!["File Name".to_string(), "Clip Directory".to_string()];
    hdr.extend(RESOLVE_KEYS.iter().map(|k| k.to_string()));
    s.push_str(&hdr.iter().map(|h| q(h)).collect::<Vec<_>>().join(","));
    s.push_str("\r\n");
    for c in clips {
        let vals = resolve_values(c);
        let mut row = vec![q(&c.name), q(&c.dir)];
        for k in RESOLVE_KEYS { row.push(q(vals.iter().find(|(kk, _)| kk == k).map(|(_, v)| v.as_str()).unwrap_or(""))); }
        s.push_str(&row.join(","));
        s.push_str("\r\n");
    }
    let mut out = vec![0xFF, 0xFE];
    for u in s.encode_utf16() { out.extend_from_slice(&u.to_le_bytes()); }
    out
}
