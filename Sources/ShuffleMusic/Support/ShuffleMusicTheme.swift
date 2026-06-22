import AppKit
import SwiftUI

enum ShuffleMusicTheme {
    static let radius: CGFloat = 8
    static let smallRadius: CGFloat = 6

    static let tint = adaptiveColor(
        light: NSColor(calibratedRed: 0.28, green: 0.36, blue: 0.82, alpha: 1),
        dark: NSColor(calibratedRed: 0.62, green: 0.70, blue: 1.00, alpha: 1)
    )
    static let onTint = adaptiveColor(
        light: NSColor.white,
        dark: NSColor(calibratedWhite: 0.08, alpha: 1)
    )
    static let softShadow = adaptiveColor(
        light: NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.34, alpha: 0.16),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.45)
    )
    static let glassHairline = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.86),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.12)
    )
    static let glassWhitewash = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.82),
        dark: NSColor(calibratedWhite: 0.16, alpha: 0.72)
    )

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum GlassButtonTone: Equatable {
    case neutral
    case primary

    var fill: Color {
        switch self {
        case .neutral:
            return ShuffleMusicTheme.glassWhitewash
        case .primary:
            return ShuffleMusicTheme.tint.opacity(0.92)
        }
    }

    var foreground: Color {
        switch self {
        case .neutral:
            return .primary
        case .primary:
            return ShuffleMusicTheme.onTint
        }
    }
}

enum ModalPanelStyle {
    static func applyPopupWindowChrome(to window: NSWindow) {
        window.backgroundColor = .clear
        window.isOpaque = false
    }
}

class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}
