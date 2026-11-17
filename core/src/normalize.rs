//! Common clip sheet: one field list for every camera, each value with provenance.
use crate::model::*;
use crate::tmcd::Timecode;
use serde_json::Value;

pub struct Idx<'a> { pub tags: &'a [RawTag] }

impl<'a> Idx<'a> {
    /// spec = "Group:Name" or "*:Name" (any group; "Track*" prefix match supported)
    pub fn find(&self, spec: &str) -> Option<&'a RawTag> {
        let (g, n) = spec.split_once(':')?;
        self.tags.iter().find(|t| {
            t.name == n && (g == "*" || t.group == g || (g.ends_with('*') && t.group.starts_with(&g[..g.len() - 1])))
        })
    }
}

fn s_of(t: &RawTag) -> String {
    match &t.raw { Value::String(s) => s.trim().to_string(), v => v.to_string() }
}
fn printed(t: &RawTag) -> String { t.printed.clone().unwrap_or_else(|| s_of(t)).trim().to_string() }
fn num(t: &RawTag) -> Option<f64> {
    match &t.raw {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => {
            let d: String = s.trim().chars().take_while(|c| c.is_ascii_digit() || *c == '.' || *c == '-').collect();
            d.parse().ok()
        }
        _ => None,
    }
}
fn sref(t: &RawTag, kind: Kind) -> SourceRef {
    SourceRef { source: "exiftool".into(), group: t.group.clone(), tag: t.name.clone(), raw: t.raw.clone(), printed: t.printed.clone(), kind }
}
fn useless(s: &str) -> bool {
    let l = s.to_lowercase();
    s.is_empty() || l.starts_with("0000:00:00") || l == "n/a" || l.starts_with("unknown") || l.starts_with("(binary") || l == "0 0 0 0" || l == "undef"
}
fn trim_num(x: f64, d: usize) -> String {
    let s = format!("{:.*}", d, x);
    if s.contains('.') { s.trim_end_matches('0').trim_end_matches('.').to_string() } else { s }
}
fn fmt_shutter(x: f64) -> String {
    if x <= 0.0 { return String::new(); }
    if x < 0.5 { format!("1/{} s", (1.0 / x).round() as i64) } else { format!("{} s", trim_num(x, 2)) }
}

#[derive(PartialEq)]
enum Cmp { Equal, Close, Differs }

type Fmt = fn(&RawTag) -> Option<String>;
type Cmpf = fn(&RawTag, &RawTag) -> Cmp;

fn norm(s: &str) -> String { s.chars().filter(|c| c.is_alphanumeric()).collect::<String>().to_lowercase() }
fn same_text(a: &RawTag, b: &RawTag) -> Cmp {
    let (x, y) = (norm(&printed(a)), norm(&printed(b)));
    if x == y || x.contains(&y) || y.contains(&x) { Cmp::Equal } else { Cmp::Differs }
}
fn same_any(_: &RawTag, _: &RawTag) -> Cmp { Cmp::Equal }
fn wb_class(t: &RawTag) -> bool { let l = printed(t).to_lowercase(); l.starts_with("auto") }
fn same_wb(a: &RawTag, b: &RawTag) -> Cmp { if wb_class(a) == wb_class(b) { Cmp::Equal } else { Cmp::Differs } }
fn same_num(a: &RawTag, b: &RawTag) -> Cmp {
    match (num(a), num(b)) {
        (Some(x), Some(y)) => {
            let m = x.abs().max(y.abs());
            if m == 0.0 || (x - y).abs() / m < 1e-6 { Cmp::Equal }
            else if (x - y).abs() / m <= 0.10 { Cmp::Close } else { Cmp::Differs }
        }
        _ => Cmp::Differs,
    }
}

