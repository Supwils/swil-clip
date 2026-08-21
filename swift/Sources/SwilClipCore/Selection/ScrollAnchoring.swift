import Foundation

/// Decides what a keyboard-driven list should scroll to, and when.
///
/// ## The problem this replaces
///
/// The obvious implementation — `scrollTo(selected, anchor: .center)` on every
/// selection change — re-centres the list on *every* arrow key. The selected row
/// never moves relative to the viewport; the entire list slides underneath it
/// instead. Combined with an animation per keypress, holding `↓` produces a
/// continuous smear, and each individual press produces a visible jolt even when
/// the row was already comfortably on screen.
///
/// ## The rule
///
/// **Do not scroll while the selection is comfortably inside the viewport.**
/// Only when it comes within `lead` rows of an edge does the list move, and then
/// by the minimum needed to keep that margin.
///
/// The implementation is a trick rather than geometry: instead of measuring the
/// viewport, ask the scroll view to reveal the row `lead` positions *beyond* the
/// selection, using a minimal-scroll anchor. If that row is already visible,
/// nothing happens; if it is not, the list scrolls exactly enough to show it —
/// which leaves `lead` rows of runway past the cursor. This works with variable
/// row heights (an expanded row is much taller) where arithmetic on a fixed row
/// height would not.
public enum ScrollAnchoring {
    /// Rows of runway kept between the cursor and the edge it is moving toward.
    ///
    /// Two is the smallest value that still shows you what you are moving into.
    /// One reads as "the list scrolls when I reach the very bottom", which is
    /// exactly the sensation of the cursor being stuck to the edge.
    public static let defaultLead = 2

    /// Index of the row the scroll view should be asked to reveal.
    ///
    /// - Parameters:
    ///   - old: index of the previously selected row, if any.
    ///   - new: index of the newly selected row.
    ///   - count: number of rows currently rendered.
    ///   - lead: rows of runway to keep past the cursor.
    /// - Returns: the index to reveal, clamped into range, or `nil` when there is
    ///   nothing to scroll to.
    public static func revealIndex(
        movingFrom old: Int?,
        to new: Int,
        count: Int,
        lead: Int = ScrollAnchoring.defaultLead
    ) -> Int? {
        guard count > 0, new >= 0, new < count else { return nil }
        guard let old, old != new else {
            // No previous position — a fresh open, a filter change, a click.
            // Reveal the row itself, with no directional runway to guess at.
            return new
        }
        let direction = new > old ? 1 : -1
        let projected = new + direction * lead
        return min(max(projected, 0), count - 1)
    }

    /// Whether a selection change should animate the scroll.
    ///
    /// **It should not.** Keyboard navigation is discrete: the cursor is either
    /// on this row or the next one, and interpolating between them adds latency
    /// to every keypress while producing the smear that holding a key makes
    /// obvious. Spotlight and Raycast both scroll instantly for this reason.
    ///
    /// A pointer-initiated jump — clicking a far-away row, or the list being
    /// re-anchored after a filter — is different: there the movement is large and
    /// unexpected, and a short animation explains where the content went.
    public static func shouldAnimate(_ cause: ScrollCause) -> Bool {
        switch cause {
        case .keyboard: false
        case .reanchor: true
        }
    }

    public enum ScrollCause: Equatable, Sendable {
        /// Arrow keys, Home/End — discrete, frequent, must be instant.
        case keyboard
        /// The list changed underneath the selection: a filter narrowed, a clip
        /// arrived, a tab switched.
        case reanchor
    }
}
