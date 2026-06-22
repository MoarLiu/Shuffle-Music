import AppKit

final class StatusBarController {
    private static let itemWidth: CGFloat = 126

    private let statusItem = NSStatusBar.system.statusItem(withLength: itemWidth)
    private let controlView: StatusBarControlView
    private let menu = NSMenu()

    init(
        musicFeature: ShuffleMusicFeature,
        showPlayer: @escaping (NSWindow?) -> Void,
        quit: @escaping () -> Void
    ) {
        controlView = StatusBarControlView(
            musicFeature: musicFeature,
            showPlayer: showPlayer
        )
        controlView.frame = NSRect(x: 0, y: 0, width: Self.itemWidth, height: NSStatusBar.system.thickness)
        statusItem.view = controlView

        let openItem = NSMenuItem(title: "Open Player", action: #selector(openPlayer), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = CallbackMenuItem(title: "Quit Shuffle Music", keyEquivalent: "q", callback: quit)
        menu.addItem(quitItem)

        controlView.onContextMenuRequested = { [weak self] in
            guard let self else { return }
            self.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: self.controlView.bounds.minY), in: self.controlView)
        }
    }

    func update(snapshot: ShuffleMusicPlayerSnapshot) {
        controlView.update(snapshot: snapshot)
    }

    @objc private func openPlayer() {
        controlView.showPlayerFromIcon()
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
