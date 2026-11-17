use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    /// Written by the camera (maker notes / camera EXIF).
    Declared,
    /// Container signalling (QuickTime nclc, MXF essence descriptors).
    Container,
    /// Derived by GDC Metadata (pair rules, rounding, unit conversion).
    Computed,
    /// Decoded by a GDC reader from a binary stream.
    Decoded,
    /// Reported by DaVinci Resolve (never stored in the file).
    Resolve,
    /// Value from an external sidecar file.
    Sidecar,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct SourceRef {
    pub source: String,   // exiftool | gdc-tmcd | resolve ...
    pub group: String,    // ExifTool -G1 family
    pub tag: String,      // original tag name
    pub raw: Value,       // untouched value (-n)
    pub printed: Option<String>, // ExifTool printed value
    pub kind: Kind,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    Found,
    Unavailable,
    SourcesDiffer,
    Computed,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Field {
    pub id: String,
    pub section: String,
    pub value: Option<String>,
    pub status: Status,
    pub primary: Option<SourceRef>,
    pub alternates: Vec<SourceRef>,
    /// Machine-readable note code (localised by the UI): rounding, pair_rule, container_label ...
    pub note: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct RawTag {
    pub group: String,
    pub name: String,
    pub raw: Value,
    pub printed: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Clip {
    pub path: String,
    pub dir: String,
    pub name: String,
    pub ext: String,
    pub size: u64,
    pub mtime_ns: u128,
    pub ok: bool,
    pub error: Option<String>,
    pub fields: Vec<Field>,
    pub tags: Vec<RawTag>,
    pub readers: Vec<String>,
    pub scan_ms: u128,
    #[serde(default)]
    pub motion: Option<crate::motion::Motion>,
}
