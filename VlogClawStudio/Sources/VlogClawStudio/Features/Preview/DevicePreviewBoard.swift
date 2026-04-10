import SwiftUI

struct DevicePreviewBoard: View {
    let model: StudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let device = model.selectedDevice {
                header(for: device)

                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(StudioTheme.panelStrong)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(StudioTheme.border, lineWidth: 1)
                        )

                    if let mjpeg = device.mjpegURL, device.status == .connected, let url = URL(string: mjpeg) {
                        MJPEGWebView(streamURL: url)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .padding(18)
                    } else {
                        previewPlaceholder(for: device)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                taskRail
            } else {
                emptySelection
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .studioPanel()
    }

    private func header(for device: StudioDevice) -> some View {
        HStack(alignment: .top) {
            SectionHeader(
                eyebrow: "Live View",
                title: device.displayName,
                subtitle: "WDA status, MJPEG preview, and workflow telemetry for the currently selected iPhone."
            )

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                StatusBadge(text: device.status.label, color: StudioTheme.statusColor(device.status))
                Text(device.productType ?? "Unknown hardware")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(StudioTheme.secondaryText)
            }
        }
    }

    private func previewPlaceholder(for device: StudioDevice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 42))
                .foregroundStyle(StudioTheme.accent)

            Text(device.status == .connected ? "MJPEG feed unavailable" : "Connect to start the live preview")
                .font(.custom("Avenir Next", size: 28))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)

            Text(device.status == .connected ? "后端已经建立了设备会话，但还没有拿到可用的 MJPEG 地址。" : "连接成功后，这里会直接通过 `WKWebView` 加载 WDA 的 MJPEG 流。")
                .font(.custom("Avenir Next", size: 14))
                .foregroundStyle(StudioTheme.secondaryText)

            VStack(alignment: .leading, spacing: 8) {
                streamRow(label: "WDA", value: device.wdaURL ?? "Pending")
                streamRow(label: "MJPEG", value: device.mjpegURL ?? "Pending")
                streamRow(label: "Last Error", value: device.lastError ?? "None")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(28)
    }

    private var taskRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Workflow Activity")
                    .font(.custom("Avenir Next", size: 18))
                    .fontWeight(.semibold)
                    .foregroundStyle(StudioTheme.primaryText)
                Spacer()
                Text("\(model.selectedDeviceTasks.count) task(s)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(StudioTheme.secondaryText)
            }

            if model.selectedDeviceTasks.isEmpty {
                Text("还没有和当前设备关联的任务。右侧生成完文案后，可以直接发送一个小红书图文任务到这里。")
                    .font(.custom("Avenir Next", size: 13))
                    .foregroundStyle(StudioTheme.secondaryText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(model.selectedDeviceTasks.prefix(6)) { task in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(task.workflow ?? "task")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(StudioTheme.secondaryText)
                                    Spacer()
                                    StatusBadge(text: task.status.label, color: StudioTheme.taskColor(task.status))
                                }

                                Text(task.title ?? "Untitled workflow")
                                    .font(.custom("Avenir Next", size: 16))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(StudioTheme.primaryText)
                                    .lineLimit(2)

                                Text(task.body ?? task.instruction)
                                    .font(.custom("Avenir Next", size: 12))
                                    .foregroundStyle(StudioTheme.secondaryText)
                                    .lineLimit(3)

                                HStack {
                                    Text("steps \(task.steps.count)/\(task.maxSteps)")
                                    Spacer()
                                    Text(task.updatedAt.formatted(date: .omitted, time: .shortened))
                                }
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(StudioTheme.secondaryText)
                            }
                            .padding(16)
                            .frame(width: 250, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.82))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(StudioTheme.border, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var emptySelection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                eyebrow: "Live View",
                title: "No iPhone Selected",
                subtitle: "先回 Dashboard 连接一台 iPhone，成功后这里会直接变成实时的 WDA MJPEG 监视画布。"
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func streamRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.secondaryText)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(StudioTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
