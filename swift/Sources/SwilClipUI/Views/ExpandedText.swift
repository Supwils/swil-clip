import AppKit
import SwiftUI

/// A request to scroll one expanded row by some lines.
///
/// `serial` is what makes it an *event* rather than a value: pressing `⇧↓`
/// twice produces two requests with identical `id` and `lines`, and the view
/// must act on both.
struct ExpansionScroll: Equatable {
    let id: String
    let lines: Int
    let serial: Int
}

/// The read-only body of an expanded row.
///
/// An `NSTextView` rather than SwiftUI `Text` in a `ScrollView`, for one
/// reason: `⇧↑` / `⇧↓` scroll it by *lines*. SwiftUI on macOS 14 can only
/// scroll to an identified child, so line scrolling would mean splitting the
/// text into one `Text` per line — which breaks selection across lines, the
/// one thing a read-only text view is still for.
///
/// It sizes itself to its content up to `maxHeight`, so a one-line clip does
/// not open into a tall empty box.
struct ExpandedText: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor
    let maxHeight: CGFloat
    /// The latest scroll request for *this* row, or `nil`.
    let scroll: ExpansionScroll?

    final class Coordinator {
        var lastSerial: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        // A request that arrived before the view existed is already stale.
        context.coordinator.lastSerial = scroll?.serial
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        if textView.font != font { textView.font = font }
        if textView.textColor != color { textView.textColor = color }

        guard let scroll, scroll.serial != context.coordinator.lastSerial else { return }
        context.coordinator.lastSerial = scroll.serial
        let lineHeight = textView.layoutManager?.defaultLineHeight(for: font) ?? font.pointSize
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        let target = min(max(0, clip.bounds.origin.y + CGFloat(scroll.lines) * lineHeight), maxY)
        // No animation: keyboard scrolling never animates here (CLAUDE.md §6),
        // because held keys stack animations into a smear.
        clip.scroll(to: NSPoint(x: 0, y: target))
        scrollView.reflectScrolledClipView(clip)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView scrollView: NSScrollView, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let textView = scrollView.documentView as? NSTextView,
              let container = textView.textContainer,
              let layout = textView.layoutManager
        else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = ceil(layout.usedRect(for: container).height)
        return CGSize(width: width, height: min(max(used, font.pointSize), maxHeight))
    }
}
