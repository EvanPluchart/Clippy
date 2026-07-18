import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class GlobalShortcutService: ObservableObject {
    @Published private(set) var conflictMessage: String?
    @Published private(set) var registeredConfiguration: ShortcutConfiguration?

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?
    private var nextIdentifier: UInt32 = 1

    @discardableResult
    func register(configuration: ShortcutConfiguration, action: @escaping () -> Void) -> Bool {
        self.action = action
        guard configuration.isValid else {
            conflictMessage = "Ajoutez Commande, Option ou Contrôle pour éviter de bloquer une touche normale."
            return false
        }
        if registeredConfiguration == configuration, hotKey != nil {
            conflictMessage = nil
            return true
        }
        guard installEventHandlerIfNeeded() else { return false }

        let identifier = EventHotKeyID(signature: OSType(0x434C5059), id: nextIdentifier) // CLPY
        nextIdentifier &+= 1
        var candidate: EventHotKeyRef?
        let registration = RegisterEventHotKey(
            configuration.keyCode,
            configuration.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &candidate
        )
        guard registration == noErr, let candidate else {
            conflictMessage = "Ce raccourci est déjà utilisé par macOS ou une autre application."
            return false
        }

        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = candidate
        registeredConfiguration = configuration
        conflictMessage = nil
        return true
    }

    private func installEventHandlerIfNeeded() -> Bool {
        guard eventHandler == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<GlobalShortcutService>.fromOpaque(userData).takeUnretainedValue()
            // Let Carbon finish dispatching the keyboard event before AppKit
            // activates a SwiftUI-hosting panel. Opening synchronously can make
            // AppKit re-enter SwiftUI hit testing while the event is unwinding.
            DispatchQueue.main.async { service.action?() }
            return noErr
        }, 1, &eventType, pointer, &eventHandler)
        guard status == noErr else {
            conflictMessage = "Le gestionnaire de raccourci n’a pas pu être installé."
            return false
        }
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
        registeredConfiguration = nil
    }
}
