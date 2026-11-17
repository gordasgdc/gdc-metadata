//! Sony XAVC / XAVC S MP4: embedded "Non-Real-Time Metadata" XML (and its `<clip>M01.XML` card sidecar) plus the first
//! sample of the `rtmd` timed-metadata track.
//!
//! Sources (public facts, no code copied): the NRT XML is plain XML (`<Item name="CaptureGammaEquation" value="s-log3-cine"/>`);
//! the rtmd record layout (16-bit header length, then 16-bit tag + 16-bit length records; 0x8000 FNumber = 2^(8-v/8192),
//! 0x8109 ExposureTime rational, 0x810b ISO) is documented in the ExifTool Sony tag table.
//! Value names are only mapped for strings that were observed or are unambiguous; anything else is shown raw, never guessed.
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Sony {
    pub gamma: Option<String>,     // CaptureGammaEquation (raw string)
    pub primaries: Option<String>, // CaptureColorPrimaries (raw string)
    pub coding: Option<String>,    // CodingEquations (YCbCr matrix label)
    pub maker: Option<String>,
    pub model: Option<String>,
    pub ltc: Option<u32>,          // LtcChange value at frameCount 0 (BCD, as written)
    pub half_step: bool,
    pub fps: Option<f64>,          // CaptureFps / FormatFps from the XML
    pub fnumber: Option<f64>,
    pub exposure: Option<(u32, u32)>,
    pub iso: Option<u32>,
    /// "embedded" (inside the MP4) or "sidecar" (card-structure XML next to the clip)
    pub origin: String,
}

pub fn curve_name(raw: &str) -> Option<&'static str> {
    match raw.to_ascii_lowercase().as_str() {
        "s-log3" | "s-log3-cine" => Some("S-Log3"),
        "s-log2" => Some("S-Log2"),
        _ => None,
    }
}
pub fn gamut_name(raw: &str) -> Option<&'static str> {
    match raw.to_ascii_lowercase().as_str() {
        "s-gamut3-cine" => Some("S-Gamut3.Cine"),
        "s-gamut3" => Some("S-Gamut3"),
        "s-gamut" => Some("S-Gamut"),
        _ => None,
    }
}
/// The gamut variant the gamma string itself implies ("s-log3-cine" is the S-Log3/S-Gamut3.Cine pairing, "s-log3" the S-Log3/S-Gamut3 one).
pub fn gamma_implied_gamut(raw: &str) -> Option<&'static str> {
    match raw.to_ascii_lowercase().as_str() { "s-log3-cine" => Some("S-Gamut3.Cine"), "s-log3" => Some("S-Gamut3"), _ => None }
}

fn attr(tag: &str, name: &str) -> Option<String> {
    let k = format!("{}=\"", name);
    let i = tag.find(&k)? + k.len();
    let j = tag[i..].find('"')?;
    Some(tag[i..i + j].to_string())
}
fn item(x: &str, name: &str) -> Option<String> {
    let k = format!("<Item name=\"{}\"", name);
    let i = x.find(&k)?;
    let j = x[i..].find('>')?;
    attr(&x[i..i + j], "value")
}
fn first_tag<'a>(x: &'a str, open: &str) -> Option<&'a str> {
    let i = x.find(open)?;
    let j = x[i..].find('>')?;
    Some(&x[i..i + j])
}

/// Parses the NRT XML text (pure function, unit-testable on synthetic XML).
pub fn parse_nrt(x: &str, origin: &str) -> Option<Sony> {
    if !x.contains("<NonRealTimeMeta") { return None; }
    let mut s = Sony { origin: origin.into(), ..Default::default() };
    s.gamma = item(x, "CaptureGammaEquation");
    s.primaries = item(x, "CaptureColorPrimaries");
    s.coding = item(x, "CodingEquations");
    if let Some(d) = first_tag(x, "<Device ") { s.maker = attr(d, "manufacturer"); s.model = attr(d, "modelName"); }
    if let Some(t) = first_tag(x, "<LtcChangeTable") { s.half_step = attr(t, "halfStep").map_or(false, |v| v == "true"); }
    let mut from = 0;
    while let Some(i) = x[from..].find("<LtcChange ") {
        let a = from + i; let b = x[a..].find('>').map(|j| a + j).unwrap_or(x.len());
        let t = &x[a..b];
        if attr(t, "frameCount").as_deref() == Some("0") { s.ltc = attr(t, "value").and_then(|v| u32::from_str_radix(&v, 16).ok()); break; }
        from = b;
    }
    if let Some(t) = first_tag(x, "<VideoFrame ") {
        s.fps = attr(t, "formatFps").or_else(|| attr(t, "captureFps")).and_then(|v| v.trim_end_matches('p').trim_end_matches('i').parse::<f64>().ok());
    }
    if s.gamma.is_none() && s.primaries.is_none() && s.model.is_none() { return None; }
    Some(s)
}