fn fmt_text(t: &RawTag) -> Option<String> { let s = printed(t); if useless(&s) { None } else { Some(s) } }
fn fmt_fnum(t: &RawTag) -> Option<String> { num(t).filter(|x| *x > 0.0).map(|x| format!("f/{}", trim_num(x, 1))) }
fn fmt_iso(t: &RawTag) -> Option<String> { num(t).filter(|x| *x > 0.0).map(|x| format!("ISO {}", x as i64)) }
fn fmt_focal(t: &RawTag) -> Option<String> { num(t).filter(|x| *x > 0.0).map(|x| format!("{} mm", trim_num(x, 1))) }
fn fmt_shut(t: &RawTag) -> Option<String> { num(t).filter(|x| *x > 0.0).map(fmt_shutter) }
fn fmt_kelvin(t: &RawTag) -> Option<String> { num(t).filter(|x| *x > 500.0 && *x < 100000.0).map(|x| format!("{} K", x as i64)) }
fn fmt_wbmode(t: &RawTag) -> Option<String> {
    let s = printed(t); let l = s.to_lowercase();
    if useless(&s) { return None; }
    Some(if l.contains("kelvin") || l.contains("temperature") { "Kelvin".into() } else if l == "auto" || l.starts_with("auto") { "Auto".into() } else { s })
}

