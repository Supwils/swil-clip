export type ContentTag =
  | "url"
  | "email"
  | "color"
  | "json"
  | "code"
  | "multiline"
  | "text";

const URL_RE = /^https?:\/\//i;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const HEX_COLOR_RE = /^#[0-9a-fA-F]{3,8}$/;
const RGB_COLOR_RE = /^rgba?\(\s*\d/i;
const CODE_INDENT_RE = /^[ \t]{2,}/m;
const CODE_PUNCT_RE = /[{};()<>[\]]/g;

function isJson(text: string): boolean {
  if (text.length < 2) return false;
  const trimmed = text.trim();
  if (
    (trimmed[0] !== "{" && trimmed[0] !== "[") ||
    (trimmed[trimmed.length - 1] !== "}" && trimmed[trimmed.length - 1] !== "]")
  ) {
    return false;
  }
  try {
    const parsed: unknown = JSON.parse(trimmed);
    return typeof parsed === "object" && parsed !== null;
  } catch {
    return false;
  }
}

function isCode(text: string): boolean {
  if (!text.includes("\n")) return false;
  if (CODE_INDENT_RE.test(text)) return true;
  const punctMatches = text.match(CODE_PUNCT_RE);
  return punctMatches !== null && punctMatches.length >= 4;
}

export function detectContentTag(content: string): ContentTag {
  const trimmed = content.trim();

  if (URL_RE.test(trimmed)) return "url";
  if (EMAIL_RE.test(trimmed)) return "email";
  if (HEX_COLOR_RE.test(trimmed) || RGB_COLOR_RE.test(trimmed)) return "color";
  if (isJson(trimmed)) return "json";
  if (isCode(trimmed)) return "code";
  if (trimmed.includes("\n")) return "multiline";
  return "text";
}

/** For color tags, returns the raw hex/rgb value to use as backgroundColor. */
export function extractColorValue(content: string): string {
  return content.trim();
}