/// LTC value (BCD bytes FF SS MM HH; the 0x40 bit of FF is NOT treated as drop-frame: MediaInfo/ffprobe report non-drop for these clips) -> "HH:MM:SS:FF" at the video frame rate.
/// With HalfStep the timecode counts at half the video rate (59.94p -> 29.97): the video frame number is doubled
/// (the first video frame of a TC frame is used; confirmed against MediaInfo/ffprobe on A7 IV clips).
pub fn ltc_text(s: &Sony) -> Option<String> {
    let v = s.ltc?; let b = v.to_be_bytes();
    let bcd = |x: u8, mask: u8| ((x & mask) >> 4) * 10 + (x & 0x0f);
    let ff = bcd(b[0], 0x30) as u32; let ss = bcd(b[1], 0x70); let mm = bcd(b[2], 0x70); let hh = bcd(b[3], 0x30);
    let ff = if s.half_step { ff * 2 } else { ff };
    Some(format!("{:02}:{:02}:{:02}:{:02}", hh, mm, ss, ff))
}

/// First rtmd sample -> (FNumber, ExposureTime num/den, ISO). Pure function.
pub fn parse_rtmd(d: &[u8]) -> (Option<f64>, Option<(u32, u32)>, Option<u32>) {
    let (mut f, mut e, mut iso) = (None, None, None);
    if d.len() < 4 { return (f, e, iso); }
    let mut pos = u16::from_be_bytes([d[0], d[1]]) as usize;
    let end = d.len();
    while pos + 4 < end {
        let tag = u16::from_be_bytes([d[pos], d[pos + 1]]);
        if tag == 0 { break; }
        let mut len = u16::from_be_bytes([d[pos + 2], d[pos + 3]]) as usize;
        if tag == 0x060e { len = 0x10; } else { pos += 4; if tag == 0x8300 { continue; } }
        if pos + len > end { break; }
        let v = &d[pos..pos + len];
        match tag {
            0x8000 if len == 2 => { let r = u16::from_be_bytes([v[0], v[1]]) as f64; f = Some(2f64.powf(8.0 - r / 8192.0)); }
            0x8109 if len == 8 => { e = Some((u32::from_be_bytes([v[0], v[1], v[2], v[3]]), u32::from_be_bytes([v[4], v[5], v[6], v[7]]))); }
            0x810b if len == 2 => { iso = Some(u16::from_be_bytes([v[0], v[1]]) as u32); }
            _ => {}
        }
        pos += len;
    }
    (f, e, iso)
}

fn be32(b: &[u8]) -> u32 { u32::from_be_bytes([b[0], b[1], b[2], b[3]]) }
fn be64(b: &[u8]) -> u64 { u64::from_be_bytes(b[0..8].try_into().unwrap()) }
fn children(d: &[u8]) -> Vec<([u8; 4], usize, usize)> {
    let mut out = vec![]; let mut p = 0usize;
    while p + 8 <= d.len() {
        let mut size = be32(&d[p..]) as u64; let t: [u8; 4] = d[p + 4..p + 8].try_into().unwrap(); let mut hdr = 8usize;
        if size == 1 { if p + 16 > d.len() { break; } size = be64(&d[p + 8..]); hdr = 16; } else if size == 0 { size = (d.len() - p) as u64; }
        if size < hdr as u64 || p as u64 + size > d.len() as u64 { break; }
        out.push((t, p + hdr, p + size as usize)); p += size as usize;
    }
    out
}
fn find<'a>(d: &'a [u8], t: &[u8; 4]) -> Option<&'a [u8]> { children(d).into_iter().find(|c| &c.0 == t).map(|c| &d[c.1..c.2]) }

