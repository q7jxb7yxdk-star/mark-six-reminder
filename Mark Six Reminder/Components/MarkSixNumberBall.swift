import SwiftUI

/// A reusable SwiftUI rendering of a Mark Six number ball using its standard color group.
struct MarkSixNumberBall: View {
    let number: Int?
    let size: CGFloat
    let isHighlighted: Bool

    /// Creates a number ball, or a neutral zero placeholder when no number is supplied.
    init(number: Int?, size: CGFloat = 76, isHighlighted: Bool = false) {
        self.number = number
        self.size = size
        self.isHighlighted = isHighlighted
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: palette.gradientColors,
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(white: 0.92)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .padding(size * 0.18)

            Text(number ?? 0, format: .number)
                .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: size, height: size)
        .overlay {
            Circle()
                .stroke(
                    isHighlighted ? Color.yellow : Color.white.opacity(0.45),
                    lineWidth: isHighlighted ? max(3, size * 0.08) : 1
                )
        }
        .scaleEffect(isHighlighted ? 1.04 : 1)
        .shadow(color: .black.opacity(0.16), radius: size * 0.08, y: size * 0.04)
        .contentShape(Circle())
        .animation(.snappy(duration: 0.18), value: isHighlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Resolves the official color group, or the neutral placeholder palette.
    private var palette: MarkSixBallPalette {
        guard let number else {
            return .placeholder
        }
        return MarkSixBallPalette.palette(for: number)
    }

    /// Describes the ball clearly for VoiceOver without treating zero as a valid draw number.
    private var accessibilityLabel: String {
        guard let number else {
            return "尚未產生號碼"
        }
        let matchDescription = isHighlighted ? "，已命中" : ""
        return "\(palette.accessibilityName)號碼球 \(number)\(matchDescription)"
    }
}

/// Defines the standard color grouping and accessible appearance of Mark Six balls.
private enum MarkSixBallPalette {
    case placeholder
    case red
    case blue
    case green

    private static let redNumbers: Set<Int> = [
        1, 2, 7, 8, 12, 13, 18, 19, 23, 24, 29, 30, 34, 35, 40, 45, 46,
    ]

    private static let blueNumbers: Set<Int> = [
        3, 4, 9, 10, 14, 15, 20, 25, 26, 31, 36, 37, 41, 42, 47, 48,
    ]

    /// Maps a valid number from 1 through 49 to its standard color group.
    static func palette(for number: Int) -> Self {
        precondition((1...49).contains(number), "Mark Six ball numbers must be between 1 and 49.")

        if redNumbers.contains(number) {
            return .red
        }
        if blueNumbers.contains(number) {
            return .blue
        }
        return .green
    }

    /// Provides the light-to-dark gradient sampled from the current official web presentation.
    var gradientColors: [Color] {
        switch self {
        case .placeholder:
            [Color(white: 0.68), Color(white: 0.42)]
        case .red:
            [Color(red: 0.88, green: 0.26, blue: 0.26), Color(red: 0.59, green: 0.15, blue: 0.11)]
        case .blue:
            [Color(red: 0.22, green: 0.58, blue: 0.84), Color(red: 0.00, green: 0.22, blue: 0.48)]
        case .green:
            [Color(red: 0.47, green: 0.67, blue: 0.33), Color(red: 0.21, green: 0.38, blue: 0.08)]
        }
    }

    /// Returns the Traditional Chinese color name used by VoiceOver.
    var accessibilityName: String {
        switch self {
        case .placeholder:
            "灰色"
        case .red:
            "紅色"
        case .blue:
            "藍色"
        case .green:
            "綠色"
        }
    }
}

#Preview {
    HStack {
        MarkSixNumberBall(number: nil)
        MarkSixNumberBall(number: 1)
        MarkSixNumberBall(number: 3, isHighlighted: true)
        MarkSixNumberBall(number: 5)
    }
    .padding()
}
