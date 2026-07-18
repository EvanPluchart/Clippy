import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Text(
            state.monitor.isRunning
                ? "\(state.repository.items.count) élément(s) · Surveillance active"
                : "\(state.repository.items.count) élément(s) · Surveillance en pause"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if let conflict = state.shortcut.conflictMessage {
            Label(conflict, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        Divider()

        Button("Afficher le panneau rapide  \(state.settingsStore.value.shortcut.display)") {
            state.showQuickPanel()
        }
        Button("Ouvrir l’historique") {
            state.showHistory()
        }

        Divider()

        if state.monitor.isRunning {
            Button("Mettre la surveillance en pause") {
                var settings = state.settingsStore.value
                settings.monitoringEnabled = false
                state.settingsStore.update(settings)
            }
        } else {
            Button("Reprendre la surveillance") { state.monitor.resume() }
        }
        Button("Vider l’historique non épinglé…") { state.confirmAndClearHistory() }
            .disabled(state.repository.items.allSatisfy(\.isPinned))

        Divider()

        Button("Réglages…") { state.showSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Button("Quitter Clippy") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
