import AppKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var model = ClipboardHistoryViewModel()
    @State private var confirmClear = false

    private var filtered: [ClipboardItem] {
        model.filtered(state.repository.items)
    }

    private var visible: [ClipboardItem] {
        Array(filtered.prefix(model.displayLimit))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.filter) {
                Label("Tout l’historique", systemImage: "clock.arrow.circlepath")
                    .tag(nil as ClipboardItemType?)
                Section("Types") {
                    ForEach(ClipboardItemType.allCases.filter { $0 != .unknown }) { type in
                        Label(type.title, systemImage: type.symbol)
                            .tag(type as ClipboardItemType?)
                    }
                }
                Section("Résumé") {
                    LabeledContent("Éléments", value: "\(state.repository.items.count)")
                    LabeledContent("Épinglés", value: "\(state.repository.pinnedCount)")
                    LabeledContent("Stockage", value: state.repository.totalBytes.formattedBytes)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                if let warning = state.storageWarning ?? state.repository.lastError {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.1))
                }
                if let notice = state.notice {
                    AppNoticeBanner(notice: notice)
                }

                HStack {
                    TextField("Rechercher dans l’historique", text: $model.query)
                        .textFieldStyle(.roundedBorder)
                    Picker("Tri", selection: $model.sortOrder) {
                        ForEach(ClipboardHistoryViewModel.SortOrder.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .frame(width: 160)
                    Button {
                        state.showQuickPanel()
                    } label: {
                        Label("Panneau rapide", systemImage: "rectangle.on.rectangle")
                    }
                }
                .padding()

                Divider()

                if visible.isEmpty {
                    ContentUnavailableView(
                        model.query.isEmpty
                            ? String(localized: "Historique vide")
                            : String(localized: "Aucun résultat"),
                        systemImage: model.query.isEmpty ? "clipboard" : "magnifyingglass",
                        description: Text(
                            model.query.isEmpty
                                ? String(localized: "Les prochains éléments copiés apparaîtront ici.")
                                : String(localized: "Essayez une autre recherche ou un autre filtre.")
                        )
                    )
                } else {
                    historyList
                }
            }
            .navigationTitle("Historique")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        setSelectionPinned(!selectionIsFullyPinned)
                    } label: {
                        Label(
                            selectionIsFullyPinned
                                ? String(localized: "Désépingler")
                                : String(localized: "Épingler"),
                            systemImage: selectionIsFullyPinned ? "pin.slash" : "pin"
                        )
                    }
                    .disabled(model.selection.isEmpty)

                    Button {
                        copySelection()
                    } label: {
                        Label("Copier", systemImage: "doc.on.doc")
                    }
                    .disabled(model.selection.count != 1)

                    Button(role: .destructive) {
                        deleteSelection()
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                    .disabled(model.selection.isEmpty)

                    Button {
                        confirmClear = true
                    } label: {
                        Label("Vider", systemImage: "trash.slash")
                    }
                    .disabled(state.repository.items.allSatisfy(\.isPinned))
                }
            }
            .confirmationDialog("Vider l’historique non épinglé ?", isPresented: $confirmClear) {
                Button("Vider", role: .destructive) { state.clearHistory() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Les éléments épinglés seront conservés.")
            }
        }
        .onChange(of: model.query) { _, _ in
            model.resetPagination()
            model.selection.removeAll()
        }
        .onChange(of: model.filter) { _, _ in
            model.resetPagination()
            model.selection.removeAll()
        }
        .onChange(of: model.sortOrder) { _, _ in
            model.resetPagination()
        }
        .onChange(of: state.repository.items.map(\.id)) { _, availableIDs in
            model.selection.formIntersection(availableIDs)
            model.resetPagination()
        }
    }

    private var historyList: some View {
        List(selection: $model.selection) {
            ForEach(visible) { item in
                ClipboardItemRow(item: item)
                    .tag(item.id)
            }
            if visible.count < filtered.count {
                HStack {
                    Spacer()
                    Button("Afficher 200 éléments supplémentaires") {
                        model.loadMore()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
        }
        .background {
            HistoryDoubleClickMonitor {
                copySelection()
            }
        }
        .onDeleteCommand { deleteSelection() }
        .onCopyCommand {
            if let item = state.repository.items.first(where: { model.selection.contains($0.id) }) {
                state.copy(item)
            }
            return []
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(L10n.resultCount(filtered.count))
                Spacer()
                if !model.selection.isEmpty {
                    Text(L10n.selectionCount(model.selection.count))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.bar)
        }
    }

    private func deleteSelection() {
        state.delete(state.repository.items.filter { model.selection.contains($0.id) })
        model.selection.removeAll()
    }

    private func copySelection() {
        guard model.selection.count == 1,
              let item = state.repository.items.first(where: { model.selection.contains($0.id) }) else {
            return
        }
        state.copy(item)
    }

    private var selectionIsFullyPinned: Bool {
        !model.selection.isEmpty &&
        state.repository.items
            .filter { model.selection.contains($0.id) }
            .allSatisfy(\.isPinned)
    }

    private func setSelectionPinned(_ pinned: Bool) {
        state.repository.setPinned(ids: model.selection, pinned: pinned)
    }
}

private struct HistoryDoubleClickMonitor: NSViewRepresentable {
    let action: @MainActor () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.action = action
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    @MainActor
    final class MonitorView: NSView {
        var action: (@MainActor () -> Void)?
        private var eventMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self,
                      event.window === self.window,
                      event.clickCount == 2,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else {
                    return event
                }
                DispatchQueue.main.async { [weak self] in self?.action?() }
                return event
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        func stopMonitoring() {
            guard let eventMonitor else { return }
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

    }
}
