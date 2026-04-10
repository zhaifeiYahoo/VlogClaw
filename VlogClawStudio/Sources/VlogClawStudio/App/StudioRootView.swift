import Observation
import SwiftUI

struct StudioRootView: View {
    @Bindable var model: StudioModel

    var body: some View {
        ZStack {
            StudioBackdrop()

            HStack(spacing: 18) {
                StudioSidebarView(model: model)
                contentView
            }
            .padding(20)
        }
        .overlay(alignment: .top) {
            if let error = model.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .lineLimit(2)
                    Spacer()
                    Button("Dismiss") {
                        model.clearError()
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.primaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(StudioTheme.warmSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(StudioTheme.warmAccent.opacity(0.28), lineWidth: 1)
                )
                .padding(.top, 16)
                .padding(.horizontal, 24)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(model.bannerText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(StudioTheme.secondaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(StudioTheme.panel.opacity(0.88))
                )
                .overlay(
                    Capsule()
                        .stroke(StudioTheme.border, lineWidth: 1)
                )
                .padding(24)
        }
        .task {
            model.start()
        }
        .onDisappear {
            model.stop()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch model.selectedSection {
        case .dashboard:
            DashboardView(model: model)
        case .workflow:
            WorkflowWorkspaceView(model: model)
        }
    }
}
