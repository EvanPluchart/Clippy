import AppKit
import SwiftUI

@main
struct ClippyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("Clippy", systemImage: state.monitor.isRunning ? "clipboard.fill" : "clipboard", isInserted: Binding(
            get: { state.settingsStore.value.showMenuBarItem },
            set: { state.setMenuBarItemVisible($0) }
        )) {
            MenuBarView().environmentObject(state)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") {
                    state.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shouldSuppressNextReopen = ProcessInfo.processInfo.arguments.contains(
        ApplicationRelauncher.relaunchArgument
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
        #if DEBUG || QA
        AppState.shared.seedPreviewDataIfRequested()
        let environment = ProcessInfo.processInfo.environment
        let smokeScreen = environment["CLIPPY_SMOKE_SCREEN"]
            ?? (environment["CLIPPY_SMOKE_SHOW_PANEL"] == "1" ? "panel" : nil)
        if let smokeScreen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                switch smokeScreen {
                case "panel":
                    AppState.shared.showQuickPanel()
                case "paste":
                    AppState.shared.showQuickPanel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        guard let item = AppState.shared.repository.items.first(where: {
                            $0.type == .plainText
                        }) else {
                            Log.general.error("QA paste smoke test could not find a text item")
                            return
                        }
                        AppState.shared.selectFromQuickPanel(item)
                    }
                case "history":
                    AppState.shared.showHistory()
                case "onboarding":
                    AppState.shared.showOnboarding()
                case "settings":
                    AppState.shared.showSettings()
                default:
                    Log.general.error("Unknown QA smoke screen: \(smokeScreen, privacy: .public)")
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                AppState.shared.showOnboardingIfNeeded()
            }
        }
        #else
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            AppState.shared.showOnboardingIfNeeded()
        }
        #endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppState.shared.refreshSystemState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let shouldSuppress = AppState.shared.shouldSuppressApplicationReopen || shouldSuppressNextReopen
        shouldSuppressNextReopen = false
        if Self.shouldShowHistoryOnReopen(
            hasVisibleWindows: flag,
            shouldSuppress: shouldSuppress
        ) {
            AppState.shared.showHistory()
        }
        return true
    }

    static func shouldShowHistoryOnReopen(
        hasVisibleWindows: Bool,
        shouldSuppress: Bool
    ) -> Bool {
        !hasVisibleWindows && !shouldSuppress
    }
}
