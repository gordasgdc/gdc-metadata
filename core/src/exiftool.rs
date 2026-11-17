use crate::model::RawTag;
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn locate() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("GDC_EXIFTOOL") {
        let p = PathBuf::from(p);
        if p.exists() { return Some(p); }
    }
    for c in ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"] {
        if Path::new(c).exists() { return Some(PathBuf::from(c)); }
    }
    None
}

pub fn version(bin: &Path) -> Option<String> {
    let o = Command::new(bin).arg("-ver").output().ok()?;
    Some(String::from_utf8_lossy(&o.stdout).trim().to_string())
}

fn run(bin: &Path, files: &[PathBuf], numeric: bool) -> Result<Vec<serde_json::Map<String, Value>>, String> {
    let mut c = Command::new(bin);
    c.args(["-json", "-G1", "-a", "-u", "-q", "-q", "-api", "largefilesupport=1"]);
    if numeric { c.arg("-n"); }
    c.args(files);
    let o = c.output().map_err(|e| format!("exiftool: {e}"))?;
    let txt = String::from_utf8_lossy(&o.stdout);
    if txt.trim().is_empty() { return Err(String::from_utf8_lossy(&o.stderr).trim().to_string()); }
    let v: Vec<Value> = serde_json::from_str(&txt).map_err(|e| format!("exiftool json: {e}"))?;
    Ok(v.into_iter().filter_map(|x| x.as_object().cloned()).collect())
}

/// Batch read: raw (-n) and printed values merged per file.
pub fn read_batch(bin: &Path, files: &[PathBuf]) -> HashMap<String, Result<Vec<RawTag>, String>> {
    let mut out = HashMap::new();
    let raw = run(bin, files, true);
    let printed = run(bin, files, false);
    match (raw, printed) {
        (Ok(r), Ok(p)) => {
            let pm: HashMap<String, serde_json::Map<String, Value>> = p
                .into_iter()
                .filter_map(|m| m.get("SourceFile").and_then(|s| s.as_str()).map(|s| (s.to_string(), m.clone())))
                .collect();
            for m in r {
                let sf = m.get("SourceFile").and_then(|s| s.as_str()).unwrap_or("").to_string();
                let pr = pm.get(&sf);
                let mut tags = vec![];
                for (k, v) in &m {
                    if k == "SourceFile" { continue; }
                    let (g, n) = match k.split_once(':') { Some((g, n)) => (g.to_string(), n.to_string()), None => ("".into(), k.clone()) };
                    let printed = pr.and_then(|p| p.get(k)).map(|x| match x { Value::String(s) => s.clone(), o => o.to_string() });
                    tags.push(RawTag { group: g, name: n, raw: v.clone(), printed });
                }
                out.insert(sf, Ok(tags));
            }
        }
        (Err(e), _) | (_, Err(e)) => {
            for f in files { out.insert(f.to_string_lossy().to_string(), Err(e.clone())); }
        }
    }
    out
}
