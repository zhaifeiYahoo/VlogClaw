import Observation
import SwiftUI

struct DashboardView: View {
    @Bindable var model: StudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            dashboardHeader
            metricsRow

            HSplitView {
                DeviceRailView(model: model)
                DashboardOverviewBoard(model: model)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dashboardHeader: some View {
        HStack(alignment: .top, spacing: 20) {
            SectionHeader(
                eyebrow: "Dashboard",
                title: "Studio Control Center",
                subtitle: "把连接真机的所有动作留在这里，Workflow 页面只保留实时预览和发小红书。"
            )

            Spacer()

            Button {
                if model.canOpenWorkflow {
                    model.openSection(.workflow)
                } else {
                    Task { await model.refreshAll(showSpinner: true) }
                }
            } label: {
                Label(model.canOpenWorkflow ? "Jump To Workflow" : "Refresh Devices", systemImage: model.canOpenWorkflow ? "arrow.right.circle.fill" : "arrow.clockwise")
                    .padding(.horizontal, 2)
            }
            .buttonStyle(
                ActionButtonStyle(
                    fill: model.canOpenWorkflow ? StudioTheme.accent : StudioTheme.panelRaised,
                    foreground: model.canOpenWorkflow ? StudioTheme.accentForeground : StudioTheme.primaryText,
                    stroke: model.canOpenWorkflow ? StudioTheme.accent.opacity(0.18) : StudioTheme.border
                )
            )
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 14) {
            DashboardMetricCard(
                title: "Backend",
                value: model.backendState.label,
                detail: "Port \(model.backendPort)",
                tint: StudioTheme.backendColor(model.backendState)
            )
            DashboardMetricCard(
                title: "Connected Devices",
                value: "\(model.connectedDevices.count)",
                detail: "\(model.devices.count) discovered total",
                tint: StudioTheme.success
            )
            DashboardMetricCard(
                title: "Workflow Queue",
                value: "\(model.selectedDeviceTasks.count)",
                detail: model.selectedDevice?.deviceName ?? "No selected device",
                tint: StudioTheme.warmAccent
            )
        }
    }
}

private struct DashboardOverviewBoard: View {
    @Bindable var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                readinessCard
                journeyCard
                latestActivityCard
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .studioPanel()
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Workflow Readiness")
                .font(.custom("Avenir Next", size: 20))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)

            if let device = model.workflowReadyDevice {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(device.displayName)
                            .font(.custom("Avenir Next", size: 18))
                            .fontWeight(.semibold)
                            .foregroundStyle(StudioTheme.primaryText)
                        Text("WDA 与 MJPEG 已就绪后，Workflow 页面会直接进入实时预览和任务投递。")
                            .font(.custom("Avenir Next", size: 13))
                            .foregroundStyle(StudioTheme.secondaryText)
                    }

                    Spacer()
                    StatusBadge(text: device.status.label, color: StudioTheme.statusColor(device.status))
                }

                Button {
                    model.openSection(.workflow)
                } label: {
                    Label("Open Workflow", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    ActionButtonStyle(
                        fill: StudioTheme.accent,
                        foreground: StudioTheme.accentForeground,
                        stroke: StudioTheme.accent.opacity(0.18)
                    )
                )
            } else {
                Text("还没有已连接的 iPhone。先在 Phone Rail 里启动 backend、确认 WDA 配置，再直接刷新、选择并连接设备。")
                    .font(.custom("Avenir Next", size: 13))
                    .foregroundStyle(StudioTheme.secondaryText)

                HStack(spacing: 12) {
                    readinessTag(title: "Backend", value: model.backendState.label)
                    readinessTag(title: "Phone Rail", value: model.devices.isEmpty ? "Empty" : "Ready")
                    readinessTag(title: "Workflow", value: "Locked")
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(StudioTheme.accentSoft.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(StudioTheme.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var journeyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connection Journey")
                .font(.custom("Avenir Next", size: 20))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)

            DashboardStepRow(
                index: "01",
                title: "Launch backend",
                detail: "在 Phone Rail 顶部确认 backend 运行，再决定是否保持 auto launch。",
                isComplete: model.backendState == .running
            )
            DashboardStepRow(
                index: "02",
                title: "Discover phones",
                detail: "触发 Rescan Devices，让 Studio 拉取当前真机和 WDA 状态。",
                isComplete: !model.devices.isEmpty
            )
            DashboardStepRow(
                index: "03",
                title: "Connect one iPhone",
                detail: "连接成功后会自动切到 Workflow 页面。",
                isComplete: model.canOpenWorkflow
            )
            DashboardStepRow(
                index: "04",
                title: "Preview and publish",
                detail: "在 Workflow 里看实时画面、生成文案、发起小红书任务。",
                isComplete: model.selectedSection == .workflow && model.canOpenWorkflow
            )
        }
        .padding(20)
        .studioPanel(fill: Color.white.opacity(0.72), radius: 24)
    }

    private var latestActivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Latest Activity")
                    .font(.custom("Avenir Next", size: 20))
                    .fontWeight(.semibold)
                    .foregroundStyle(StudioTheme.primaryText)
                Spacer()
                Text(model.bannerText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(StudioTheme.secondaryText)
            }

            if let latestTask = model.latestTask {
                Text(latestTask.title ?? "Untitled workflow")
                    .font(.custom("Avenir Next", size: 17))
                    .fontWeight(.semibold)
                    .foregroundStyle(StudioTheme.primaryText)
                Text(latestTask.body ?? latestTask.instruction)
                    .font(.custom("Avenir Next", size: 13))
                    .foregroundStyle(StudioTheme.secondaryText)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    StatusBadge(text: latestTask.status.label, color: StudioTheme.taskColor(latestTask.status))
                    Text("Updated \(latestTask.updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(StudioTheme.secondaryText)
                }
            } else {
                Text("当前还没有 workflow 任务。连接好设备后，去 Workflow 页面生成文案并直接发起投递。")
                    .font(.custom("Avenir Next", size: 13))
                    .foregroundStyle(StudioTheme.secondaryText)
            }
        }
        .padding(20)
        .studioPanel(fill: Color.white.opacity(0.72), radius: 24)
    }

    private func readinessTag(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.tertiaryText)
            Text(value)
                .font(.custom("Avenir Next", size: 14))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StudioTheme.tertiaryText)
            }

            Text(value)
                .font(.custom("Avenir Next", size: 28))
                .fontWeight(.bold)
                .foregroundStyle(StudioTheme.primaryText)

            Text(detail)
                .font(.custom("Avenir Next", size: 12))
                .foregroundStyle(StudioTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .studioPanel(fill: Color.white.opacity(0.76), radius: 22)
    }
}

private struct DashboardStepRow: View {
    let index: String
    let title: String
    let detail: String
    let isComplete: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isComplete ? StudioTheme.successSoft : StudioTheme.panelStrong)
                    .frame(width: 38, height: 38)
                Text(index)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isComplete ? StudioTheme.success : StudioTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Avenir Next", size: 16))
                    .fontWeight(.semibold)
                    .foregroundStyle(StudioTheme.primaryText)
                Text(detail)
                    .font(.custom("Avenir Next", size: 13))
                    .foregroundStyle(StudioTheme.secondaryText)
            }

            Spacer()

            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isComplete ? StudioTheme.success : StudioTheme.tertiaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(StudioTheme.panelRaised)
        )
    }
}
