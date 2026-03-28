use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum ClipType {
    Text,
    Image,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ClipItem {
    pub id: String,
    pub clip_type: ClipType,
    pub content: String,
    pub preview: String,
    pub timestamp: i64,
    #[serde(default)]
    pub pinned: bool,
    pub app_name: Option<String>,
    pub image_width: Option<u32>,
    pub image_height: Option<u32>,
    pub image_format: Option<String>,
}