fn read_moov(f: &mut File) -> Option<Vec<u8>> {
    let len = f.metadata().ok()?.len(); let mut pos = 0u64;
    while pos + 8 <= len {
        f.seek(SeekFrom::Start(pos)).ok()?; let mut h = [0u8; 16]; let n = f.read(&mut h).ok()?; if n < 8 { return None; }
        let mut size = be32(&h) as u64; let mut hdr = 8u64;
        if size == 1 { if n < 16 { return None; } size = be64(&h[8..]); hdr = 16; } else if size == 0 { size = len - pos; }
        if size < hdr { return None; }
        if &h[4..8] == b"moov" {
            let pl = size - hdr; if pl > 256 * 1024 * 1024 { return None; }
            f.seek(SeekFrom::Start(pos + hdr)).ok()?; let mut buf = vec![0u8; pl as usize]; f.read_exact(&mut buf).ok()?; return Some(buf);
        }
        pos += size;
    }
    None
}

/// NRT XML stored in a top-level `meta` box (XAVC S MP4 puts it after `moov`).
fn read_top_xml(f: &mut File) -> Option<String> {
    let len = f.metadata().ok()?.len(); let mut pos = 0u64;
    while pos + 8 <= len {
        f.seek(SeekFrom::Start(pos)).ok()?; let mut h = [0u8; 16]; let n = f.read(&mut h).ok()?; if n < 8 { return None; }
        let mut size = be32(&h) as u64; let mut hdr = 8u64;
        if size == 1 { if n < 16 { return None; } size = be64(&h[8..]); hdr = 16; } else if size == 0 { size = len - pos; }
        if size < hdr { return None; }
        if &h[4..8] == b"meta" && size - hdr <= 4 * 1024 * 1024 {
            f.seek(SeekFrom::Start(pos + hdr)).ok()?; let mut buf = vec![0u8; (size - hdr) as usize]; f.read_exact(&mut buf).ok()?;
            if let Some(i) = buf.windows(16).position(|w| w == b"<NonRealTimeMeta") {
                let j = buf[i..].windows(18).position(|w| w == b"</NonRealTimeMeta>").map(|k| i + k + 18).unwrap_or(buf.len());
                return Some(String::from_utf8_lossy(&buf[i..j]).to_string());
            }
        }
        pos += size;
    }
    None
}

fn sidecar(path: &Path) -> Option<String> {
    let stem = path.file_stem()?.to_string_lossy().to_string();
    let dir = path.parent()?;
    // card structure: .../PRIVATE/M4ROOT/CLIP/C0001.MP4 + C0001M01.XML (same folder); MXF: .../XDROOT/Clip/C0001.MXF + C0001M01.XML
    for ext in ["XML", "xml"] {
        let p = dir.join(format!("{}M01.{}", stem, ext));
        if let Ok(t) = std::fs::read_to_string(&p) { return Some(t); }
    }
    None
}

