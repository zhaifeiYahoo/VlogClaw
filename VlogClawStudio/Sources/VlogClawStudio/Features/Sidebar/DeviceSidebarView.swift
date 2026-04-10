import Observation
import SwiftUI

struct DeviceSidebarView: View {
    @Bindable var model: StudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(
                eyebrow: "Control Plane",
                title: "Connected Phones",
                subtitle: "Sonic bridge discovery, WDA session state, and the live MJPEG endpoint all surface here."
            )

            backendSection

            VStack(alignment: .leading, spacing: 10) {
                Text("Backend URL")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StudioTheme.secondaryText)

                TextField("http://127.0.0.1:8080", text: $model.serverURL)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(StudioTheme.panelRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: 1)
                    )
                    .foregroundStyle(StudioTheme.primaryText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))

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
                .foregroundStyle(Color.black)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(StudioTheme.accent)
                )
            }

            ScrollView {
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
                            Text("确认 `sib devices -d` 能看到真机，再回到这里触发刷新。")
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
        }
        .padding(24)
        .frame(minWidth: 320, idealWidth: 340, maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)
        .studioPanel()
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

            Toggle(isOn: $model.backendAutoStart) {
                Text("Auto launch on startup")
                    .font(.custom("Avenir Next", size: 12))
                    .foregroundStyle(StudioTheme.secondaryText)
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 8) {
                Text("Backend Binary")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StudioTheme.secondaryText)

                TextField("/path/to/backend/bin/vlogclaw", text: $model.backendBinaryPath)
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
                        model.applyBackendPath()
                    }
            }

            HStack(spacing: 12) {
                Button {
                    model.applyBackendPath()
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
                        .fill(Color.black.opacity(0.22))
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
                .fill(StudioTheme.panelRaised.opacity(0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
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
}

private struct DeviceRow: View {
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
                .fill(isSelected ? StudioTheme.panelRaised : StudioTheme.panel.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? StudioTheme.accent.opacity(0.6) : StudioTheme.border, lineWidth: 1)
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
            return StudioTheme.danger.opacity(0.18)
        case .connecting:
            return StudioTheme.warmAccent.opacity(0.2)
        case .disconnected, .error:
            return StudioTheme.accent
        }
    }

    private var buttonTextColor: Color {
        switch device.status {
        case .connected, .connecting:
            return StudioTheme.primaryText
        case .disconnected, .error:
            return .black
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
