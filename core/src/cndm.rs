//! Canon `cndm` timed-metadata track ("NRT Metadata" in MP4/MOV from Cinema EOS / EOS R video).
//!
//! The track samples are SMPTE-336M style KLV sets (key 060e2b34 0253 0101 0c02 0101 ..).
//! Items inside a set are `tag(2) len(2) value`. Canon does not publish the contents, so the two
//! items below are DERIVED EMPIRICALLY (matched against what DaVinci Resolve reports on real
//! clips) and are labelled as such in the UI. Only codes that were observed are mapped; any
//! other code is reported as unrecognised, never guessed.
//!
//!   item 0xe211  value = 16-byte UL ..0e150001 NN 000000  -> transfer curve code NN
//!                 02 = Canon Log 2, 07 = Canon Log 3
//!   item 0xe212  value = 16-byte UL ..0e150002 NN 000000  -> gamut code NN
//!                 02 = Cinema Gamut
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Cndm {
    pub curve_code: Option<u8>,
    pub gamut_code: Option<u8>,
}

pub fn curve_name(code: u8) -> Option<&'static str> {
    match code { 2 => Some("Canon Log 2"), 7 => Some("Canon Log 3"), _ => None }
}
pub fn gamut_name(code: u8) -> Option<&'static str> {
    match code { 2 => Some("Cinema Gamut"), _ => None }
}

const KLV_PREFIX: [u8; 4] = [0x06, 0x0e, 0x2b, 0x34];
const MAX_MOOV: u64 = 256 * 1024 * 1024;
const MAX_SAMPLE: u64 = 1024 * 1024;

fn be32(b: &[u8]) -> u32 { u32::from_be_bytes([b[0], b[1], b[2], b[3]]) }
fn be64(b: &[u8]) -> u64 { u64::from_be_bytes(b[0..8].try_into().unwrap()) }

fn ber(d: &[u8], p: usize) -> Option<(usize, usize)> {
    let b = *d.get(p)?;
    if b < 0x80 { return Some((b as usize, p + 1)); }
    let n = (b & 0x7f) as usize;
    if n == 0 || n > 4 || p + 1 + n > d.len() { return None; }
    let mut v = 0usize;
    for i in 0..n { v = (v << 8) | d[p + 1 + i] as usize; }
    Some((v, p + 1 + n))
}

/// Parses one cndm sample (pure function, unit-testable on synthetic bytes).
pub fn parse_sample(d: &[u8]) -> Cndm {
    let mut out = Cndm::default();
    let mut p = match d.windows(4).position(|w| w == KLV_PREFIX) { Some(p) => p, None => return out };
    while p + 17 <= d.len() && d[p..p + 4] == KLV_PREFIX {
        let (len, v) = match ber(d, p + 16) { Some(x) => x, None => break };
        let end = (v + len).min(d.len());
        let mut q = v;
        while q + 4 <= end {
            let tag = u16::from_be_bytes([d[q], d[q + 1]]);
            let l = u16::from_be_bytes([d[q + 2], d[q + 3]]) as usize;
            if q + 4 + l > end { break; }
            let val = &d[q + 4..q + 4 + l];
            // value must be a Canon private-use UL: 060e2b34 0401010d 0e15000K NN 000000
            if val.len() == 16 && val[..4] == KLV_PREFIX && val[8..10] == [0x0e, 0x15] && val[10] == 0x00 {
                match (tag, val[11]) {
                    (0xe211, 0x01) => out.curve_code = Some(val[12]),
                    (0xe212, 0x02) => out.gamut_code = Some(val[12]),
                    _ => {}
                }
            }
            q += 4 + l;
        }
        p = end;
    }
    out
}

fn children(d: &[u8]) -> Vec<([u8; 4], usize, usize)> {
    let mut out = vec![];
    let mut p = 0usize;
    while p + 8 <= d.len() {
        let mut size = be32(&d[p..]) as u64;
        let t: [u8; 4] = d[p + 4..p + 8].try_into().unwrap();
        let mut hdr = 8usize;
        if size == 1 { if p + 16 > d.len() { break; } size = be64(&d[p + 8..]); hdr = 16; }
        else if size == 0 { size = (d.len() - p) as u64; }
        if size < hdr as u64 || p as u64 + size > d.len() as u64 { break; }
        out.push((t, p + hdr, p + size as usize));
        p += size as usize;
    }
    out
}
fn find<'a>(d: &'a [u8], t: &[u8; 4]) -> Option<&'a [u8]> {
    children(d).into_iter().find(|c| &c.0 == t).map(|c| &d[c.1..c.2])
}

