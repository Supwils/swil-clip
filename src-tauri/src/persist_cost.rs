//! Persistence cost harness — opt-in, never part of the default gate.
//!
//! Both tests are #[ignore]d — they allocate hundreds of MB and take ~2min in
//! a debug build, which has no place in `pnpm prepush`. Run them deliberately,
//! and ALWAYS with --release: an unoptimized AES build is ~30x slower and will
//! send you chasing a bottleneck that does not exist in the shipped app.
//!
//! ```text
//! cargo test --release --manifest-path src-tauri/Cargo.toml \
//!   persist_cost -- --ignored --nocapture
//! ```
//!
//! Answers one question: how long does one history save actually take?
//! `save_history` = serde_json::to_vec + AES-256-GCM encrypt + disk write, and
//! it runs inside the IPC handler, so this number is the latency every delete,
//! pin and clipboard capture pays.

#[cfg(test)]
mod tests {
    use crate::clipboard::types::{ClipItem, ClipType};
    use crate::crypto;
    use std::time::Instant;

    fn text_item(i: usize) -> ClipItem {
        ClipItem {
            id: format!("id-{i}"),
            clip_type: ClipType::Text,
            content: "lorem ipsum dolor sit amet ".repeat(20),
            preview: "lorem ipsum".to_string(),
            timestamp: 1700000000000,
            pinned: false,
            app_name: None,
            image_width: None,
            image_height: None,
            image_format: None,
        }
    }

    /// `bytes` of base64 payload — a retina screenshot lands around 2-8 MB.
    fn image_item(i: usize, bytes: usize) -> ClipItem {
        ClipItem {
            id: format!("img-{i}"),
            clip_type: ClipType::Image,
            content: "A".repeat(bytes),
            preview: "Image (png)".to_string(),
            timestamp: 1700000000000,
            pinned: false,
            app_name: None,
            image_width: None,
            image_height: None,
            image_format: Some("png".to_string()),
        }
    }

    /// Where does the time actually go? serialize, encrypt, or write?
    fn breakdown(label: &str, items: &[ClipItem]) {
        let key = [7u8; 32];
        let dir = std::env::temp_dir().join("swilclip-bench");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("blob.json");

        let t0 = Instant::now();
        let json = serde_json::to_vec(items).unwrap();
        let serialize_ms = t0.elapsed().as_secs_f64() * 1000.0;
        let raw_mb = json.len() as f64 / 1_048_576.0;

        let t1 = Instant::now();
        let blob = crypto::encrypt(&json, &key).unwrap();
        let encrypt_ms = t1.elapsed().as_secs_f64() * 1000.0;

        let t2 = Instant::now();
        std::fs::write(&path, &blob).unwrap();
        let write_ms = t2.elapsed().as_secs_f64() * 1000.0;

        println!(
            "{label:<32} serialize {serialize_ms:>8.1} ms | encrypt {encrypt_ms:>8.1} ms \
             ({:>6.1} MB/s) | write {write_ms:>7.1} ms",
            raw_mb / (encrypt_ms / 1000.0),
        );
        let _ = std::fs::remove_file(&path);
    }

    fn measure(label: &str, items: &[ClipItem]) {
        let key = [7u8; 32];
        let dir = std::env::temp_dir().join("swilclip-bench");
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("blob.json");

        // Warm up so we measure steady state, not first-touch allocation.
        for _ in 0..2 {
            let json = serde_json::to_vec(items).unwrap();
            let _ = crypto::encrypt(&json, &key).unwrap();
        }

        let mut total_ms = 0.0;
        let runs = 5;
        let mut blob_len = 0;
        for _ in 0..runs {
            let start = Instant::now();
            let json = serde_json::to_vec(items).unwrap();
            let blob = crypto::encrypt(&json, &key).unwrap();
            blob_len = blob.len();
            std::fs::write(&path, &blob).unwrap();
            total_ms += start.elapsed().as_secs_f64() * 1000.0;
        }

        println!(
            "{label:<34} {:>8.1} ms/save   blob {:>7.2} MB",
            total_ms / runs as f64,
            blob_len as f64 / 1_048_576.0,
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    #[ignore = "perf harness; run with --release --ignored"]
    fn persist_cost_of_one_save() {
        println!("\n--- cost of a single save_history (serialize + encrypt + write) ---");

        measure("50 text only (default cap)", &(0..50).map(text_item).collect::<Vec<_>>());

        let mut with_images: Vec<ClipItem> = (0..45).map(text_item).collect();
        with_images.extend((0..5).map(|i| image_item(i, 2 * 1024 * 1024)));
        measure("50 items, 5x 2MB screenshots", &with_images);

        let mut heavy: Vec<ClipItem> = (0..480).map(text_item).collect();
        heavy.extend((0..20).map(|i| image_item(i, 4 * 1024 * 1024)));
        measure("500 cap, 20x 4MB (uncapped)", &heavy);

        // Same history, after the byte budget — this is what ships.
        let mut capped = heavy.clone();
        crate::store_logic::enforce_byte_budget(
            &mut capped,
            crate::store_logic::MAX_TOTAL_CONTENT_BYTES,
        );
        measure("same, after the byte budget", &capped);

        println!("--- every delete / pin / clipboard capture pays this ---\n");
    }

    #[test]
    #[ignore = "perf harness; run with --release --ignored"]
    fn persist_cost_breakdown() {
        println!("\n--- breakdown ---");
        let mut with_images: Vec<ClipItem> = (0..45).map(text_item).collect();
        with_images.extend((0..5).map(|i| image_item(i, 2 * 1024 * 1024)));
        breakdown("50 items, 5x 2MB images", &with_images);

        let big = vec![image_item(0, 16 * 1024 * 1024)];
        breakdown("one 16MB image", &big);
        println!();
    }
}
