import SwiftUI

struct QuickPanelView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = ClipboardHistoryViewModel()
    @FocusState private var searchFocused: Bool
    @State private var selectedIndex = 0
    @State private var hoveredItemID: UUID?
    @State private var confirmClear = false

    private var visible: [ClipboardItem] {
        model.filtered(state.repository.items, limit: 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            TypeFilterBar(selection: $model.filter)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            Divider()
            content
            if let notice = state.notice {
                AppNoticeBanner(notice: notice)
            }
            if state.settingsStore.value.automaticallyPaste && !state.automaticPaste.isAuthorized {
                permissionNotice
            }
            footer
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.12), lineWidth: 1)
        }
        .padding(1)
        .onAppear { resetForPresentation() }
        .onChange(of: model.query) { _, _ in selectedIndex = 0 }
        .onChange(of: model.filter) { _, _ in selectedIndex = 0 }
        .onChange(of: visible.map(\.id)) { _, _ in normalizeSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .quickPanelDidOpen)) { _ in
            resetForPresentation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickPanelMoveDown)) { _ in
            moveSelection(by: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickPanelMoveUp)) { _ in
            moveSelection(by: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickPanelConfirmSelection)) { _ in
            copySelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickPanelSelectIndex)) { notification in
            if let index = notification.object as? Int { copy(at: index) }
        }
    }

    @ViewBuilder
    private var header: some View {
        if confirmClear {
            HStack(spacing: 10) {
                Label("Vider l’historique non épinglé ?", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Annuler") { confirmClear = false }
                    .keyboardShortcut(.cancelAction)
                Button("Vider", role: .destructive) {
                    state.clearHistory()
                    confirmClear = false
                }
                .disabled(state.repository.items.allSatisfy(\.isPinned))
            }
            .padding(12)
            .background(.bar)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "clipboard.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                TextField("Rechercher", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { copySelected() }
                    .accessibilityLabel("Rechercher dans l’historique")
                Text(state.settingsStore.value.shortcut.display)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button {
                    confirmClear = true
                } label: {
                    Image(systemName: "trash.slash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Vider l’historique"))
                .disabled(state.repository.items.allSatisfy(\.isPinned))
                Button {
                    state.hideQuickPanel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Fermer"))
            }
            .padding(12)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var content: some View {
        if visible.isEmpty {
            ContentUnavailableView(
                model.query.isEmpty
                    ? String(localized: "Aucun élément")
                    : String(localized: "Aucun résultat"),
                systemImage: model.query.isEmpty ? "clipboard" : "magnifyingglass",
                description: Text(
                    model.query.isEmpty
                        ? String(localized: "Copiez du texte, une image, un lien ou un fichier.")
                        : String(localized: "Essayez une autre recherche ou un autre filtre.")
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                            quickRow(item, index: index)
                                .id(item.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selectedIndex) { _, index in
                    guard visible.indices.contains(index) else { return }
                    if reduceMotion {
                        proxy.scrollTo(visible[index].id, anchor: .center)
                    } else {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(visible[index].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func quickRow(_ item: ClipboardItem, index: Int) -> some View {
        HStack(spacing: 2) {
            ClipboardItemRow(
                item: item,
                compact: true,
                shortcutLabel: index < 9 ? "⌘\(index + 1)" : nil
            )
            .onTapGesture { state.selectFromQuickPanel(item) }
            .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])

            VStack(spacing: 4) {
                Button {
                    state.repository.togglePinned(item)
                } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(
                    item.isPinned
                        ? String(localized: "Désépingler")
                        : String(localized: "Épingler")
                )
                .accessibilityLabel(
                    item.isPinned
                        ? String(localized: "Désépingler")
                        : String(localized: "Épingler")
                )

                Button(role: .destructive) {
                    state.delete([item])
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Supprimer"))
                .accessibilityLabel(String(localized: "Supprimer"))
            }
            .padding(.trailing, 8)
        }
        .background(
            index == selectedIndex
                ? Color.accentColor.opacity(0.16)
                : (hoveredItemID == item.id ? Color.primary.opacity(0.08) : Color.primary.opacity(0.035)),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            if index == selectedIndex {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
        }
    }

    private var permissionNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(.orange)
            Text("Autorisez le collage automatique pour coller directement dans l’app précédente.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Autoriser") {
                _ = state.automaticPaste.requestAuthorization()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("↑↓ Naviguer  ·  ↩ Coller  ·  esc Fermer")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(L10n.itemCount(visible.count))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private func resetForPresentation() {
        confirmClear = false
        model.query = ""
        model.filter = nil
        selectedIndex = 0
        hoveredItemID = nil
        DispatchQueue.main.async { searchFocused = true }
    }

    private func normalizeSelection() {
        if visible.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, visible.count - 1)
        }
    }

    private func moveSelection(by offset: Int) {
        guard !visible.isEmpty else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + offset, 0), visible.count - 1)
    }

    private func copySelected() {
        copy(at: selectedIndex)
    }

    private func copy(at index: Int) {
        guard visible.indices.contains(index) else { return }
        state.selectFromQuickPanel(visible[index])
    }
}

extension Notification.Name {
    static let quickPanelDidOpen = Notification.Name("Clippy.QuickPanel.DidOpen")
    static let quickPanelMoveUp = Notification.Name("Clippy.QuickPanel.MoveUp")
    static let quickPanelMoveDown = Notification.Name("Clippy.QuickPanel.MoveDown")
    static let quickPanelConfirmSelection = Notification.Name("Clippy.QuickPanel.ConfirmSelection")
    static let quickPanelSelectIndex = Notification.Name("Clippy.QuickPanel.SelectIndex")
}
