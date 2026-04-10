import AppKit
import Observation
import SwiftUI

struct DeviceRailView: View {
    @Bindable var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    eyebrow: "Devices",
                    title: "Phone Rail",
                    subtitle: "把 backend 控制、WDA 配置、设备选择和连接动作合并到同一列，避免在两块面板之间来回切换。"
                )

                backendSection

                deviceOverviewSection

                if let selectedDevice = model.selectedDevice {
                    selectedDeviceSummary(for: selectedDevice)
                }

                LazyVStack(spacing: 14) {
                    ForEach(model.devices) { device in
                        DeviceRow(
                            device: device,
                            isSelected: model.selectedDeviceID == device.id,
                            onSelect: {
                                model.selectedDeviceID = device.id
                            },
                            onToggleConnection: {
                                Task {
                                    if device.status == .connected || device.status == .connecting {
                                        await model.disconnect(device)
                                    } else {
                                        await model.connect(device)
                                    }
                                }
                            }
                        )
                    }

                    if model.devices.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No device discovered")
                                .font(.custom("Avenir Next", size: 18))
                                .fontWeight(.semibold)
                                .foregroundStyle(StudioTheme.primaryText)
                            Text("确认 `sib devices -d` 能看到真机，再在这列里直接刷新、选择并连接设备。")
                                .font(.custom("Avenir Next", size: 13))
                                .foregroundStyle(StudioTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .studioPanel()
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(24)
        }
        .frame(minWidth: 380, idealWidth: 410, maxWidth: 440, maxHeight: .infinity, alignment: .topLeading)
        .studioPanel(fill: Color.white.opacity(0.84), radius: 24)
    }

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Managed Backend")
                    .font(.custom("Avenir Next", size: 17))
                    .fontWeight(.semibold)
                    .foregroundStyle(StudioTheme.primaryText)
                Spacer()
                StatusBadge(text: model.backendState.label, color: StudioTheme.backendColor(model.backendState))
            }

            Text("Desktop App 会直接启动内置的 backend，本地地址和 binary 路径不再需要手动配置。")
                .font(.custom("Avenir Next", size: 12))
                .foregroundStyle(StudioTheme.secondaryText)

            Toggle(isOn: $model.backendAutoStart) {
                Text("Auto launch on startup")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundStyle(StudioTheme.secondaryText)
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 8) {
                Text("WDA Project")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StudioTheme.secondaryText)

                Text("连接真机时，backend 会优先执行 `xcodebuild -project <该路径> -scheme WebDriverAgentRunner -destination id=<设备 UDID> test`。")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundStyle(StudioTheme.secondaryText)

                TextField("/path/to/WebDriverAgent.xcodeproj", text: $model.wdaProjectPath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(StudioTheme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(StudioTheme.panelRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: 1)
                    )
                    .onSubmit {
                        model.applyWDAProjectPath()
                    }

                HStack(spacing: 12) {
                    Button {
                        chooseWDAProject()
                    } label: {
                        Text("Choose…")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(fill: StudioTheme.panelRaised, foreground: StudioTheme.primaryText))

                    Button {
                        model.wdaProjectPath = ""
                        model.applyWDAProjectPath()
                    } label: {
                        Text("Clear")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(fill: StudioTheme.panelStrong, foreground: StudioTheme.secondaryText))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("WDA Bundle ID")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StudioTheme.secondaryText)

                Text("用于覆盖 backend 里的默认 Runner bundle id。未修改工程配置时，保持默认值即可。")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundStyle(StudioTheme.secondaryText)

                TextField("com.vlogclaw.WebDriverAgentRunner", text: $model.wdaBundleID)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(StudioTheme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(StudioTheme.panelRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: 1)
                    )
                    .onSubmit {
                        model.applyWDABundleID()
                    }
            }

            HStack(spacing: 12) {
                Button {
                    model.launchBackend()
                } label: {
                    Text("Launch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ActionButtonStyle(fill: StudioTheme.warmAccent, foreground: .black))

                Button {
                    model.stopBackend()
                } label: {
                    Text("Stop")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ActionButtonStyle(fill: StudioTheme.panelRaised, foreground: StudioTheme.primaryText))
            }

            HStack {
                sidebarKeyValue("PID", model.backendPID.map(String.init) ?? "n/a")
                Spacer()
                sidebarKeyValue("Port", "\(model.backendPort)")
            }

            if !model.backendLogTail.isEmpty {
                ScrollView {
                    Text(model.backendLogTail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(StudioTheme.secondaryText)
                        .textSelection(.enabled)
                }
                .frame(height: 96)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(StudioTheme.panelStrong)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var deviceOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rail Overview")
                .font(.custom("Avenir Next", size: 17))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)

            Text("这列现在同时承担配置、刷新、选机和连接职责。设备准备好后，Workflow 页面才解锁。")
                .font(.custom("Avenir Next", size: 12))
                .foregroundStyle(StudioTheme.secondaryText)

            HStack(spacing: 12) {
                compactStat(title: "Discovered", value: "\(model.devices.count)")
                compactStat(title: "Connected", value: "\(model.connectedDevices.count)")
                compactStat(title: "Selected", value: model.selectedDevice == nil ? "None" : "Ready")
            }

            Button {
                Task { await model.refreshAll(showSpinner: true) }
            } label: {
                HStack {
                    Text(model.isRefreshing ? "Refreshing…" : "Rescan Devices")
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(StudioTheme.accentForeground)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(StudioTheme.accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(StudioTheme.accent.opacity(0.16), lineWidth: 1)
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private func chooseWDAProject() {
        let panel = NSOpenPanel()
        panel.title = "Select WDA Project"
        panel.message = "选择 `.xcodeproj`，或包含 `.xcodeproj` 的工程目录。"
        panel.prompt = "Use Path"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        if !model.wdaProjectPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: model.wdaProjectPath)
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        model.wdaProjectPath = url.path
        model.applyWDAProjectPath()
    }

    private func selectedDeviceSummary(for device: StudioDevice) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Selected Device")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StudioTheme.tertiaryText)
                Text(device.displayName)
                    .font(.custom("Avenir Next", size: 16))
                    .fontWeight(.semibold)
                    .foregroundStyle(StudioTheme.primaryText)
                    .lineLimit(1)
                Text(device.productType ?? "Unknown hardware")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(StudioTheme.secondaryText)
            }

            Spacer()
            StatusBadge(text: device.status.label, color: StudioTheme.statusColor(device.status))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(StudioTheme.accentSoft.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StudioTheme.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func sidebarKeyValue(_ key: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.secondaryText)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(StudioTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func compactStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.tertiaryText)
            Text(value)
                .font(.custom("Avenir Next", size: 14))
                .fontWeight(.semibold)
                .foregroundStyle(StudioTheme.primaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(StudioTheme.panelRaised)
        )
    }
}

struct DeviceRow: View {
    let device: StudioDevice
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleConnection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(device.displayName)
                        .font(.custom("Avenir Next", size: 17))
                        .fontWeight(.semibold)
                        .foregroundStyle(StudioTheme.primaryText)
                    Text("\(device.compactVersion)  •  \(device.shortUDID)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(StudioTheme.secondaryText)
                }
                Spacer()
                StatusBadge(text: device.status.label, color: StudioTheme.statusColor(device.status))
            }

            VStack(alignment: .leading, spacing: 8) {
                keyValue("Product", device.productType ?? "Unknown")
                keyValue("WDA", device.wdaURL ?? "Pending")
                keyValue("MJPEG", device.mjpegURL ?? "Pending")
            }

            Button(action: onToggleConnection) {
                Text(buttonLabel)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(buttonTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(buttonBackground)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? StudioTheme.accentSoft : StudioTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? StudioTheme.accent.opacity(0.24) : StudioTheme.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var buttonLabel: String {
        switch device.status {
        case .connected:
            return "Disconnect"
        case .connecting:
            return "Stop Pending"
        case .disconnected, .error:
            return "Connect Device"
        }
    }

    private var buttonBackground: Color {
        switch device.status {
        case .connected:
            return StudioTheme.dangerSoft
        case .connecting:
            return StudioTheme.warmSoft
        case .disconnected, .error:
            return StudioTheme.accent
        }
    }

    private var buttonTextColor: Color {
        switch device.status {
        case .connected:
            return StudioTheme.danger
        case .connecting:
            return StudioTheme.warmAccent
        case .disconnected, .error:
            return StudioTheme.accentForeground
        }
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.secondaryText)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(StudioTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
