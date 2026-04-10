import Observation
import SwiftUI

struct StudioRootView: View {
    @Bindable var model: StudioModel

    var body: some View {
        ZStack {
            StudioBackdrop()

            HSplitView {
                DeviceSidebarView(model: model)
                DevicePreviewBoard(model: model)
                AssistantPanelView(model: model)
            }
            .padding(22)
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
                .foregroundStyle(Color.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(StudioTheme.warmAccent)
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
}
