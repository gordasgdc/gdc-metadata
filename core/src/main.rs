use gdc_metadata_core::{export, exiftool, scan};
use serde_json::json;
use std::io::Write;
use std::path::{Path, PathBuf};

fn arg(args: &[String], flag: &str) -> Option<String> { args.iter().position(|a| a == flag).and_then(|i| args.get(i + 1)).cloned() }

fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let cmd = a.first().map(|s| s.as_str()).unwrap_or("");
    let root = a.get(1).map(PathBuf::from);
    let ver = exiftool::locate().and_then(|b| exiftool::version(&b)).unwrap_or_else(|| "unavailable".into());
    match (cmd, root) {
        ("version", _) => println!("{}", json!({"core": env!("CARGO_PKG_VERSION"), "exiftool": ver})),
        ("scan", Some(r)) => {
            let out = std::io::stdout();
            let mut o = out.lock();
            scan::scan(&r, |e| {
                let line = match e {
                    scan::Event::Found(n) => json!({"event": "found", "count": n}),
                    scan::Event::Clip(c) => json!({"event": "clip", "clip": c}),
                    scan::Event::Done { clips, errors, ms } => json!({"event": "done", "clips": clips, "errors": errors, "ms": ms}),
                };
                let _ = writeln!(o, "{}", line);
                let _ = o.flush();
            });
        }
        ("export", Some(r)) => {
            let out_dir = arg(&a, "--out-dir").map(PathBuf::from);
            let share = a.iter().any(|x| x == "--share");
            let clips = scan::scan(&r, |_| {});
            for c in &clips {
                let res = export::write_sidecar(c, if r.is_file() { r.parent().unwrap() } else { &r }, out_dir.as_deref(), &ver, share);
                println!("{}", json!({"clip": c.path, "result": format!("{:?}", res)}));
            }
        }
        ("resolve-csv", Some(r)) => {
            let clips = scan::scan(&r, |_| {});
            let bytes = export::resolve_csv(&clips);
            let out = arg(&a, "--out").expect("--out required");
            std::fs::write(Path::new(&out), bytes).expect("write csv");
            println!("{}", json!({"rows": clips.len(), "out": out}));
        }
        ("resolve-plan", Some(r)) => {
            let clips = scan::scan(&r, |_| {});
            let plan: Vec<_> = clips.iter().map(|c| json!({"path": c.path, "name": c.name, "dir": c.dir, "values": export::resolve_values(c)})).collect();
            println!("{}", serde_json::to_string(&plan).unwrap());
        }
        _ => { eprintln!("usage: gdc-metadata-core version | scan <path> | export <path> [--out-dir D] [--share] | resolve-csv <path> --out F | resolve-plan <path>"); std::process::exit(2); }
    }
}
