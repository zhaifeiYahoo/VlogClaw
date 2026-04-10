import SwiftUI

enum StudioTheme {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.063)
    static let panel = Color(red: 0.078, green: 0.094, blue: 0.129)
    static let panelRaised = Color(red: 0.102, green: 0.118, blue: 0.161)
    static let border = Color.white.opacity(0.11)
    static let primaryText = Color(red: 0.96, green: 0.98, blue: 1.0)
    static let secondaryText = Color(red: 0.61, green: 0.67, blue: 0.77)
    static let accent = Color(red: 0.44, green: 0.88, blue: 1.0)
    static let warmAccent = Color(red: 1.0, green: 0.74, blue: 0.47)
    static let success = Color(red: 0.43, green: 0.9, blue: 0.63)
    static let danger = Color(red: 1.0, green: 0.44, blue: 0.42)

    static func statusColor(_ status: DeviceConnectionState) -> Color {
        switch status {
        case .connected:
            return success
        case .connecting:
            return warmAccent
        case .error:
            return danger
        case .disconnected:
            return secondaryText
        }
    }

    static func taskColor(_ status: StudioTaskStatus) -> Color {
        switch status {
        case .completed:
            return success
        case .running:
            return accent
        case .pending:
            return warmAccent
        case .failed, .cancelled:
            return danger
        }
    }

    static func backendColor(_ state: BackendRuntimeState) -> Color {
        switch state {
        case .running:
            return success
        case .launching:
            return warmAccent
        case .failed:
            return danger
        case .idle, .stopped:
            return secondaryText
        }
    }
}

struct StudioBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.01, green: 0.06, blue: 0.09),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { proxy in
                Path { path in
                    let step: CGFloat = 28
                    for x in stride(from: 0, through: proxy.size.width, by: step) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    }
                    for y in stride(from: 0, through: proxy.size.height, by: step) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.035), lineWidth: 0.5)
            }

            Circle()
                .fill(StudioTheme.accent.opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: 280, y: -260)

            Circle()
                .fill(StudioTheme.warmAccent.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -420, y: 280)
        }
        .ignoresSafeArea()
    }
}

struct StudioPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(StudioTheme.panel.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.32), radius: 28, x: 0, y: 16)
    }
}

extension View {
    func studioPanel() -> some View {
        modifier(StudioPanelModifier())
    }
}

struct SectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.accent)
                .tracking(1.2)
            Text(title)
                .font(.custom("Avenir Next", size: 24))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)
            Text(subtitle)
                .font(.custom("Avenir Next", size: 13))
                .foregroundStyle(StudioTheme.secondaryText)
        }
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(StudioTheme.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(color.opacity(0.16))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.42), lineWidth: 1)
        )
    }
}

struct ActionButtonStyle: ButtonStyle {
    let fill: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(foreground.opacity(configuration.isPressed ? 0.86 : 1))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.7), lineWidth: 1)
            )
    }
}
