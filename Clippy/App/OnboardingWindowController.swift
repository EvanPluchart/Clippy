import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var closeHandler: (() -> Void)?
    private var suppressNextCloseCallback = false

    func show(state: AppState, onClose: @escaping () -> Void) {
        closeHandler = onClose
        let window = window ?? makeWindow(state: state)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let window, window.isVisible else { return }
        suppressNextCloseCallback = true
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        if suppressNextCloseCallback {
            suppressNextCloseCallback = false
            return
        }
        closeHandler?()
    }

    private func makeWindow(state: AppState) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Bienvenue dans Clippy")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: OnboardingView().environmentObject(state)
        )
        return window
    }
}
