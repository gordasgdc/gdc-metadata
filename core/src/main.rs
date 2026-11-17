use gdc_metadata_core::{export, exiftool, scan};
use serde_json::json;
use std::io::Write;
use std::path::{Path, PathBuf};

fn arg(args: &[String], flag: &str) -> Option<String> { args.iter().position(|a| a == flag).and_then(|i| args.get(i + 1)).cloned() }

fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let cmd = a.first().map(|s| s.as_str()).unwrap_or("");
    // positional paths (any number) after the command; flags with a value are skipped
    let mut roots: Vec<PathBuf> = vec![];
    let mut i = 1;
    while i < a.len() { if a[i] == "--out" || a[i] == "--out-dir" { i += 2; continue; } if !a[i].starts_with("--") { roots.push(PathBuf::from(&a[i])); } i += 1; }
    let root = roots.first().cloned();
    let ver = exiftool::locate().and_then(|b| exiftool::version(&b)).unwrap_or_else(|| "unavailable".into());
    match (cmd, root) {
        ("version", _) => println!("{}", json!({"core": env!("CARGO_PKG_VERSION"), "exiftool": ver})),
        ("scan", Some(_)) => {
            let out = std::io::stdout();
            let mut o = out.lock();
            scan::scan_many(&roots, |e| {
                let line = match e {
                    scan::Event::Found(n) => json!({"event": "found", "count": n}),
                    scan::Event::Clip(c) => json!({"event": "clip", "clip": c}),
                    scan::Event::Rejected(p, why) => json!({"event": "rejected", "path": p, "reason": why}),
                    scan::Event::Done { clips, errors, ms } => json!({"event": "done", "clips": clips, "errors": errors, "ms": ms}),
                };
                let _ = writeln!(o, "{}", line);
                let _ = o.flush();
            });
        }
        ("export", Some(_)) => {
            let out_dir = arg(&a, "--out-dir").map(PathBuf::from);
            let share = a.iter().any(|x| x == "--share");
            let clips = scan::scan_many(&roots, |_| {});
            // with --out-dir, keep each clip's folder structure below the nearest common ancestor so equal names from different folders stay distinct
            let common = export::common_ancestor(&clips);
            for c in &clips {
                let res = export::write_sidecar(c, &common, out_dir.as_deref(), &ver, share);
                println!("{}", json!({"clip": c.path, "result": format!("{:?}", res)}));
            }
        }
        ("resolve-csv", Some(_)) => {
            let clips = scan::scan_many(&roots, |_| {});
            let bytes = export::resolve_csv(&clips);
            let out = arg(&a, "--out").expect("--out required");
            std::fs::write(Path::new(&out), bytes).expect("write csv");
            println!("{}", json!({"rows": clips.len(), "out": out}));
        }
        ("resolve-plan", Some(_)) => {
            let clips = scan::scan_many(&roots, |_| {});
            let plan: Vec<_> = clips.iter().map(|c| json!({"path": c.path, "name": c.name, "dir": c.dir, "values": export::resolve_values(c)})).collect();
            println!("{}", serde_json::to_string(&plan).unwrap());
        }
        _ => { eprintln!("usage: gdc-metadata-core version | scan <path>... | export <path>... [--out-dir D] [--share] | resolve-csv <path>... --out F | resolve-plan <path>..."); std::process::exit(2); }
    }
}
