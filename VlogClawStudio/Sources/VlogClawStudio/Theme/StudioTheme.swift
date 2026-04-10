import SwiftUI

enum StudioTheme {
    static let background = Color(red: 0.95, green: 0.98, blue: 1.0)
    static let backgroundTint = Color(red: 0.88, green: 0.95, blue: 0.97)
    static let sidebarPanel = Color.white.opacity(0.76)
    static let panel = Color.white.opacity(0.88)
    static let panelRaised = Color(red: 0.97, green: 0.98, blue: 1.0)
    static let panelStrong = Color(red: 0.92, green: 0.95, blue: 0.98)
    static let border = Color(red: 0.79, green: 0.86, blue: 0.91)
    static let borderStrong = Color(red: 0.69, green: 0.78, blue: 0.85)
    static let primaryText = Color(red: 0.10, green: 0.16, blue: 0.22)
    static let secondaryText = Color(red: 0.32, green: 0.41, blue: 0.50)
    static let tertiaryText = Color(red: 0.48, green: 0.56, blue: 0.64)
    static let accent = Color(red: 0.08, green: 0.72, blue: 0.65)
    static let accentSoft = Color(red: 0.84, green: 0.97, blue: 0.95)
    static let warmAccent = Color(red: 0.96, green: 0.49, blue: 0.12)
    static let warmSoft = Color(red: 1.0, green: 0.94, blue: 0.88)
    static let success = Color(red: 0.20, green: 0.71, blue: 0.43)
    static let successSoft = Color(red: 0.89, green: 0.97, blue: 0.92)
    static let danger = Color(red: 0.85, green: 0.33, blue: 0.32)
    static let dangerSoft = Color(red: 0.98, green: 0.91, blue: 0.90)
    static let shadow = Color(red: 0.25, green: 0.37, blue: 0.50).opacity(0.12)
    static let accentForeground = Color.white
    static let warmForeground = Color.white

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
                    StudioTheme.background,
                    Color.white,
                    StudioTheme.backgroundTint,
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
                .stroke(StudioTheme.border.opacity(0.24), lineWidth: 0.5)
            }

            Circle()
                .fill(StudioTheme.accentSoft.opacity(0.9))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: 320, y: -240)

            Circle()
                .fill(StudioTheme.warmSoft.opacity(0.92))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -420, y: 260)

            RoundedRectangle(cornerRadius: 80, style: .continuous)
                .fill(Color.white.opacity(0.28))
                .frame(width: 580, height: 340)
                .blur(radius: 50)
                .offset(x: -220, y: -160)
        }
        .ignoresSafeArea()
    }
}

struct StudioPanelModifier: ViewModifier {
    let fill: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
            .shadow(color: StudioTheme.shadow, radius: 22, x: 0, y: 16)
    }
}

extension View {
    func studioPanel(fill: Color = StudioTheme.panel, radius: CGFloat = 24) -> some View {
        modifier(StudioPanelModifier(fill: fill, radius: radius))
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
                .font(.custom("Avenir Next", size: 26))
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
                .fill(color.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.24), lineWidth: 1)
        )
    }
}

struct ActionButtonStyle: ButtonStyle {
    let fill: Color
    let foreground: Color
    var stroke: Color = StudioTheme.border

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
                    .stroke(stroke, lineWidth: 1)
            )
            .shadow(color: StudioTheme.shadow.opacity(configuration.isPressed ? 0.08 : 0.18), radius: 12, x: 0, y: 8)
    }
}
