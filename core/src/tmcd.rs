//! Minimal QuickTime/ISO-BMFF reader for the `tmcd` timecode track.
//! Source: Apple QuickTime File Format Specification (public), "Timecode Media".
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

#[derive(Debug, Clone, PartialEq)]
pub struct Timecode {
    pub text: String,
    pub fps: u32,
    pub drop_frame: bool,
    pub start_counter: i64,
    pub frames: u64,
}

const MAX_MOOV: u64 = 256 * 1024 * 1024;

fn be32(b: &[u8]) -> u32 { u32::from_be_bytes([b[0], b[1], b[2], b[3]]) }
fn be64(b: &[u8]) -> u64 { u64::from_be_bytes(b[0..8].try_into().unwrap()) }

/// Children of a box payload: (type, payload range)
fn children(d: &[u8]) -> Vec<([u8; 4], usize, usize)> {
    let mut out = vec![];
    let mut p = 0usize;
    while p + 8 <= d.len() {
        let mut size = be32(&d[p..]) as u64;
        let t: [u8; 4] = d[p + 4..p + 8].try_into().unwrap();
        let mut hdr = 8usize;
        if size == 1 {
            if p + 16 > d.len() { break; }
            size = be64(&d[p + 8..]);
            hdr = 16;
        } else if size == 0 {
            size = (d.len() - p) as u64;
        }
        if size < hdr as u64 || p as u64 + size > d.len() as u64 { break; }
        out.push((t, p + hdr, p + size as usize));
        p += size as usize;
    }
    out
}

fn find<'a>(d: &'a [u8], t: &[u8; 4]) -> Option<&'a [u8]> {
    children(d).into_iter().find(|c| &c.0 == t).map(|c| &d[c.1..c.2])
}

fn read_moov(path: &Path) -> Option<Vec<u8>> {
    let mut f = File::open(path).ok()?;
    let len = f.metadata().ok()?.len();
    let mut pos = 0u64;
    while pos + 8 <= len {
        f.seek(SeekFrom::Start(pos)).ok()?;
        let mut h = [0u8; 16];
        let n = f.read(&mut h).ok()?;
        if n < 8 { return None; }
        let mut size = be32(&h) as u64;
        let t = &h[4..8];
        let mut hdr = 8u64;
        if size == 1 { if n < 16 { return None; } size = be64(&h[8..]); hdr = 16; }
        else if size == 0 { size = len - pos; }
        if size < hdr { return None; }
        if t == b"moov" {
            let pl = size - hdr;
            if pl > MAX_MOOV { return None; }
            f.seek(SeekFrom::Start(pos + hdr)).ok()?;
            let mut buf = vec![0u8; pl as usize];
            f.read_exact(&mut buf).ok()?;
            return Some(buf);
        }
        pos += size;
    }
    None
}

/// Frame counter -> HH:MM:SS:FF (or ;FF for drop-frame, per SMPTE 12M).
pub fn counter_to_tc(counter: i64, fps: u32, drop: bool) -> String {
    let c = counter.max(0) as u64;
    let fps64 = fps as u64;
    let (f, s, m, h);
    if drop && (fps == 30 || fps == 60) {
        let d = fps64 / 30 * 2; // dropped frames per minute
        let per_min = fps64 * 60 - d;
        let per_10 = per_min * 10 + d;
        let blocks = c / per_10;
        let rem = c % per_10;
        let adj = c + d * 9 * blocks + if rem > d { d * ((rem - d) / per_min) } else { 0 };
        f = adj % fps64;
        s = (adj / fps64) % 60;
        m = (adj / (fps64 * 60)) % 60;
        h = adj / (fps64 * 3600);
    } else {
        f = c % fps64;
        s = (c / fps64) % 60;
        m = (c / (fps64 * 60)) % 60;
        h = c / (fps64 * 3600);
    }
    let sep = if drop { ';' } else { ':' };
    format!("{:02}:{:02}:{:02}{}{:02}", h, m, s, sep, f)
}

pub fn read_start_timecode(path: &Path) -> Option<Timecode> {
    let moov = read_moov(path)?;
    for (t, a, b) in children(&moov) {
        if &t != b"trak" { continue; }
        let trak = &moov[a..b];
        let mdia = find(trak, b"mdia")?;
        let hdlr = match find(mdia, b"hdlr") { Some(h) => h, None => continue };
        if hdlr.len() < 12 || &hdlr[8..12] != b"tmcd" { continue; }
        let stbl = find(find(mdia, b"minf")?, b"stbl")?;
        let stsd = find(stbl, b"stsd")?;
        // stsd: ver/flags(4) count(4) then entry: size(4) type(4) reserved(6) dref(2) reserved(4) flags(4) timescale(4) frameDur(4) nframes(1)
        if stsd.len() < 41 { continue; }
        let e = &stsd[8..];
        let flags = be32(&e[8 + 12..]);
        let nframes = e[8 + 12 + 12] as u32;
        let drop = flags & 1 == 1;
        if nframes == 0 { continue; }
        let off = if let Some(co) = find(stbl, b"stco") {
            if co.len() < 12 || be32(&co[4..]) == 0 { continue; }
            be32(&co[8..]) as u64
        } else if let Some(co) = find(stbl, b"co64") {
            if co.len() < 16 || be32(&co[4..]) == 0 { continue; }
            be64(&co[8..])
        } else { continue };
        let nsamples = find(stbl, b"stsz").map(|z| if z.len() >= 12 { be32(&z[8..]) as u64 } else { 0 }).unwrap_or(0);
        let mut f = File::open(path).ok()?;
        f.seek(SeekFrom::Start(off)).ok()?;
        let mut s = [0u8; 4];
        f.read_exact(&mut s).ok()?;
        let counter = i32::from_be_bytes(s) as i64;
        return Some(Timecode {
            text: counter_to_tc(counter, nframes, drop),
            fps: nframes, drop_frame: drop, start_counter: counter, frames: nsamples,
        });
    }
    None
}
