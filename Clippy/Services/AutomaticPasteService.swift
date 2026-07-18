import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum AutomaticPasteOutcome: Equatable {
    case pasted
    case copiedOnly
    case permissionRequired
    case targetUnavailable
    case eventPostingFailed
}

@MainActor
final class AutomaticPasteService: ObservableObject {
    @Published private(set) var isAuthorized = CGPreflightPostEventAccess()
    @Published private(set) var lastOutcome: AutomaticPasteOutcome?

    private var requestedPermissionThisSession = false

    func refreshAuthorization() {
        isAuthorized = CGPreflightPostEventAccess()
        if isAuthorized, lastOutcome == .permissionRequired {
            lastOutcome = nil
        }
    }

    @discardableResult
    func requestAuthorization() -> Bool {
        requestedPermissionThisSession = true
        let granted = CGRequestPostEventAccess()
        isAuthorized = granted || CGPreflightPostEventAccess()
        if !isAuthorized { lastOutcome = .permissionRequired }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.refreshAuthorization()
        }
        return isAuthorized
    }

    func restoreFocus(
        to application: NSRunningApplication?,
        automaticallyPaste: Bool,
        completion: ((AutomaticPasteOutcome) -> Void)? = nil
    ) {
        guard automaticallyPaste else {
            if let application, !application.isTerminated {
                activateIfNeeded(application)
            }
            finish(.copiedOnly, completion: completion)
            return
        }

        guard let application, !application.isTerminated else {
            finish(.targetUnavailable, completion: completion)
            return
        }

        refreshAuthorization()
        if !isAuthorized, !requestedPermissionThisSession {
            _ = requestAuthorization()
        }
        guard isAuthorized else {
            activateIfNeeded(application)
            NSSound.beep()
            finish(.permissionRequired, completion: completion)
            return
        }

        activateIfNeeded(application)
        // Let AppKit restore the target app's key window after the quick panel
        // disappears before posting Command-V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.pasteWhenApplicationIsReady(application, attempt: 0, completion: completion)
        }
    }

    private func pasteWhenApplicationIsReady(
        _ application: NSRunningApplication,
        attempt: Int,
        completion: ((AutomaticPasteOutcome) -> Void)?
    ) {
        guard !application.isTerminated else {
            finish(.targetUnavailable, completion: completion)
            return
        }

        let targetIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
        guard targetIsFrontmost else {
            guard attempt < 40 else {
                NSSound.beep()
                finish(.targetUnavailable, completion: completion)
                return
            }
            activateIfNeeded(application)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                self?.pasteWhenApplicationIsReady(application, attempt: attempt + 1, completion: completion)
            }
            return
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ) else {
            NSSound.beep()
            finish(.eventPostingFailed, completion: completion)
            return
        }

        source.localEventsSuppressionInterval = 0
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
            keyUp.post(tap: .cgSessionEventTap)
            self?.finish(.pasted, completion: completion)
        }
    }

    private func activateIfNeeded(_ application: NSRunningApplication) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != application.processIdentifier else {
            return
        }
        application.activate(options: [])
    }

    private func finish(
        _ outcome: AutomaticPasteOutcome,
        completion: ((AutomaticPasteOutcome) -> Void)?
    ) {
        lastOutcome = outcome
        completion?(outcome)
    }
}
