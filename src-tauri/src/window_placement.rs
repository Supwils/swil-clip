//! Pure geometry for deciding where the panel opens.
//!
//! Split out from `lib.rs` for the same reason as `store_logic`: the Tauri
//! types are untestable in a unit test, the arithmetic is exactly where the
//! bugs live. Everything here works in **logical points** — the coordinate
//! space macOS reports the cursor in — so a Retina display cannot silently
//! double the offsets.

/// A rectangle in logical points, top-left origin. Coordinates may be negative
/// (a display to the left of, or above, the primary one).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl Rect {
    pub fn new(x: f64, y: f64, width: f64, height: f64) -> Self {
        Rect {
            x,
            y,
            width,
            height,
        }
    }

    fn right(&self) -> f64 {
        self.x + self.width
    }

    fn bottom(&self) -> f64 {
        self.y + self.height
    }

    fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.x && x < self.right() && y >= self.y && y < self.bottom()
    }

    fn overlaps(&self, other: &Rect) -> bool {
        self.x < other.right()
            && other.x < self.right()
            && self.y < other.bottom()
            && other.y < self.bottom()
    }
}

/// Index of the work area containing `(x, y)`, if any.
pub fn area_containing(areas: &[Rect], x: f64, y: f64) -> Option<usize> {
    areas.iter().position(|area| area.contains(x, y))
}

/// Index of the first work area the window rect overlaps at all.
///
/// Used to decide whether a *saved* position is still usable: a window dragged
/// slightly past an edge has a top-left corner that is on no display, yet is
/// perfectly reachable. Only a window overlapping nothing is stranded.
pub fn area_overlapping(areas: &[Rect], window: Rect) -> Option<usize> {
    areas.iter().position(|area| area.overlaps(&window))
}

/// Move `window` the shortest distance needed to sit fully inside `area`.
///
/// A window larger than the area pins to the area's origin rather than being
/// pushed off the opposite edge — losing the bottom of an over-tall panel is
/// recoverable, losing its title strip is not.
pub fn clamp_into(area: Rect, window: Rect) -> (f64, f64) {
    let max_x = (area.right() - window.width).max(area.x);
    let max_y = (area.bottom() - window.height).max(area.y);
    (
        window.x.clamp(area.x, max_x),
        window.y.clamp(area.y, max_y),
    )
}

/// Where the panel should open for a summon at `(cursor_x, cursor_y)`.
///
/// Horizontally centred on the cursor and hanging below it, then clamped into
/// whichever display the cursor is on (falling back to `fallback_area` when the
/// cursor is on none — it can sit in the dead space between mismatched
/// displays). Returns `None` only when there are no displays to place it on.
pub fn placement_for_cursor(
    areas: &[Rect],
    cursor_x: f64,
    cursor_y: f64,
    window_width: f64,
    window_height: f64,
) -> Option<(f64, f64)> {
    let index = area_containing(areas, cursor_x, cursor_y).or(if areas.is_empty() {
        None
    } else {
        Some(0)
    })?;
    let area = areas[index];
    let window = Rect::new(
        cursor_x - window_width / 2.0,
        cursor_y,
        window_width,
        window_height,
    );
    Some(clamp_into(area, window))
}

/// Where the panel should re-open given a remembered position.
///
/// `None` means the remembered point no longer lands on any connected display
/// — an external monitor was unplugged or the layout changed — and the caller
/// must fall back to the cursor instead of opening the panel out of reach.
pub fn placement_for_saved(
    areas: &[Rect],
    saved_x: f64,
    saved_y: f64,
    window_width: f64,
    window_height: f64,
) -> Option<(f64, f64)> {
    let window = Rect::new(saved_x, saved_y, window_width, window_height);
    let index = area_overlapping(areas, window)?;
    Some(clamp_into(areas[index], window))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 1440×900 primary, plus a 1920×1080 display to its LEFT (negative x) —
    /// the layout that the old `.max(0.0)` guard collapsed onto the origin.
    fn two_displays() -> Vec<Rect> {
        vec![
            Rect::new(0.0, 25.0, 1440.0, 875.0),
            Rect::new(-1920.0, 25.0, 1920.0, 1055.0),
        ]
    }

    const W: f64 = 340.0;
    const H: f64 = 480.0;

    #[test]
    fn cursor_placement_centres_horizontally_and_hangs_below() {
        let areas = two_displays();
        let (x, y) = placement_for_cursor(&areas, 700.0, 300.0, W, H).unwrap();
        assert_eq!(x, 700.0 - W / 2.0);
        assert_eq!(y, 300.0);
    }

    #[test]
    fn cursor_near_right_edge_pulls_the_panel_fully_on_screen() {
        let areas = two_displays();
        let (x, _) = placement_for_cursor(&areas, 1435.0, 100.0, W, H).unwrap();
        assert_eq!(x, 1440.0 - W, "right edge must be flush, not overhanging");
    }

    #[test]
    fn cursor_near_bottom_edge_lifts_the_panel_fully_on_screen() {
        let areas = two_displays();
        let (_, y) = placement_for_cursor(&areas, 700.0, 880.0, W, H).unwrap();
        assert_eq!(y, 900.0 - H);
    }

    #[test]
    fn cursor_on_a_display_left_of_primary_stays_there() {
        let areas = two_displays();
        let (x, y) = placement_for_cursor(&areas, -1000.0, 400.0, W, H).unwrap();
        assert_eq!(x, -1000.0 - W / 2.0);
        assert_eq!(y, 400.0);
        assert!(x < 0.0, "must not be clamped onto the primary display");
    }

    #[test]
    fn menu_bar_is_never_covered() {
        let areas = two_displays();
        let (_, y) = placement_for_cursor(&areas, 700.0, 0.0, W, H).unwrap();
        assert_eq!(y, 25.0, "work area starts below the menu bar");
    }

    #[test]
    fn a_window_taller_than_the_display_pins_to_the_top() {
        let areas = vec![Rect::new(0.0, 25.0, 800.0, 300.0)];
        let (x, y) = placement_for_cursor(&areas, 400.0, 200.0, W, H).unwrap();
        assert_eq!((x, y), (400.0 - W / 2.0, 25.0));
    }

    #[test]
    fn no_displays_means_no_placement() {
        assert!(placement_for_cursor(&[], 10.0, 10.0, W, H).is_none());
    }

    #[test]
    fn saved_position_on_a_live_display_is_kept_verbatim() {
        let areas = two_displays();
        assert_eq!(
            placement_for_saved(&areas, 300.0, 200.0, W, H),
            Some((300.0, 200.0)),
        );
    }

    #[test]
    fn saved_position_hanging_off_an_edge_is_pulled_back_not_discarded() {
        let areas = two_displays();
        let (x, y) = placement_for_saved(&areas, 1300.0, 200.0, W, H).unwrap();
        assert_eq!((x, y), (1440.0 - W, 200.0));
    }

    #[test]
    fn saved_position_on_an_unplugged_display_is_rejected() {
        // Remembered on the secondary display, which is now gone.
        let only_primary = vec![two_displays()[0]];
        assert!(placement_for_saved(&only_primary, -900.0, 300.0, W, H).is_none());
    }
}
