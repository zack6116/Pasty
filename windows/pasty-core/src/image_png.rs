use image::RgbaImage;
use sha2::{Digest, Sha256};

const PNG_SIGNATURE: [u8; 8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

pub struct ImagePNG;

impl ImagePNG {
    pub fn is_png(data: &[u8]) -> bool {
        data.len() >= 24 && data[..8] == PNG_SIGNATURE
    }

    /// PNG bytes ready to store. An already-decodable PNG is returned unchanged.
    pub fn normalized_png(data: &[u8]) -> Option<Vec<u8>> {
        if data.is_empty() {
            return None;
        }
        if Self::is_png(data) && Self::can_decode(data) {
            return Some(data.to_vec());
        }
        Self::reencoded_png(data)
    }

    pub fn pixel_label(of_png: &[u8]) -> Option<String> {
        if !Self::is_png(of_png) {
            return None;
        }
        let width = big_endian_u32(of_png, 16)?;
        let height = big_endian_u32(of_png, 20)?;
        if width == 0 || height == 0 {
            return None;
        }
        Some(format!("{width}×{height}"))
    }

    /// Stable across PNG encodings of the same pixels (SHA256 of RGBA8 buffer).
    pub fn pixel_fingerprint(data: &[u8]) -> Option<String> {
        let img = image::load_from_memory(data).ok()?.to_rgba8();
        let width = img.width() as usize;
        let height = img.height() as usize;
        if width == 0 || height == 0 || width > 20_000 || height > 20_000 {
            return None;
        }
        let digest = hash_rgba_premultiplied(&img);
        Some(format!("{width}x{height}:{digest}"))
    }

    fn can_decode(data: &[u8]) -> bool {
        image::load_from_memory(data).is_ok()
    }

    fn reencoded_png(data: &[u8]) -> Option<Vec<u8>> {
        let img = image::load_from_memory(data).ok()?;
        let mut out = Vec::new();
        let encoder = image::codecs::png::PngEncoder::new(&mut out);
        img.write_with_encoder(encoder).ok()?;
        if Self::is_png(&out) && Self::can_decode(&out) {
            Some(out)
        } else {
            None
        }
    }
}

fn big_endian_u32(data: &[u8], offset: usize) -> Option<u32> {
    if data.len() < offset + 4 {
        return None;
    }
    Some(u32::from_be_bytes([
        data[offset],
        data[offset + 1],
        data[offset + 2],
        data[offset + 3],
    ]))
}

/// Match CoreGraphics premultiplied-last RGBA layout for fingerprints.
fn hash_rgba_premultiplied(img: &RgbaImage) -> String {
    let width = img.width() as usize;
    let height = img.height() as usize;
    let bytes_per_row = width * 4;
    let mut buffer = vec![0u8; height * bytes_per_row];
    for (x, y, pixel) in img.enumerate_pixels() {
        let r = pixel[0] as u16;
        let g = pixel[1] as u16;
        let b = pixel[2] as u16;
        let a = pixel[3] as u16;
        let i = (y as usize) * bytes_per_row + (x as usize) * 4;
        // Premultiply to mirror CGImageAlphaInfo.premultipliedLast
        buffer[i] = ((r * a) / 255) as u8;
        buffer[i + 1] = ((g * a) / 255) as u8;
        buffer[i + 2] = ((b * a) / 255) as u8;
        buffer[i + 3] = a as u8;
    }
    let digest = Sha256::digest(&buffer);
    hex::encode(digest)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_non_png() {
        assert!(!ImagePNG::is_png(b"not-a-png"));
    }
}
