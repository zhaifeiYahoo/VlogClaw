import Observation
import SwiftUI

struct WorkflowWorkspaceView: View {
    @Bindable var model: StudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            workflowHeader

            HSplitView {
                DevicePreviewBoard(model: model)
                AssistantPanelView(model: model)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var workflowHeader: some View {
        HStack(alignment: .top, spacing: 20) {
            SectionHeader(
                eyebrow: "Workflow",
                title: "Live Preview + Xiaohongshu",
                subtitle: "这里专注于看实时画面、生成文案和把结果投递到真机自动化流程。"
            )

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                if let device = model.workflowReadyDevice {
                    StatusBadge(text: device.status.label, color: StudioTheme.statusColor(device.status))
                    Text("Active iPhone: \(device.deviceName)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(StudioTheme.secondaryText)
                } else {
                    Text("Connect an iPhone in Dashboard to unlock the live preview.")
                        .font(.custom("Avenir Next", size: 12))
                        .foregroundStyle(StudioTheme.secondaryText)
                        .multilineTextAlignment(.trailing)
                }

                Button {
                    model.openSection(.dashboard)
                } label: {
                    Label("Back To Dashboard", systemImage: "sidebar.left")
                }
                .buttonStyle(ActionButtonStyle(fill: StudioTheme.panelRaised, foreground: StudioTheme.primaryText, stroke: StudioTheme.border))
            }
        }
    }
}
