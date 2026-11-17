import AppKit
import SwiftUI

/// ③ 的多行输入框：无边框、17px、行高 1.55。
/// 用 NSTextView 而不是 TextEditor，以便精确控制排版和焦点（⌘↩ 由面板统一拦截）。
struct InputTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusToken: Int
    var blurToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlaceholderTextView()
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = Self.font
        textView.textColor = NSColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
        textView.insertionPointColor = textView.textColor ?? .black
        textView.defaultParagraphStyle = Self.paragraphStyle
        textView.typingAttributes = Self.attributes
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            textView.typingAttributes = Self.attributes
            if let storage = textView.textStorage {
                storage.setAttributes(Self.attributes, range: NSRange(location: 0, length: storage.length))
            }
            textView.needsDisplay = true
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
            }
        }
        if context.coordinator.blurToken != blurToken {
            context.coordinator.blurToken = blurToken
            DispatchQueue.main.async {
                if textView.window?.firstResponder === textView { textView.window?.makeFirstResponder(nil) }
            }
        }
    }

    static let font = NSFont.systemFont(ofSize: 17)

    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        // CSS line-height 1.55 → 26.35pt 行高
        style.minimumLineHeight = 26.35
        style.maximumLineHeight = 26.35
        return style
    }()

    static var attributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1),
            .paragraphStyle: paragraphStyle,
            .kern: -0.17,
            .baselineOffset: (26.35 - font.ascender + font.descender) / 2 - 1,
        ]
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?
        var focusToken = 0
        var blurToken = 0

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

final class PlaceholderTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }

    override var string: String { didSet { needsDisplay = true } }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        var attributes = InputTextView.attributes
        attributes[.foregroundColor] = NSColor(srgbRed: 0x8A / 255, green: 0x8A / 255, blue: 0x8A / 255, alpha: 1)
        NSAttributedString(string: placeholder, attributes: attributes)
            .draw(in: bounds.insetBy(dx: textContainerInset.width, dy: textContainerInset.height))
    }
}