struct Cand { spec: &'static str, kind: Kind }
fn d(spec: &'static str) -> Cand { Cand { spec, kind: Kind::Declared } }
fn c(spec: &'static str) -> Cand { Cand { spec, kind: Kind::Container } }

fn field(ix: &Idx, id: &str, section: &str, cands: &[Cand], fmt: Fmt, cmp: Cmpf) -> Field {
    let mut found: Vec<(&RawTag, String, Kind)> = vec![];
    for cd in cands {
        if let Some(t) = ix.find(cd.spec) {
            if let Some(v) = fmt(t) { found.push((t, v, cd.kind.clone())); }
        }
    }
    if found.is_empty() {
        return Field { id: id.into(), section: section.into(), value: None, status: Status::Unavailable, primary: None, alternates: vec![], note: None };
    }
    let (p, v, k) = found.remove(0);
    let mut status = Status::Found; let mut note: Option<String> = None;
    let mut alts = vec![];
    for (t, av, ak) in found {
        match cmp(p, t) {
            Cmp::Equal => {}
            Cmp::Close => { if av != v && note.is_none() { note = Some("close_values".to_string()); } }
            Cmp::Differs => { status = Status::SourcesDiffer; note = Some("differs".to_string()); }
        }
        alts.push(sref(t, ak));
    }
    Field { id: id.into(), section: section.into(), value: Some(v), status, primary: Some(sref(p, k)), alternates: alts, note }
}

fn computed(id: &str, section: &str, value: &str, rule: &str, basis: &RawTag) -> Field {
    Field { id: id.into(), section: section.into(), value: Some(value.into()), status: Status::Computed,
        primary: Some(SourceRef { source: "gdc-rule".into(), group: "pair".into(), tag: rule.into(), raw: basis.raw.clone(), printed: basis.printed.clone(), kind: Kind::Computed }),
        alternates: vec![sref(basis, Kind::Declared)], note: Some("pair_rule".into()) }
}
fn unavailable(id: &str, section: &str, note: Option<&str>) -> Field {
    Field { id: id.into(), section: section.into(), value: None, status: Status::Unavailable, primary: None, alternates: vec![], note: note.map(String::from) }
}
fn declared(id: &str, section: &str, value: String, t: &RawTag, note: Option<&str>) -> Field {
    Field { id: id.into(), section: section.into(), value: Some(value), status: Status::Found, primary: Some(sref(t, Kind::Declared)), alternates: vec![], note: note.map(String::from) }
}

/// Image profile / curve / gamut. Only values the file states; pair rules are marked Computed.
fn profile_fields(ix: &Idx) -> Vec<Field> {
    let mut profile: Option<Field> = None;
    let mut curve: Option<Field> = None;
    let mut gamut: Option<Field> = None;

    if let Some(t) = ix.find("Panasonic:PhotoStyle") {
        let s = printed(t);
        if !useless(&s) {
            profile = Some(declared("picture_profile", "color", s.clone(), t, None));
            if s.to_lowercase().contains("v-log") {
                curve = Some(declared("curve", "color", "V-Log".into(), t, None));
                gamut = Some(computed("gamut", "color", "V-Gamut", "V-Log->V-Gamut", t));
            }
        }
    }
    if let Some(t) = ix.find("Canon:CanonLogVersion") {
        let s = printed(t); let l = s.to_lowercase();
        let name = if l.contains("v1") || l == "clog" { Some("Canon Log") } else if l.contains("v2") { Some("Canon Log 2") } else if l.contains("v3") { Some("Canon Log 3") } else { None };
        if let Some(n) = name { curve = Some(declared("curve", "color", n.into(), t, None)); }
    }
    if let Some(t) = ix.find("Canon:ColorSpace2") {
        let s = printed(t);
        if s.to_lowercase().contains("cinemagamut") { gamut = Some(declared("gamut", "color", "Cinema Gamut".into(), t, None)); }
        else if !useless(&s) { gamut = Some(declared("gamut", "color", s, t, None)); }
    }
    if profile.is_none() {
        if let Some(t) = ix.find("Canon:PictureStyle") {
            let s = printed(t);
            if !useless(&s) { profile = Some(declared("picture_profile", "color", format!("Picture Style: {}", s), t, None)); }
        }
    }
    if let Some(t) = ix.find("Nikon:PictureControlName") {
        let s = printed(t);
        if !useless(&s) {
            profile = Some(declared("picture_profile", "color", s.clone(), t, None));
            if s.to_lowercase().contains("n-log") {
                curve = Some(declared("curve", "color", "N-Log".into(), t, None));
                gamut = Some(computed("gamut", "color", "Rec.2020", "N-Log->Rec.2020", t));
            }
        }
    }
    if let Some(t) = ix.find("Keys:ViewingGamma") {
        let s = printed(t);
        if !useless(&s) { curve = Some(declared("curve", "color", s, t, Some("viewing_metadata"))); }
    }
    if let Some(t) = ix.find("Keys:ViewingGamut") {
        let s = printed(t);
        if !useless(&s) { gamut = Some(declared("gamut", "color", s, t, Some("viewing_metadata"))); }
    }
    let mut ul_note = false;
    if curve.is_none() {
        if let Some(t) = ix.find("Track*:CaptureGammaEquation") {
            ul_note = true;
            let mut f = unavailable("curve", "color", Some("ul_unmapped"));
            f.alternates.push(sref(t, Kind::Container));
            curve = Some(f);
        }
    }
    let _ = ul_note;
    vec![
        profile.unwrap_or_else(|| unavailable("picture_profile", "color", None)),
        curve.unwrap_or_else(|| unavailable("curve", "color", None)),
        gamut.unwrap_or_else(|| unavailable("gamut", "color", None)),
    ]
}

fn container_field(ix: &Idx, id: &str, name: &str) -> Field {
    let spec = format!("Track*:{}", name);
    match ix.find(&spec) {
        Some(t) => {
            let s = printed(t);
            if useless(&s) { return unavailable(id, "color", None); }
            let mut f = declared(id, "color", s, t, Some("container_label"));
            f.primary.as_mut().unwrap().kind = Kind::Container;
            f
        }
        None => unavailable(id, "color", None),
    }
}

pub fn build_fields(tags: &[RawTag], tc: Option<&Timecode>, size: u64, ext: &str) -> Vec<Field> {
    let ix = Idx { tags };
    let mut out = vec![];
    out.push(field(&ix, "make", "camera", &[d("IFD0:Make"), d("UserData:Make"), d("Keys:CameraManufacturer"), d("Red:Make")], fmt_text, same_text));
    out.push(field(&ix, "camera_model", "camera", &[d("IFD0:Model"), d("UserData:Model"), d("Keys:CameraType"), d("Red:Model"), d("Red:CameraModel")], fmt_text, same_text));
    out.push(field(&ix, "lens", "camera", &[d("Canon:LensModel"), d("ExifIFD:LensModel"), d("Panasonic:LensType"), d("Nikon:LensID"), d("Keys:LensType"), Cand { spec: "Composite:LensID", kind: Kind::Computed }], fmt_text, same_text));
    out.push(field(&ix, "focal_length", "camera", &[d("ExifIFD:FocalLength"), d("Canon:FocalLength"), d("Keys:FocalLength")], fmt_focal, same_num));
    out.push(field(&ix, "aperture", "exposure", &[d("ExifIFD:FNumber"), d("Canon:FNumber"), d("Keys:Aperture")], fmt_fnum, same_num));
    out.push(field(&ix, "iso", "exposure", &[d("ExifIFD:ISO"), d("Panasonic:ISO"), d("Keys:ISO")], fmt_iso, same_num));
    out.push(field(&ix, "shutter", "exposure", &[d("ExifIFD:ExposureTime"), d("Canon:ExposureTime"), d("Keys:ShutterSpeed")], fmt_shut, same_num));
    out.push(field(&ix, "wb_mode", "color", &[d("Canon:WhiteBalance"), d("Panasonic:WhiteBalance"), d("ExifIFD:WhiteBalance")], fmt_wbmode, same_wb));
    out.push(field(&ix, "wb_temp", "color", &[d("Canon:ColorTemperature"), d("Panasonic:ColorTempKelvin"), d("Nikon:WhiteBalance"), d("Red:ColorTemperature"), d("Keys:ColorTemperature")], fmt_kelvin, same_num));
    out.push(unavailable("tint", "color", Some("no_source_tag")));
    out.extend(profile_fields(&ix));
    out.push(container_field(&ix, "container_primaries", "ColorPrimaries"));
    out.push(container_field(&ix, "container_transfer", "TransferCharacteristics"));
    out.push(container_field(&ix, "container_matrix", "MatrixCoefficients"));
    out.push(field(&ix, "resolution", "file", &[c("Composite:ImageSize")], fmt_text, same_text));
    out.push(field(&ix, "frame_rate", "file", &[c("Track*:VideoFrameRate")], |t| num(t).filter(|x| *x > 0.0).map(|x| format!("{} fps", trim_num(x, 3))), same_num));
    out.push(field(&ix, "codec", "file", &[c("Track*:CompressorID"), c("Track*:VideoCodec")], fmt_text, same_text));
    // timecode: GDC tmcd reader first, ExifTool tags as alternates
    let mut tcf = unavailable("timecode", "file", None);
    if let Some(t) = tc {
        tcf = Field { id: "timecode".into(), section: "file".into(), value: Some(t.text.clone()), status: Status::Found,
            primary: Some(SourceRef { source: "gdc-tmcd".into(), group: "QuickTime".into(), tag: "tmcd".into(), raw: Value::from(t.start_counter), printed: Some(format!("{} fps{}", t.fps, if t.drop_frame { " DF" } else { "" })), kind: Kind::Decoded }),
            alternates: vec![], note: None };
    }
    if let Some(t) = ix.find("*:StartTimecode") {
        let s = printed(t);
        if !useless(&s) {
            if tcf.value.is_none() { tcf = declared("timecode", "file", s, t, None); tcf.primary.as_mut().unwrap().kind = Kind::Container; }
            else { tcf.alternates.push(sref(t, Kind::Container)); }
        }
    }
    out.push(tcf);
    // audio summary
    let n_audio = tags.iter().filter(|t| t.name == "AudioSampleRate").count();
    let ch: f64 = tags.iter().filter(|t| t.name == "AudioChannels").filter_map(num).sum();
    if n_audio > 0 {
        let rate = tags.iter().find(|t| t.name == "AudioSampleRate").and_then(num).unwrap_or(0.0);
        let bits = tags.iter().find(|t| t.name == "AudioBitsPerSample").and_then(num);
        let v = format!("{} ch · {} kHz{}", if ch > 0.0 { ch as i64 } else { n_audio as i64 }, trim_num(rate / 1000.0, 1), bits.map(|b| format!(" · {}-bit", b as i64)).unwrap_or_default());
        let t0 = tags.iter().find(|t| t.name == "AudioSampleRate").unwrap();
        out.push(Field { id: "audio".into(), section: "file".into(), value: Some(v), status: Status::Found, primary: Some(sref(t0, Kind::Container)), alternates: vec![], note: None });
    } else { out.push(unavailable("audio", "file", None)); }
    out.push(field(&ix, "date_recorded", "file", &[d("ExifIFD:DateTimeOriginal"), c("QuickTime:CreateDate"), c("Track1:TrackCreateDate")], fmt_text, same_any));
    out.push(Field { id: "file_size".into(), section: "file".into(), value: Some(format!("{} {}", trim_num(size as f64 / 1_048_576.0, 1), "MB")), status: Status::Computed, primary: None, alternates: vec![], note: Some(ext.to_lowercase()) });
    out
}
