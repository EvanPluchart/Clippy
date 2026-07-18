import SwiftUI

struct AppNoticeBanner: View {
    @EnvironmentObject private var state: AppState
    let notice: AppNotice

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(notice.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                state.clearNotice()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Fermer le message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch notice.kind {
        case .information: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch notice.kind {
        case .information: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }
}
