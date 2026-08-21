import CoreGraphics

/// Where the panel goes when summoned.
///
/// Pure geometry, deliberately: v1 shipped SC-03, where a saved position could
/// put the panel off-screen and out of reach — a bug that only appears when a
/// display is unplugged or resolution changes, which is exactly the situation
/// nobody tests by hand. Keeping the rules as functions over rectangles makes
/// those cases assertions instead.
///
/// All coordinates are AppKit points with a bottom-left origin. v1 also had to
/// juggle physical pixels because Tauri mixed the two; AppKit does not, so that
/// entire class of Retina doubling bugs is absent here rather than defended.
public enum PanelPlacement {
    /// Gap between the cursor and the panel's top-left corner, so the panel does
    /// not open underneath the pointer.
    public static let cursorInset: CGFloat = 8
    /// Minimum distance kept from every screen edge.
    public static let screenMargin: CGFloat = 8

    /// Position the panel near `cursor`, clamped inside `visibleFrame`.
    ///
    /// The panel hangs below-right of the cursor where there is room, and flips
    /// to whichever side has space when there is not — the behaviour of every
    /// macOS context menu, so it needs no explanation.
    public static func origin(
        forCursor cursor: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        // Preferred: top-left corner just below-right of the cursor. In
        // bottom-left coordinates that means subtracting the height.
        var x = cursor.x + cursorInset
        var y = cursor.y - cursorInset - panelSize.height

        // Flip horizontally when the panel would overhang the right edge.
        if x + panelSize.width > visibleFrame.maxX - screenMargin {
            x = cursor.x - cursorInset - panelSize.width
        }
        // Flip vertically when it would fall off the bottom.
        if y < visibleFrame.minY + screenMargin {
            y = cursor.y + cursorInset
        }

        return clamp(
            origin: CGPoint(x: x, y: y), panelSize: panelSize, visibleFrame: visibleFrame
        )
    }

    /// Force a rectangle fully inside `visibleFrame`.
    ///
    /// Clamping runs on every path, including restored positions. A panel that
    /// cannot be reached cannot be moved back, so "mostly on screen" is not an
    /// acceptable outcome.
    public static func clamp(
        origin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        // A panel larger than the screen is pinned to the top-left rather than
        // producing an inverted range.
        let maxX = max(visibleFrame.minX + screenMargin,
                       visibleFrame.maxX - panelSize.width - screenMargin)
        let maxY = max(visibleFrame.minY + screenMargin,
                       visibleFrame.maxY - panelSize.height - screenMargin)
        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX + screenMargin), maxX),
            y: min(max(origin.y, visibleFrame.minY + screenMargin), maxY)
        )
    }

    /// Whether a remembered position is still usable.
    ///
    /// A position saved on a display that is now unplugged must be discarded,
    /// not clamped onto some other screen — the panel would appear somewhere the
    /// user never put it, which is more confusing than reverting to the cursor.
    public static func isRestorable(
        origin: CGPoint,
        panelSize: CGSize,
        screens: [CGRect]
    ) -> Bool {
        let frame = CGRect(origin: origin, size: panelSize)
        // "Substantially visible" rather than "fully": a panel the user nudged
        // a few points past an edge should still come back where they left it.
        let required = frame.width * frame.height * 0.6
        for screen in screens {
            let overlap = screen.intersection(frame)
            guard !overlap.isNull else { continue }
            if overlap.width * overlap.height >= required { return true }
        }
        return false
    }
}