/// Reads Sony NRT metadata: embedded XML first, card sidecar as the alternative; rtmd first sample for exposure.
pub fn read(path: &Path) -> Option<Sony> {
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
    let mut out: Option<Sony> = None;
    let mut rtmd: Option<Vec<u8>> = None;
    if matches!(ext.as_str(), "mp4" | "mov" | "m4v") {
        if let Ok(mut f) = File::open(path) {
            if let Some(x) = read_top_xml(&mut f) { out = parse_nrt(&x, "embedded"); }
            if let Some(moov) = read_moov(&mut f) {
                if out.is_none() {
                    if let Some(i) = moov.windows(16).position(|w| w == b"<NonRealTimeMeta") {
                        let j = moov[i..].windows(18).position(|w| w == b"</NonRealTimeMeta>").map(|k| i + k + 18).unwrap_or(moov.len());
                        out = parse_nrt(&String::from_utf8_lossy(&moov[i..j]), "embedded");
                    }
                }
                for (t, a, b) in children(&moov) {
                    if &t != b"trak" { continue; }
                    let Some(mdia) = find(&moov[a..b], b"mdia") else { continue };
                    let Some(stbl) = find(mdia, b"minf").and_then(|m| find(m, b"stbl")) else { continue };
                    let Some(stsd) = find(stbl, b"stsd") else { continue };
                    if stsd.len() < 16 || &stsd[12..16] != b"rtmd" { continue; }
                    let off = if let Some(co) = find(stbl, b"stco") { if co.len() < 12 || be32(&co[4..]) == 0 { continue } be32(&co[8..]) as u64 }
                        else if let Some(co) = find(stbl, b"co64") { if co.len() < 16 || be32(&co[4..]) == 0 { continue } be64(&co[8..]) } else { continue };
                    let size = match find(stbl, b"stsz") { Some(z) if z.len() >= 12 => { let fx = be32(&z[4..]) as u64; if fx != 0 { fx } else if z.len() >= 16 && be32(&z[8..]) > 0 { be32(&z[12..]) as u64 } else { continue } } _ => continue };
                    if size == 0 || size > 1 << 20 { continue; }
                    if f.seek(SeekFrom::Start(off)).is_ok() { let mut buf = vec![0u8; size as usize]; if f.read_exact(&mut buf).is_ok() { rtmd = Some(buf); } }
                    break;
                }
            }
        }
    }
    if out.is_none() { out = sidecar(path).and_then(|t| parse_nrt(&t, "sidecar")); }
    let mut s = out?;
    if let Some(d) = rtmd { let (f, e, i) = parse_rtmd(&d); s.fnumber = f; s.exposure = e; s.iso = i; }
    Some(s)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn xml(gamma: &str, prim: &str) -> String {
        format!(r#"<?xml version="1.0"?><NonRealTimeMeta xmlns="urn:schemas-professionalDisc:nonRealTimeMeta:ver.2.20"><LtcChangeTable tcFps="30" halfStep="true"><LtcChange frameCount="0" value="64583706" status="increment"/></LtcChangeTable><VideoFormat><VideoFrame videoCodec="AVC" captureFps="59.94p" formatFps="59.94p"/></VideoFormat><Device manufacturer="Sony" modelName="ILCE-7M4" serialNo="4294967295"/><AcquisitionRecord><Group name="CameraUnitMetadataSet"><Item name="CaptureGammaEquation" value="{gamma}"/><Item name="CaptureColorPrimaries" value="{prim}"/><Item name="CodingEquations" value="rec709"/></Group></AcquisitionRecord></NonRealTimeMeta>"#)
    }
    #[test] fn slog3_cine_pair() {
        let s = parse_nrt(&xml("s-log3-cine", "s-gamut3-cine"), "embedded").unwrap();
        assert_eq!(curve_name(s.gamma.as_deref().unwrap()), Some("S-Log3"));
        assert_eq!(gamut_name(s.primaries.as_deref().unwrap()), Some("S-Gamut3.Cine"));
        assert_eq!(s.model.as_deref(), Some("ILCE-7M4"));
    }
    #[test] fn sgamut3_is_not_sgamut3_cine() {
        let a = parse_nrt(&xml("s-log3", "s-gamut3"), "embedded").unwrap();
        let b = parse_nrt(&xml("s-log3-cine", "s-gamut3-cine"), "embedded").unwrap();
        assert_eq!(curve_name(a.gamma.as_deref().unwrap()), curve_name(b.gamma.as_deref().unwrap()));
        assert_ne!(gamut_name(a.primaries.as_deref().unwrap()), gamut_name(b.primaries.as_deref().unwrap()));
        assert_eq!(gamma_implied_gamut("s-log3"), Some("S-Gamut3"));
    }
    #[test] fn unknown_strings_not_guessed() { assert_eq!(curve_name("hlg3"), None); assert_eq!(gamut_name("x-gamut"), None); }
    #[test] fn timecode_matches_reference() {
        let s = parse_nrt(&xml("s-log3-cine", "s-gamut3-cine"), "embedded").unwrap();
        assert_eq!(ltc_text(&s).unwrap(), "06:37:58:48"); // MediaInfo/ffprobe report 06:37:58:48 for this clip
    }
    #[test] fn rtmd_exposure() {
        // header length 0x1c, then FNumber(2.8 -> v), exposure 1/128, ISO 800
        let v = ((8.0 - (2.8f64).log2()) * 8192.0).round() as u16;
        let mut d = vec![0u8; 0x1c]; d[1] = 0x1c;
        d.extend([0x80, 0x00, 0, 2]); d.extend(v.to_be_bytes());
        d.extend([0x81, 0x09, 0, 8]); d.extend(1u32.to_be_bytes()); d.extend(128u32.to_be_bytes());
        d.extend([0x81, 0x0b, 0, 2]); d.extend(800u16.to_be_bytes());
        d.extend([0, 0, 0, 0, 0, 0]);
        let (f, e, i) = parse_rtmd(&d);
        assert!((f.unwrap() - 2.8).abs() < 0.01); assert_eq!(e, Some((1, 128))); assert_eq!(i, Some(800));
    }
}
