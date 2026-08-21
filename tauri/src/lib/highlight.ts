import type { ReactNode } from "react";
import { createElement, Fragment } from "react";

/**
 * Split `text` into runs based on the positions of characters that contribute
 * to a fuzzy match against `query`. Matched runs are wrapped in a styled
 * <mark> for highlighting; non-matching runs are returned as plain text.
 *
 * Matching is case-insensitive and order-preserving (the same algorithm cmdk
 * uses for ranking). Whitespace in the query is ignored, mirroring cmdk's
 * behavior so the highlight tracks what the user actually sees ranked.
 *
 * Falls back to returning `text` unchanged when `query` is empty, no chars
 * matched, or every char matched (avoiding pointless splits).
 */
/**
 * Case-insensitive, order-preserving fuzzy match — the exact matcher behind
 * `renderHighlightedText`, so what the search filter keeps and what the
 * highlight marks can never disagree. Empty/whitespace queries match all.
 */
export function fuzzyMatches(text: string, query: string): boolean {
  const normalizedQuery = query.replace(/\s+/g, "").toLowerCase();
  if (normalizedQuery.length === 0) return true;

  const lowerText = text.toLowerCase();
  let qi = 0;
  for (let ti = 0; ti < lowerText.length && qi < normalizedQuery.length; ti++) {
    if (lowerText[ti] === normalizedQuery[qi]) {
      qi++;
    }
  }
  return qi === normalizedQuery.length;
}

export function renderHighlightedText(text: string, query: string | undefined): ReactNode {
  if (!query) return text;

  const normalizedQuery = query.replace(/\s+/g, "").toLowerCase();
  if (normalizedQuery.length === 0) return text;

  const lowerText = text.toLowerCase();
  const matched: boolean[] = new Array(text.length).fill(false);

  // Greedy forward scan — same shape as cmdk's command.score positions, but
  // we don't need their exact ranking, just the participating indices.
  let qi = 0;
  for (let ti = 0; ti < lowerText.length && qi < normalizedQuery.length; ti++) {
    if (lowerText[ti] === normalizedQuery[qi]) {
      matched[ti] = true;
      qi++;
    }
  }

  // If nothing matched, return raw text — nothing to highlight.
  if (qi === 0) return text;

  // If literally every char matched (e.g. query equals text lowercased), one
  // <mark> wraps the whole string — keep semantic but skip splitting work.
  const runs: ReactNode[] = [];
  let i = 0;
  while (i < text.length) {
    const isMatch = matched[i];
    let j = i + 1;
    while (j < text.length && matched[j] === isMatch) {
      j++;
    }
    const chunk = text.slice(i, j);
    if (isMatch) {
      runs.push(
        createElement(
          "mark",
          {
            key: i,
            className:
              "rounded-sm bg-accent/30 text-foreground px-px",
          },
          chunk,
        ),
      );
    } else {
      runs.push(chunk);
    }
    i = j;
  }

  return createElement(Fragment, null, ...runs);
}
