use crate::clipboard::types::ClipItem;

/// Largest single clip we will record, in bytes of stored content.
///
/// Images are held as base64, and the capture path falls back to
/// `public.tiff` when there is no PNG on the pasteboard — an uncompressed 5K
/// TIFF is ~59 MB raw, ~79 MB base64, from ONE copy. Skipping outright beats
/// truncating: a half-stored clip that pastes as garbage is worse than one
/// that was never offered.
///
/// 10 MB comfortably clears a base64 Retina screenshot while rejecting the
/// pathological cases.
pub const MAX_CLIP_BYTES: usize = 10 * 1024 * 1024;

/// Ceiling on the total stored content.
///
/// Every mutation re-serialises and re-encrypts the WHOLE history (see SC-07),
/// so this number sets the worst-case latency of a delete, a pin, and of the
/// clipboard poll thread. Measured on the release build at ~135 MB/s through
/// serialize+encrypt+write, so 32 MB ≈ 240 ms worst case, against 505 ms for
/// the 107 MB blob that the item-count cap alone permitted.
///
/// The count cap (`enforce_max_history`) bounds how MANY entries; without this
/// one, twenty screenshots could still make every keystroke wait half a second.
pub const MAX_TOTAL_CONTENT_BYTES: usize = 32 * 1024 * 1024;

/// Stored cost of an item. Content dominates by orders of magnitude; the
/// preview is included because it is a copy of the first 200 chars.
pub fn item_bytes(item: &ClipItem) -> usize {
    item.content.len() + item.preview.len()
}

/// Whether a freshly captured clip is too large to be worth recording.
pub fn is_oversized(item: &ClipItem) -> bool {
    item_bytes(item) > MAX_CLIP_BYTES
}

/// Drop the oldest unpinned entries until the total stored content fits in
/// `max_bytes`.
///
/// Pinned entries are never evicted — same rule as the count cap — but their
/// bytes DO count, because the cost they impose on every save is just as real.
/// A history made entirely of pinned screenshots can therefore exceed the
/// budget; that is the user's explicit choice, and the alternative is deleting
/// something they asked us to keep.
pub fn enforce_byte_budget(items: &mut Vec<ClipItem>, max_bytes: usize) {
    let mut used = 0usize;
    items.retain(|item| {
        let cost = item_bytes(item);
        if item.pinned {
            used = used.saturating_add(cost);
            return true;
        }
        if used.saturating_add(cost) > max_bytes {
            return false;
        }
        used += cost;
        true
    });
}

pub fn apply_dedup(items: &mut Vec<ClipItem>, new_item: &ClipItem) {
    items.retain(|existing| {
        !(existing.clip_type == new_item.clip_type && existing.content == new_item.content)
    });
}

