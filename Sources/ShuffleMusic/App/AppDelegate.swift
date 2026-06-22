import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let musicFeature = ShuffleMusicFeature()
    private let miniPlayerController = ShuffleMusicMiniPlayerController()
    private var statusBarController: StatusBarController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureApplicationMenu()

        let statusBarController = StatusBarController(
            musicFeature: musicFeature,
            showPlayer: { [weak self] anchorWindow in
                guard let self else { return }
                self.miniPlayerController.show(anchorWindow: anchorWindow, musicFeature: self.musicFeature)
            },
            quit: {
                NSApplication.shared.terminate(nil)
            }
        )
        self.statusBarController = statusBarController

        musicFeature.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak statusBarController] snapshot in
                statusBarController?.update(snapshot: snapshot)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        musicFeature.stop()
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Shuffle Music", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }
}
