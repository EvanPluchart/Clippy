import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if let notice = state.notice {
                AppNoticeBanner(notice: notice)
            }
            TabView {
                GeneralSettings()
                    .tabItem { Label("Général", systemImage: "gear") }
                StorageSettings()
                    .tabItem { Label("Stockage", systemImage: "internaldrive") }
                PrivacySettings()
                    .tabItem { Label("Confidentialité", systemImage: "hand.raised") }
                ShortcutSettings()
                    .tabItem { Label("Raccourci", systemImage: "keyboard") }
                AboutSettings()
                    .tabItem { Label("À propos", systemImage: "info.circle") }
            }
            .padding(20)
        }
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var state: AppState
    @State private var launchError: String?
    @State private var loginStatus = LaunchAtLoginService.status

    private var settings: Binding<AppSettings> {
        Binding(
            get: { state.settingsStore.value },
            set: { state.settingsStore.update($0) }
        )
    }

    var body: some View {
        Form {
            Section("Fonctionnement") {
                Toggle("Surveiller le presse-papiers", isOn: settings.monitoringEnabled)
                LabeledContent("État") {
                    Label(
                        state.monitor.isRunning
                            ? String(localized: "Surveillance active")
                            : String(localized: "Surveillance en pause"),
                        systemImage: state.monitor.isRunning ? "checkmark.circle.fill" : "pause.circle"
                    )
                    .foregroundStyle(state.monitor.isRunning ? .green : .secondary)
                }

                Toggle(
                    "Lancer Clippy à l’ouverture de session",
                    isOn: Binding(
                        get: { loginStatus == .enabled },
                        set: { enabled in setLaunchAtLogin(enabled) }
                    )
                )
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("macOS attend votre approbation dans les éléments d’ouverture.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Ouvrir les réglages") {
                            LaunchAtLoginService.openSystemSettings()
                        }
                    }
                }
                if let launchError {
                    Text(launchError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Toggle(
                    "Collage automatique",
                    isOn: settings.automaticallyPaste
                )
                Toggle(
                    "Fermer le panneau après une copie",
                    isOn: Binding(
                        get: {
                            settings.wrappedValue.automaticallyPaste ||
                                settings.wrappedValue.closeAfterCopy
                        },
                        set: { settings.wrappedValue.closeAfterCopy = $0 }
                    )
                )
                .disabled(settings.wrappedValue.automaticallyPaste)
                if settings.wrappedValue.automaticallyPaste {
                    Text("Le panneau se ferme toujours lorsqu’un collage automatique est lancé.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Afficher le panneau près du curseur", isOn: settings.quickPanelNearCursor)
            }

            Section("Présentation") {
                Picker("Apparence", selection: settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                Toggle(
                    "Afficher dans la barre des menus",
                    isOn: Binding(
                        get: { state.settingsStore.value.showMenuBarItem },
                        set: { state.setMenuBarItemVisible($0) }
                    )
                )
                Toggle(
                    "Afficher l’icône dans le Dock",
                    isOn: Binding(
                        get: { state.settingsStore.value.showDockIcon },
                        set: { state.setDockIconVisible($0) }
                    )
                )
                Text("Clippy conserve toujours au moins un point d’accès visible : barre des menus ou Dock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loginStatus = LaunchAtLoginService.status
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            loginStatus = LaunchAtLoginService.status
            var updated = state.settingsStore.value
            updated.launchAtLogin = loginStatus == .enabled
            state.settingsStore.update(updated)
            launchError = loginStatus == .requiresApproval
                ? String(localized: "Autorisez Clippy dans Réglages Système > Général > Ouverture.")
                : nil
        } catch {
            loginStatus = LaunchAtLoginService.status
            launchError = String(
                localized: "macOS n’a pas pu modifier ce réglage : \(error.localizedDescription)"
            )
        }
    }
}

private struct StorageSettings: View {
    @EnvironmentObject private var state: AppState
    @State private var confirmErase = false

    private var settings: Binding<AppSettings> {
        Binding(
            get: { state.settingsStore.value },
            set: { state.settingsStore.update($0) }
        )
    }

    var body: some View {
        Form {
            Section("Rétention") {
                Picker("Conserver les éléments", selection: settings.retentionPeriod) {
                    ForEach(RetentionPeriod.allCases) { Text($0.title).tag($0) }
                }
                Stepper(
                    "Maximum : \(settings.wrappedValue.maximumItemCount) éléments",
                    value: settings.maximumItemCount,
                    in: 100...10_000,
                    step: 100
                )
                Stepper(
                    "Stockage maximal : \(settings.wrappedValue.maximumStorageMegabytes) Mo",
                    value: settings.maximumStorageMegabytes,
                    in: 50...5_000,
                    step: 50
                )
                Picker("Doublons", selection: settings.duplicatePolicy) {
                    ForEach(DuplicatePolicy.allCases) { Text($0.title).tag($0) }
                }
                Text("Les éléments épinglés ne sont jamais supprimés automatiquement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Images") {
                Toggle("Conserver les images", isOn: settings.keepImages)
                Stepper(
                    "Taille maximale : \(settings.wrappedValue.maximumImageMegabytes) Mo",
                    value: settings.maximumImageMegabytes,
                    in: 1...200
                )
                .disabled(!settings.wrappedValue.keepImages)
                Text("Clippy conserve un PNG normalisé et charge uniquement une miniature optimisée dans les listes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Utilisation actuelle") {
                LabeledContent("Éléments", value: "\(state.repository.items.count)")
                LabeledContent("Épinglés", value: "\(state.repository.pinnedCount)")
                LabeledContent("Taille estimée", value: state.repository.totalBytes.formattedBytes)
                HStack {
                    Button("Nettoyer maintenant") {
                        Task { await state.cleanup.run() }
                    }
                    .disabled(state.cleanup.isRunning)
                    if state.cleanup.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                    Button("Afficher les données") {
                        NSWorkspace.shared.open(state.fileStorage.rootURL)
                    }
                }
                if let summary = state.cleanup.lastSummary {
                    Text(
                        L10n.cleanupSummary(
                            date: summary.date.formatted(date: .abbreviated, time: .shortened),
                            removedItems: summary.removedItems,
                            reclaimedBytes: summary.reclaimedBytes.formattedBytes
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Button("Effacer toutes les données…", role: .destructive) {
                    confirmErase = true
                }
            }

            Section("Performance") {
                Stepper(
                    String(
                        localized: "Intervalle de vérification : \(settings.wrappedValue.pollingInterval.formatted(.number.precision(.fractionLength(1)))) s"
                    ),
                    value: settings.pollingInterval,
                    in: 0.3...2,
                    step: 0.1
                )
                Text("0,5 s offre un bon équilibre entre réactivité et consommation d’énergie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Effacer définitivement toutes les données locales ?",
            isPresented: $confirmErase
        ) {
            Button("Tout effacer", role: .destructive) { state.eraseEverything() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action supprime aussi les éléments épinglés et les fichiers image.")
        }
    }
}

private struct PrivacySettings: View {
    @EnvironmentObject private var state: AppState
    @State private var exclusions = ""
    @State private var patterns = ""

    private var settings: Binding<AppSettings> {
        Binding(
            get: { state.settingsStore.value },
            set: { state.settingsStore.update($0) }
        )
    }

    private var invalidPatternCount: Int {
        lines(patterns).filter {
            $0.count > 512 || (try? NSRegularExpression(pattern: $0)) == nil
        }.count
    }

    var body: some View {
        Form {
            Section("Données locales") {
                Label(
                    "Aucune télémétrie, synchronisation, dépendance tierce ou requête réseau. Tout reste sur ce Mac.",
                    systemImage: "lock.shield"
                )
                .font(.callout)
            }

            Section("Contenus sensibles") {
                Toggle("Ignorer les contenus potentiellement sensibles", isOn: settings.ignoreSensitiveContent)
                Text("Le filtre heuristique réduit certains risques sans pouvoir garantir la détection de tous les secrets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "Expressions régulières à ignorer, une par ligne",
                    text: $patterns,
                    axis: .vertical
                )
                .lineLimit(3...6)
                if invalidPatternCount > 0 {
                    Label(
                        L10n.invalidExpressionCount(invalidPatternCount),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("Collage automatique") {
                LabeledContent("Autorisation macOS") {
                    Label(
                        state.automaticPaste.isAuthorized
                            ? String(localized: "Autorisée")
                            : String(localized: "À autoriser"),
                        systemImage: state.automaticPaste.isAuthorized
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle"
                    )
                    .foregroundStyle(state.automaticPaste.isAuthorized ? .green : .orange)
                }
                Text(
                    state.automaticPaste.requiresRelaunchAfterAuthorization
                        ? String(localized: "Dans Réglages système, activez Clippy. Si elle est déjà activée, désactivez-la puis réactivez-la avant de relancer Clippy.")
                        : String(localized: "L’autorisation Accessibilité sert uniquement à envoyer ⌘V à l’application utilisée avant Clippy.")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if !state.automaticPaste.isAuthorized {
                        if state.automaticPaste.requiresRelaunchAfterAuthorization {
                            Button("Relancer Clippy") {
                                state.relaunchAfterAutomaticPasteAuthorization()
                            }
                        } else {
                            Button("Ouvrir les réglages") {
                                state.requestAutomaticPasteAuthorization()
                            }
                        }
                    }
                    Button("Actualiser l’état") {
                        state.automaticPaste.refreshAuthorization()
                    }
                }
            }

            Section("Applications exclues") {
                TextField(
                    "Identifiants de bundle, un par ligne",
                    text: $exclusions,
                    axis: .vertical
                )
                .lineLimit(4...8)
                Text("Tous les formats provenant de ces apps sont ignorés. Exemple : com.example.PasswordManager")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Types ignorés") {
                ForEach(ClipboardItemType.allCases.filter { $0 != .unknown }) { type in
                    Toggle(
                        type.title,
                        isOn: Binding(
                            get: { settings.wrappedValue.ignoredTypes.contains(type) },
                            set: { ignored in
                                if ignored {
                                    settings.wrappedValue.ignoredTypes.insert(type)
                                } else {
                                    settings.wrappedValue.ignoredTypes.remove(type)
                                }
                            }
                        )
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            exclusions = settings.wrappedValue.excludedBundleIdentifiers.joined(separator: "\n")
            patterns = settings.wrappedValue.sensitivePatterns.joined(separator: "\n")
            state.automaticPaste.refreshAuthorization()
        }
        .onChange(of: exclusions) { _, value in
            settings.wrappedValue.excludedBundleIdentifiers = lines(value)
        }
        .onChange(of: patterns) { _, value in
            settings.wrappedValue.sensitivePatterns = lines(value)
        }
    }

    private func lines(_ value: String) -> [String] {
        value
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private struct ShortcutSettings: View {
    @EnvironmentObject private var state: AppState
    @State private var draft = ShortcutConfiguration()
    @State private var applied = false

    var body: some View {
        Form {
            Section("Panneau rapide") {
                Picker("Touche", selection: $draft.keyCode) {
                    ForEach(KeyCodeMap.keys, id: \.1) { Text($0.0).tag($0.1) }
                }
                Toggle("Commande ⌘", isOn: modifier(UInt32(cmdKey)))
                Toggle("Majuscule ⇧", isOn: modifier(UInt32(shiftKey)))
                Toggle("Option ⌥", isOn: modifier(UInt32(optionKey)))
                Toggle("Contrôle ⌃", isOn: modifier(UInt32(controlKey)))
                LabeledContent("Raccourci proposé", value: draft.display)
                LabeledContent(
                    "Raccourci actif",
                    value: state.shortcut.registeredConfiguration?.display
                        ?? String(localized: "Aucun")
                )

                if !draft.isValid {
                    Label(
                        "Ajoutez Commande, Option ou Contrôle pour ne pas intercepter une touche normale.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if let message = state.shortcut.conflictMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                if applied {
                    Label("Raccourci appliqué", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                HStack {
                    Button("Appliquer") {
                        applied = state.applyShortcut(draft)
                    }
                    .disabled(!draft.isValid || draft == state.shortcut.registeredConfiguration)
                    Button("Rétablir ⌘⇧V") {
                        draft = ShortcutConfiguration()
                        applied = state.applyShortcut(draft)
                    }
                    Spacer()
                    Button("Tester") {
                        state.showQuickPanel()
                    }
                }
            }

            Section {
                Text("Le raccourci global utilise l’API système RegisterEventHotKey. Il ne surveille pas les frappes et ne demande aucune permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            draft = state.settingsStore.value.shortcut
            applied = false
        }
        .onChange(of: draft) { _, _ in applied = false }
    }

    private func modifier(_ flag: UInt32) -> Binding<Bool> {
        Binding(
            get: { draft.carbonModifiers & flag != 0 },
            set: { enabled in
                if enabled {
                    draft.carbonModifiers |= flag
                } else {
                    draft.carbonModifiers &= ~flag
                }
            }
        )
    }
}

private struct AboutSettings: View {
    @EnvironmentObject private var state: AppState

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 18) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)
            }
            Text("Clippy")
                .font(.largeTitle.bold())
            Text("Historique de presse-papiers natif, rapide et privé pour macOS.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Version \(version) (\(build))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack {
                Button("Voir sur GitHub") {
                    open("https://github.com/EvanPluchart/Clippy")
                }
                Button("Afficher l’introduction") {
                    state.showOnboarding()
                }
                Button("Copier la commande Homebrew") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(
                        "brew install --cask EvanPluchart/tap/clippy",
                        forType: .string
                    )
                    state.monitor.suppress(changeCount: pasteboard.changeCount)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("100 % local", systemImage: "internaldrive")
                    Label("Aucune dépendance tierce", systemImage: "shippingbox")
                    Label("Aucune télémétrie ni requête réseau", systemImage: "network.slash")
                    Label("SwiftUI + AppKit", systemImage: "swift")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            .frame(maxWidth: 420)

            Spacer()
            Text("Créé par Evan Pluchart · © 2026")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
