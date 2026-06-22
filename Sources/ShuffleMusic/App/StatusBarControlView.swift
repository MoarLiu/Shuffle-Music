import AppKit

final class StatusBarControlView: NSView {
    var onContextMenuRequested: (() -> Void)?

    private let musicFeature: ShuffleMusicFeature
    private let showPlayer: (NSWindow?) -> Void
    private let iconButton = StatusBarIconButton(symbolName: "music.note")
    private let previousButton = StatusBarIconButton(symbolName: "backward.fill")
    private let playPauseButton = StatusBarIconButton(symbolName: "play.fill")
    private let nextButton = StatusBarIconButton(symbolName: "forward.fill")
    private var trackingArea: NSTrackingArea?

    init(musicFeature: ShuffleMusicFeature, showPlayer: @escaping (NSWindow?) -> Void) {
        self.musicFeature = musicFeature
        self.showPlayer = showPlayer
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.clear.cgColor

        iconButton.toolTip = "Shuffle Music"
        previousButton.toolTip = "上一首"
        playPauseButton.toolTip = "播放"
        nextButton.toolTip = "下一首"

        iconButton.target = self
        iconButton.action = #selector(showPlayerFromIcon)
        previousButton.target = self
        previousButton.action = #selector(playPrevious)
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayPause)
        nextButton.target = self
        nextButton.action = #selector(playNext)

        [iconButton, previousButton, playPauseButton, nextButton].forEach { button in
            button.onContextMenuRequested = { [weak self] in
                self?.onContextMenuRequested?()
            }
        }
        [iconButton, previousButton, playPauseButton, nextButton].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let buttonSize = min(bounds.height, 24)
        let y = (bounds.height - buttonSize) / 2
        var x: CGFloat = 4

        iconButton.frame = NSRect(x: x, y: y, width: 27, height: buttonSize)
        x += 31
        previousButton.frame = NSRect(x: x, y: y, width: 27, height: buttonSize)
        x += 28
        playPauseButton.frame = NSRect(x: x, y: y, width: 27, height: buttonSize)
        x += 28
        nextButton.frame = NSRect(x: x, y: y, width: 27, height: buttonSize)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func rightMouseUp(with event: NSEvent) {
        onContextMenuRequested?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            onContextMenuRequested?()
        }
        return nil
    }

    func update(snapshot: ShuffleMusicPlayerSnapshot) {
        previousButton.isEnabled = snapshot.canPlayPrevious && !snapshot.status.isBusy
        nextButton.isEnabled = !snapshot.status.isBusy

        if snapshot.status.isBusy {
            playPauseButton.setSymbol("stop.fill")
            playPauseButton.toolTip = "停止"
        } else if snapshot.status.isPlaying {
            playPauseButton.setSymbol("pause.fill")
            playPauseButton.toolTip = "暂停"
        } else {
            playPauseButton.setSymbol("play.fill")
            playPauseButton.toolTip = "播放"
        }
    }

    @objc func showPlayerFromIcon() {
        showPlayer(window)
    }

    @objc private func playPrevious() {
        musicFeature.playPreviousTrack()
    }

    @objc private func togglePlayPause() {
        musicFeature.togglePlayPause()
    }

    @objc private func playNext() {
        musicFeature.playNextTrack()
    }
}

private final class StatusBarIconButton: NSButton {
    var onContextMenuRequested: (() -> Void)?

    init(symbolName: String) {
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = true
        setSymbol(symbolName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 27, height: 24)
    }

    func setSymbol(_ symbolName: String) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        contentTintColor = .labelColor
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onContextMenuRequested?()
            return
        }
        super.mouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        onContextMenuRequested?()
    }
}
