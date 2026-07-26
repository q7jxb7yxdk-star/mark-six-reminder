import SwiftUI

/// Applies the shared elevated surface used by feature cards throughout the app.
private struct AppCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
    }
}

extension View {
    /// Wraps content in the app's standard adaptive card treatment.
    func appCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(AppCardModifier(cornerRadius: cornerRadius))
    }
}

/// A consistent inline message for progress, success, information and errors.
struct AppStatusMessage: View {
    enum Kind {
        case progress
        case success
        case info
        case error

        /// Returns the semantic foreground color for this message type.
        var color: Color {
            switch self {
            case .progress, .info:
                .secondary
            case .success:
                .green
            case .error:
                .red
            }
        }

        /// Returns the symbol used when the message is not showing progress.
        var systemImage: String {
            switch self {
            case .progress:
                ""
            case .success:
                "checkmark.circle.fill"
            case .info:
                "info.circle.fill"
            case .error:
                "exclamationmark.triangle.fill"
            }
        }
    }

    let message: String
    let kind: Kind

    var body: some View {
        HStack(spacing: 10) {
            if kind == .progress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(kind.color)
            }

            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(kind.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(kind.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