fn read_moov(f: &mut File) -> Option<Vec<u8>> {
    let len = f.metadata().ok()?.len();
    let mut pos = 0u64;
    while pos + 8 <= len {
        f.seek(SeekFrom::Start(pos)).ok()?;
        let mut h = [0u8; 16];
        let n = f.read(&mut h).ok()?;
        if n < 8 { return None; }
        let mut size = be32(&h) as u64;
        let mut hdr = 8u64;
        if size == 1 { if n < 16 { return None; } size = be64(&h[8..]); hdr = 16; }
        else if size == 0 { size = len - pos; }
        if size < hdr { return None; }
        if &h[4..8] == b"moov" {
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

/// Reads the first cndm sample of an MP4/MOV and decodes it. None = no cndm track (not an error).
pub fn read(path: &Path) -> Option<Cndm> {
    let mut f = File::open(path).ok()?;
    let moov = read_moov(&mut f)?;
    for (t, a, b) in children(&moov) {
        if &t != b"trak" { continue; }
        let mdia = match find(&moov[a..b], b"mdia") { Some(m) => m, None => continue };
        let stbl = match find(mdia, b"minf").and_then(|m| find(m, b"stbl")) { Some(s) => s, None => continue };
        let stsd = match find(stbl, b"stsd") { Some(s) => s, None => continue };
        if stsd.len() < 16 || &stsd[12..16] != b"cndm" { continue; }
        let off = if let Some(co) = find(stbl, b"stco") {
            if co.len() < 12 || be32(&co[4..]) == 0 { continue; } be32(&co[8..]) as u64
        } else if let Some(co) = find(stbl, b"co64") {
            if co.len() < 16 || be32(&co[4..]) == 0 { continue; } be64(&co[8..])
        } else { continue };
        let size = match find(stbl, b"stsz") {
            Some(z) if z.len() >= 12 => {
                let fixed = be32(&z[4..]) as u64;
                if fixed != 0 { fixed } else if z.len() >= 16 && be32(&z[8..]) > 0 { be32(&z[12..]) as u64 } else { continue }
            }
            _ => continue,
        };
        if size == 0 || size > MAX_SAMPLE { continue; }
        f.seek(SeekFrom::Start(off)).ok()?;
        let mut buf = vec![0u8; size as usize];
        f.read_exact(&mut buf).ok()?;
        return Some(parse_sample(&buf));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ul(k: u8, nn: u8) -> Vec<u8> {
        vec![0x06,0x0e,0x2b,0x34, 0x04,0x01,0x01,0x0d, 0x0e,0x15,0x00,k, nn,0,0,0]
    }
    fn item(tag: u16, v: Vec<u8>) -> Vec<u8> {
        let mut o = tag.to_be_bytes().to_vec(); o.extend((v.len() as u16).to_be_bytes()); o.extend(v); o
    }
    fn sample(curve: Option<u8>, gamut: Option<u8>) -> Vec<u8> {
        let mut body = item(0xe001, vec![1, 2, 3]);
        if let Some(c) = curve { body.extend(item(0xe211, ul(1, c))); }
        if let Some(g) = gamut { body.extend(item(0xe212, ul(2, g))); }
        let mut s = vec![0u8; 8]; // arbitrary prefix before the first key
        s.extend([0x06,0x0e,0x2b,0x34,0x02,0x53,0x01,0x01,0x0c,0x02,0x01,0x01,0x7f,0x01,0x00,0x00]);
        s.push(0x82); s.extend((body.len() as u16).to_be_bytes()); s.extend(body); s
    }

    #[test] fn canon_log_2_and_cinema_gamut() {
        let c = parse_sample(&sample(Some(2), Some(2)));
        assert_eq!(c.curve_code, Some(2)); assert_eq!(curve_name(2), Some("Canon Log 2"));
        assert_eq!(c.gamut_code, Some(2)); assert_eq!(gamut_name(2), Some("Cinema Gamut"));
    }
    #[test] fn canon_log_3_is_distinct_from_log_2() {
        let c = parse_sample(&sample(Some(7), Some(2)));
        assert_eq!(c.curve_code, Some(7));
        assert_eq!(curve_name(7), Some("Canon Log 3"));
        assert_ne!(curve_name(7), curve_name(2));
    }
    #[test] fn unknown_codes_are_not_guessed() {
        let c = parse_sample(&sample(Some(9), Some(5)));
        assert_eq!((c.curve_code, c.gamut_code), (Some(9), Some(5)));
        assert_eq!(curve_name(9), None); assert_eq!(gamut_name(5), None);
    }
    #[test] fn curve_without_gamut_and_vice_versa() {
        assert_eq!(parse_sample(&sample(Some(2), None)), Cndm { curve_code: Some(2), gamut_code: None });
        assert_eq!(parse_sample(&sample(None, Some(2))), Cndm { curve_code: None, gamut_code: Some(2) });
    }
    #[test] fn garbage_yields_nothing() {
        assert_eq!(parse_sample(&[0u8; 64]), Cndm::default());
        assert_eq!(parse_sample(&[0x06,0x0e,0x2b,0x34,1,2]), Cndm::default());
    }
}
