import Observation
import SwiftUI

struct StudioSidebarView: View {
    @Bindable var model: StudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            brandHeader
            navigationSection
            studioStatusSection
            Spacer(minLength: 12)
            footerCard
        }
        .padding(20)
        .frame(minWidth: 248, idealWidth: 248, maxWidth: 248, maxHeight: .infinity, alignment: .topLeading)
        .studioPanel(fill: StudioTheme.sidebarPanel, radius: 28)
    }

    private var brandHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [StudioTheme.accent, Color(red: 0.25, green: 0.53, blue: 0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("VlogClaw Studio")
                    .font(.custom("Avenir Next", size: 22))
                    .fontWeight(.bold)
                    .foregroundStyle(StudioTheme.primaryText)
                Text("Bright control surface for device ops and publishing workflows.")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundStyle(StudioTheme.secondaryText)
            }
        }
    }

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workspace")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.tertiaryText)
                .tracking(1.0)

            ForEach(StudioSection.allCases) { section in
                Button {
                    model.openSection(section)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(model.selectedSection == section ? StudioTheme.accent : StudioTheme.secondaryText)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.custom("Avenir Next", size: 15))
                                .fontWeight(.semibold)
                                .foregroundStyle(StudioTheme.primaryText)
                            Text(section.subtitle)
                                .font(.custom("Avenir Next", size: 11))
                                .foregroundStyle(StudioTheme.secondaryText)
                        }

                        Spacer()

                        if section == .workflow, model.canOpenWorkflow {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(StudioTheme.success)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(model.selectedSection == section ? StudioTheme.accentSoft : Color.white.opacity(0.58))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(model.selectedSection == section ? StudioTheme.accent.opacity(0.22) : StudioTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var studioStatusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Studio Status")
                .font(.custom("Avenir Next", size: 17))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)

            sidebarMetric(title: "Backend", value: model.backendState.label, tint: StudioTheme.backendColor(model.backendState))
            sidebarMetric(title: "Connected", value: "\(model.connectedDevices.count) iPhone", tint: StudioTheme.success)
            sidebarMetric(title: "Selected", value: model.selectedDevice?.deviceName ?? "No device", tint: StudioTheme.accent)

            Button {
                if model.canOpenWorkflow {
                    model.openSection(.workflow)
                } else {
                    Task { await model.refreshAll(showSpinner: true) }
                }
            } label: {
                Label(model.canOpenWorkflow ? "Open Workflow" : "Refresh Studio", systemImage: model.canOpenWorkflow ? "arrow.right.circle.fill" : "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                ActionButtonStyle(
                    fill: model.canOpenWorkflow ? StudioTheme.accent : StudioTheme.panelRaised,
                    foreground: model.canOpenWorkflow ? StudioTheme.accentForeground : StudioTheme.primaryText,
                    stroke: model.canOpenWorkflow ? StudioTheme.accent.opacity(0.18) : StudioTheme.border
                )
            )
        }
        .padding(16)
        .studioPanel(fill: Color.white.opacity(0.7), radius: 24)
    }

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flow")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.tertiaryText)
                .tracking(1.0)
            Text("Dashboard now keeps all backend, WDA, and device connection controls inside one Phone Rail. Workflow stays focused on preview and Xiaohongshu delivery.")
                .font(.custom("Avenir Next", size: 12))
                .foregroundStyle(StudioTheme.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private func sidebarMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.tertiaryText)
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(value)
                    .font(.custom("Avenir Next", size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(StudioTheme.primaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(StudioTheme.panelRaised)
        )
    }
}
