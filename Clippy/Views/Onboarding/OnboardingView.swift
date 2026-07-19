import AppKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @State private var loginStatus = LaunchAtLoginService.status
    @State private var launchError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 26) {
                    hero
                    features
                    if let conflict = state.shortcut.conflictMessage {
                        shortcutWarning(conflict)
                    }
                    permissionCard
                }
                .padding(.horizontal, 42)
                .padding(.top, 38)
                .padding(.bottom, 28)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle(
                        "Lancer Clippy à l’ouverture de session",
                        isOn: Binding(
                            get: { loginStatus == .enabled },
                            set: { setLaunchAtLogin($0) }
                        )
                    )
                    .font(.callout)
                    Text(
                        launchError
                            ?? (loginStatus == .requiresApproval
                                ? String(
                                    localized: "macOS attend votre approbation dans les éléments d’ouverture."
                                )
                                : String(
                                    localized: "Recommandé pour garder le raccourci disponible en permanence."
                                ))
                    )
                    .font(.caption)
                    .foregroundStyle(launchError == nil ? Color.secondary : Color.red)
                }
                Spacer()
                Button("Commencer") {
                    state.completeOnboarding(openQuickPanel: true)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(.bar)
        }
        .frame(width: 720, height: 560)
        .onAppear {
            loginStatus = LaunchAtLoginService.status
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Bienvenue dans Clippy")
                .font(.largeTitle.bold())
            Text("Retrouvez et collez instantanément ce que vous avez copié, sans quitter l’app en cours.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
    }

    private var features: some View {
        HStack(alignment: .top, spacing: 14) {
            feature(
                symbol: "command",
                title: state.settingsStore.value.shortcut.display,
                detail: String(localized: "Ouvre le panneau rapide partout sur macOS.")
            )
            feature(
                symbol: "arrow.up.arrow.down",
                title: String(localized: "Tout au clavier"),
                detail: String(localized: "Flèches, Entrée, Échap et ⌘1 à ⌘9.")
            )
            feature(
                symbol: "lock.shield",
                title: String(localized: "100 % local"),
                detail: String(localized: "Aucune donnée, télémétrie ou requête réseau.")
            )
        }
    }

    private func feature(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var permissionCard: some View {
        HStack(spacing: 14) {
            Image(
                systemName: state.automaticPaste.isAuthorized
                    ? "checkmark.shield.fill"
                    : "hand.raised.fill"
            )
            .font(.title2)
            .foregroundStyle(state.automaticPaste.isAuthorized ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    state.automaticPaste.isAuthorized
                        ? String(localized: "Collage automatique autorisé")
                        : String(localized: "Autorisez le collage automatique")
                )
                .font(.headline)
                Text("Clippy utilise l’autorisation Accessibilité uniquement pour envoyer ⌘V à l’app précédente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !state.automaticPaste.isAuthorized {
                Button("Autoriser") {
                    _ = state.automaticPaste.requestAuthorization()
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private func shortcutWarning(_ message: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "keyboard.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Raccourci indisponible")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Configurer") {
                state.showSettings()
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            loginStatus = LaunchAtLoginService.status
            var settings = state.settingsStore.value
            settings.launchAtLogin = loginStatus == .enabled
            state.settingsStore.update(settings)
            launchError = nil
        } catch {
            loginStatus = LaunchAtLoginService.status
            launchError = String(localized: "macOS n’a pas pu modifier ce réglage.")
        }
    }
}
