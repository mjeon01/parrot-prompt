import AppKit
import SwiftUI

/// A native, read-only text view that is kept for the whole session. Updating
/// its string in place avoids SwiftUI relayout flicker while text streams in.
/// It follows new lines only while the reader is already at the bottom.
struct TranscriptTextView: NSViewRepresentable {
    let text: String
    let placeholder: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.textContainerInset = .zero
            view.textContainer?.lineFragmentPadding = 0
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, let storage = view.textStorage else { return }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: placeholder ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: style
        ]
        guard storage.string != text || context.coordinator.placeholder != placeholder else { return }
        context.coordinator.placeholder = placeholder
        let clip = scroll.contentView
        let atBottom = clip.bounds.maxY >= view.frame.height - 4
        storage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        if atBottom { view.scrollToEndOfDocument(nil) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var placeholder = false
    }
}
