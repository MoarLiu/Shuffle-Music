import AppKit

final class StatusBarController {
    private static let itemWidth: CGFloat = 126

    private let statusItem = NSStatusBar.system.statusItem(withLength: itemWidth)
    private let musicFeature: ShuffleMusicFeature
    private let showPlayer: (NSWindow?) -> Void
    private let menu = NSMenu()
    private var snapshot = ShuffleMusicPlayerSnapshot()

    init(
        musicFeature: ShuffleMusicFeature,
        showPlayer: @escaping (NSWindow?) -> Void,
        quit: @escaping () -> Void
    ) {
        self.musicFeature = musicFeature
        self.showPlayer = showPlayer

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.toolTip = "Shuffle Music"
            button.target = self
            button.action = #selector(handleStatusButtonAction)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.image = statusImage(for: snapshot)
        }

        let openItem = NSMenuItem(title: "Open Player", action: #selector(openPlayer), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = CallbackMenuItem(title: "Quit Shuffle Music", keyEquivalent: "q", callback: quit)
        menu.addItem(quitItem)

        statusItem.length = Self.itemWidth
    }

    func update(snapshot: ShuffleMusicPlayerSnapshot) {
        self.snapshot = snapshot
        statusItem.button?.image = statusImage(for: snapshot)
    }

    @objc private func openPlayer() {
        showPlayer(statusItem.button?.window)
    }

    @objc private func handleStatusButtonAction() {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
            return
        }

        let x = event.map { button.convert($0.locationInWindow, from: nil).x } ?? 0
        switch segment(at: x) {
        case .open:
            showPlayer(button.window)
        case .previous:
            guard snapshot.canPlayPrevious, !snapshot.status.isBusy else { return }
            musicFeature.playPreviousTrack()
        case .playPause:
            musicFeature.togglePlayPause()
        case .next:
            guard !snapshot.status.isBusy else { return }
            musicFeature.playNextTrack()
        }
    }

    private enum Segment {
        case open
        case previous
        case playPause
        case next
    }

    private func segment(at x: CGFloat) -> Segment {
        switch x {
        case ..<34:
            return .open
        case ..<62:
            return .previous
        case ..<90:
            return .playPause
        default:
            return .next
        }
    }

    private func statusImage(for snapshot: ShuffleMusicPlayerSnapshot) -> NSImage {
        let height = max(NSStatusBar.system.thickness, 22)
        let image = NSImage(size: NSSize(width: Self.itemWidth, height: height))
        image.lockFocus()
        NSColor.black.setFill()

        drawSymbol("music.note", centerX: 17.5, height: height, alpha: 1)
        drawSymbol("backward.fill", centerX: 48.5, height: height, alpha: snapshot.canPlayPrevious && !snapshot.status.isBusy ? 1 : 0.35)

        let playPauseSymbol: String
        if snapshot.status.isBusy {
            playPauseSymbol = "stop.fill"
        } else if snapshot.status.isPlaying {
            playPauseSymbol = "pause.fill"
        } else {
            playPauseSymbol = "play.fill"
        }
        drawSymbol(playPauseSymbol, centerX: 76.5, height: height, alpha: 1)
        drawSymbol("forward.fill", centerX: 104.5, height: height, alpha: snapshot.status.isBusy ? 0.35 : 1)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func drawSymbol(_ name: String, centerX: CGFloat, height: CGFloat, alpha: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else {
            return
        }

        let symbolSize = NSSize(width: 18, height: 18)
        let rect = NSRect(
            x: centerX - symbolSize.width / 2,
            y: (height - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
    }
}

private final class CallbackMenuItem: NSMenuItem {
    private let callback: () -> Void

    init(title: String, keyEquivalent: String, callback: @escaping () -> Void) {
        self.callback = callback
        super.init(title: title, action: #selector(runCallback), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runCallback() {
        callback()
    }
}