/// Trim the history down to `max` UNPINNED entries, keeping the ones nearest
/// the front (callers hand us a newest-first list) and preserving order.
///
/// Pinned entries are exempt and never counted. That is what the Settings copy
/// promises — "pinned items are always preserved" — and what a blind
/// `truncate(max)` quietly broke: over a pinned-first list, once the pin count
/// passed the cap the overflow pins were the ones deleted, which is the exact
/// opposite of what pinning is for.
pub fn enforce_max_history(items: &mut Vec<ClipItem>, max: usize) {
    let mut unpinned_kept = 0usize;
    items.retain(|item| {
        if item.pinned {
            return true;
        }
        unpinned_kept += 1;
        unpinned_kept <= max
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::clipboard::types::{ClipItem, ClipType};

    fn make_item(id: &str, content: &str) -> ClipItem {
        ClipItem {
            id: id.to_string(),
            clip_type: ClipType::Text,
            content: content.to_string(),
            preview: content.to_string(),
            timestamp: 0,
            pinned: false,
            app_name: None,
            image_width: None,
            image_height: None,
            image_format: None,
        }
    }

    #[test]
    fn test_dedup_removes_existing_same_content_and_type() {
        let mut items = vec![make_item("old-id", "hello"), make_item("other-id", "world")];
        let new_item = make_item("new-id", "hello");
        apply_dedup(&mut items, &new_item);

        assert_eq!(items.len(), 1);
        assert_eq!(items[0].id, "other-id");
    }

    #[test]
    fn test_dedup_keeps_items_with_different_content() {
        let mut items = vec![make_item("id1", "foo"), make_item("id2", "bar")];
        let new_item = make_item("id3", "baz");
        apply_dedup(&mut items, &new_item);

        assert_eq!(items.len(), 2);
    }

    #[test]
    fn test_dedup_empty_list() {
        let mut items: Vec<ClipItem> = vec![];
        let new_item = make_item("id1", "content");
        apply_dedup(&mut items, &new_item);

        assert!(items.is_empty());
    }

    #[test]
    fn test_enforce_max_truncates_at_limit() {
        let mut items: Vec<ClipItem> = (0..55).map(|i| make_item(&i.to_string(), &i.to_string())).collect();
        enforce_max_history(&mut items, 50);
        assert_eq!(items.len(), 50);
    }

    #[test]
    fn test_enforce_max_noop_below_limit() {
        let mut items = vec![make_item("a", "a"), make_item("b", "b")];
        enforce_max_history(&mut items, 50);
        assert_eq!(items.len(), 2);
    }

    fn sized_item(id: &str, bytes: usize) -> ClipItem {
        let mut item = make_item(id, "");
        item.content = "x".repeat(bytes);
        item.preview = String::new();
        item
    }

    #[test]
    fn test_byte_budget_drops_the_oldest_until_it_fits() {
        // Newest-first, as every caller hands us.
        let mut items = vec![
            sized_item("newest", 400),
            sized_item("middle", 400),
            sized_item("oldest", 400),
        ];

        enforce_byte_budget(&mut items, 1000);

        let ids: Vec<&str> = items.iter().map(|i| i.id.as_str()).collect();
        assert_eq!(ids, vec!["newest", "middle"], "the oldest entry pays first");
    }

    #[test]
    fn test_byte_budget_is_a_noop_when_it_already_fits() {
        let mut items = vec![sized_item("a", 10), sized_item("b", 10)];
        enforce_byte_budget(&mut items, 1000);
        assert_eq!(items.len(), 2);
    }

    #[test]
    fn test_byte_budget_never_evicts_pinned() {
        let mut pinned = sized_item("pinned-huge", 5000);
        pinned.pinned = true;
        let mut items = vec![sized_item("newest", 100), pinned, sized_item("oldest", 100)];

        enforce_byte_budget(&mut items, 1000);

        assert!(
            items.iter().any(|i| i.id == "pinned-huge"),
            "a pinned entry must survive even when it alone blows the budget"
        );
        // Its bytes still count, so everything unpinned behind it is evicted.
        let ids: Vec<&str> = items.iter().map(|i| i.id.as_str()).collect();
        assert_eq!(ids, vec!["newest", "pinned-huge"]);
    }

    #[test]
    fn test_oversized_single_clip_is_rejected() {
        assert!(!is_oversized(&sized_item("normal", 1024)));
        assert!(is_oversized(&sized_item("huge", MAX_CLIP_BYTES + 1)));
        // A base64 Retina screenshot must still be accepted.
        assert!(!is_oversized(&sized_item("screenshot", 6 * 1024 * 1024)));
    }

    #[test]
    fn test_byte_budget_bounds_the_worst_case_save() {
        // The point of the budget: every mutation re-encrypts the whole blob,
        // so the total content size IS the worst-case latency.
        let mut items: Vec<ClipItem> = (0..40)
            .map(|i| sized_item(&format!("img-{i}"), 4 * 1024 * 1024))
            .collect();

        enforce_byte_budget(&mut items, MAX_TOTAL_CONTENT_BYTES);

        let total: usize = items.iter().map(item_bytes).sum();
        assert!(
            total <= MAX_TOTAL_CONTENT_BYTES,
            "160 MB of screenshots must be trimmed to the budget, got {total}"
        );
    }

    #[test]
    fn test_enforce_max_never_evicts_pinned() {
        // 60 pinned items against a cap of 50: the old blind truncate deleted
        // ten of them.
        let mut items: Vec<ClipItem> = (0..60)
            .map(|i| {
                let mut item = make_item(&i.to_string(), &i.to_string());
                item.pinned = true;
                item
            })
            .collect();

        enforce_max_history(&mut items, 50);

        assert_eq!(items.len(), 60, "pinned items must all survive the cap");
        assert!(items.iter().all(|i| i.pinned));
    }

    #[test]
    fn test_enforce_max_counts_unpinned_only() {
        // Pinned-first, the shape get_history hands us.
        let mut items: Vec<ClipItem> = (0..3)
            .map(|i| {
                let mut item = make_item(&format!("pin-{i}"), &format!("pin-{i}"));
                item.pinned = true;
                item
            })
            .chain((0..10).map(|i| make_item(&format!("recent-{i}"), &format!("recent-{i}"))))
            .collect();

        enforce_max_history(&mut items, 4);

        let ids: Vec<&str> = items.iter().map(|i| i.id.as_str()).collect();
        assert_eq!(
            ids,
            vec![
                "pin-0", "pin-1", "pin-2", "recent-0", "recent-1", "recent-2", "recent-3",
            ],
            "all 3 pins plus the 4 newest unpinned, in order"
        );
    }

    #[test]
    fn test_enforce_max_keeps_a_new_clip_even_when_pins_exceed_the_cap() {
        // add_item's shape: the fresh clip is at index 0, ahead of the pins.
        let mut items = vec![make_item("fresh", "fresh")];
        items.extend((0..15).map(|i| {
            let mut item = make_item(&format!("pin-{i}"), &format!("pin-{i}"));
            item.pinned = true;
            item
        }));

        enforce_max_history(&mut items, 10);

        assert_eq!(items[0].id, "fresh", "the just-copied item must survive");
        assert_eq!(items.len(), 16);
    }

    #[test]
    fn test_clip_item_serde_roundtrip_camelcase() {
        let item = ClipItem {
            id: "uuid-1".to_string(),
            clip_type: ClipType::Text,
            content: "test".to_string(),
            preview: "test".to_string(),
            timestamp: 1700000000000,
            pinned: false,
            app_name: Some("Chrome".to_string()),
            image_width: None,
            image_height: None,
            image_format: None,
        };

        let json = serde_json::to_string(&item).expect("serialize failed");

        // Must use camelCase keys in JSON output
        assert!(json.contains("\"clipType\""), "expected camelCase 'clipType', got: {}", json);
        assert!(json.contains("\"appName\""), "expected camelCase 'appName', got: {}", json);
        assert!(!json.contains("\"clip_type\""), "must NOT contain snake_case 'clip_type'");

        let deserialized: ClipItem = serde_json::from_str(&json).expect("deserialize failed");
        assert_eq!(deserialized, item);
    }

    #[test]
    fn test_add_item_logic_newest_first() {
        let mut items = vec![make_item("old", "old content")];
        let new_item = make_item("new", "new content");

        apply_dedup(&mut items, &new_item);
        items.insert(0, new_item.clone());
        enforce_max_history(&mut items, 50);

        assert_eq!(items[0].id, "new");
        assert_eq!(items[1].id, "old");
    }

    #[test]
    fn test_add_item_dedup_moves_to_front() {
        let mut items = vec![
            make_item("id1", "first"),
            make_item("id2", "second"),
            make_item("id3", "third"),
        ];
        let new_item = make_item("id4", "second"); // duplicate content

        apply_dedup(&mut items, &new_item);
        items.insert(0, new_item);

        // "second" removed old entry, new entry inserted at front
        assert_eq!(items.len(), 3);
        assert_eq!(items[0].content, "second");
        assert_eq!(items[0].id, "id4");
    }
}
