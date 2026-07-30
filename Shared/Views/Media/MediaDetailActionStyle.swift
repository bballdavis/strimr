import SwiftUI

enum MediaDetailActionTreatment {
    case primary
    case secondary
}

struct MediaDetailActionStyle: ButtonStyle {
    let treatment: MediaDetailActionTreatment
    let secondarySideLength: CGFloat

    init(
        treatment: MediaDetailActionTreatment,
        secondarySideLength: CGFloat = 64,
    ) {
        self.treatment = treatment
        self.secondarySideLength = secondarySideLength
    }

    private var cornerRadius: CGFloat {
        treatment == .primary ? 20 : 16
    }

    private var minimumHeight: CGFloat {
        treatment == .primary ? 70 : 56
    }

    private var accentFillOpacity: Double {
        treatment == .primary ? 0.30 : 0.18
    }

    private var foregroundColor: Color {
        treatment == .primary ? .white : .accentColor
    }

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if treatment == .primary {
                configuration.label
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: minimumHeight)
            } else {
                configuration.label
                    .frame(width: secondarySideLength, height: secondarySideLength)
            }
        }
        .foregroundStyle(foregroundColor)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(accentFillOpacity))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.accentColor.opacity(0.68), lineWidth: 1.5)
        }
        .shadow(
            color: Color.accentColor.opacity(configuration.isPressed ? 0.10 : 0.18),
            radius: configuration.isPressed ? 3 : 8,
            y: configuration.isPressed ? 2 : 4,
        )
        .scaleEffect(configuration.isPressed ? 0.96 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
