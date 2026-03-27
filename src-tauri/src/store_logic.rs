use crate::clipboard::types::ClipItem;

pub fn apply_dedup(items: &mut Vec<ClipItem>, new_item: &ClipItem) {
    items.retain(|existing| {
        !(existing.clip_type == new_item.clip_type && existing.content == new_item.content)
    });
}

pub fn enforce_max_history(items: &mut Vec<ClipItem>, max: usize) {
    if items.len() > max {
        items.truncate(max);
    }
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

    #[test]
    fn test_clip_item_serde_roundtrip_camelcase() {
        let item = ClipItem {
            id: "uuid-1".to_string(),
            clip_type: ClipType::Text,
            content: "test".to_string(),
            preview: "test".to_string(),
            timestamp: 1700000000000,
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
