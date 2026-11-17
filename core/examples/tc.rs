fn main(){ let p=std::env::args().nth(1).unwrap(); println!("{:?}", gdc_metadata_core::tmcd::read_start_timecode(std::path::Path::new(&p))); }
