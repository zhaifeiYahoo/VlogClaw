import Foundation
import Observation

@MainActor
@Observable
final class StudioModel {
    private static let wdaProjectPathDefaultsKey = "studio.wdaProjectPath"
    private static let wdaBundleIDDefaultsKey = "studio.wdaBundleID"

    var selectedSection: StudioSection = .dashboard
    var serverURL = "http://127.0.0.1:8080"
    var backendState: BackendRuntimeState = .idle
    var wdaProjectPath = ""
    var wdaBundleID = "com.vlogclaw.WebDriverAgentRunner"
    var backendPort = 8080
    var backendLogTail = ""
    var backendPID: Int32?
    var backendAutoStart = true
    var devices: [StudioDevice] = []
    var selectedDeviceID: String?
    var tasks: [StudioTask] = []
    var draft = XiaohongshuDraft()
    var conversation: [ConversationMessage] = [
        ConversationMessage(
            role: .assistant,
            title: "Studio Ready",
            body: "连接真机后，右侧可以先根据描述和参考图生成小红书文案，再把结果投递到设备上的自动化发布流程。"
        ),
    ]
    var lastError: String?
    var bannerText = "Backend + WDA + MJPEG"
    var isRefreshing = false
    var isGeneratingCopy = false
    var isSubmittingWorkflow = false

    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private let backendController = BackendProcessController()
    @ObservationIgnored private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.wdaProjectPath = userDefaults.string(forKey: Self.wdaProjectPathDefaultsKey) ?? ""
        self.wdaBundleID = userDefaults.string(forKey: Self.wdaBundleIDDefaultsKey) ?? "com.vlogclaw.WebDriverAgentRunner"
    }

    var selectedDevice: StudioDevice? {
        devices.first(where: { $0.id == selectedDeviceID })
    }

    var connectedDevices: [StudioDevice] {
        devices.filter { $0.status == .connected }
    }

    var workflowReadyDevice: StudioDevice? {
        if let selectedDevice, selectedDevice.status == .connected {
            return selectedDevice
        }
        return connectedDevices.first
    }

    var selectedDeviceTasks: [StudioTask] {
        let filtered = tasks.filter { $0.deviceUDID == selectedDeviceID }
        return filtered.sorted { $0.updatedAt > $1.updatedAt }
    }

    var latestTask: StudioTask? {
        selectedDeviceTasks.first
    }

    var canGenerateCopy: Bool {
        !draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.referenceImages.isEmpty
    }

    var canSubmitWorkflow: Bool {
        selectedDevice?.status == .connected && !draft.title.isEmpty && !draft.body.isEmpty
    }

    var canOpenWorkflow: Bool {
        workflowReadyDevice != nil
    }

    func start() {
        guard pollingTask == nil else { return }
        syncBackendSnapshot(backendController.snapshot)
        if backendAutoStart {
            backendController.startIfPossible { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.syncBackendSnapshot(snapshot)
                }
            }
        }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshAll(showSpinner: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self.refreshAll(showSpinner: false)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        backendController.stop { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.syncBackendSnapshot(snapshot)
            }
        }
    }

    func refreshAll(showSpinner: Bool) async {
        if showSpinner {
            isRefreshing = true
        }
        defer {
            if showSpinner {
                isRefreshing = false
            }
        }

        do {
            let client = try apiClient()
            try await client.ensureHealthyBackend()
            async let deviceResponse = client.listDevices()
            async let taskResponse = client.listTasks()
            let (fetchedDevices, fetchedTasks) = try await (deviceResponse, taskResponse)
            devices = fetchedDevices
            tasks = fetchedTasks
            reconcileSelection()
            lastError = nil
            bannerText = "Backend synced \(Date.now.formatted(date: .omitted, time: .standard))"
        } catch {
            present(error)
        }
    }

    func connect(_ device: StudioDevice) async {
        do {
            selectedDeviceID = device.id
            let client = try apiClient()
            let resolvedWDAProjectPath = applyWDAProjectPath()
            let resolvedWDABundleID = applyWDABundleID()
            try await client.connectDevice(
                udid: device.udid,
                wdaProjectPath: resolvedWDAProjectPath.isEmpty ? nil : resolvedWDAProjectPath,
                wdaBundleID: resolvedWDABundleID.isEmpty ? nil : resolvedWDABundleID
            )
            await refreshAll(showSpinner: false)
            if selectedDevice?.status == .connected {
                bannerText = "\(device.deviceName) connected. Workflow ready."
                openSection(.workflow)
            } else {
                bannerText = "Connecting \(device.deviceName)"
            }
        } catch {
            present(error)
        }
    }

    func disconnect(_ device: StudioDevice) async {
        do {
            let client = try apiClient()
            try await client.disconnectDevice(udid: device.udid)
            await refreshAll(showSpinner: false)
            bannerText = "Disconnected \(device.deviceName)"
        } catch {
            present(error)
        }
    }

    func openSection(_ section: StudioSection) {
        if section == .workflow, let workflowReadyDevice {
            selectedDeviceID = workflowReadyDevice.id
        }
        selectedSection = section
    }

    func generateCopy() async {
        guard canGenerateCopy else {
            lastError = "先输入描述，或附上一组参考图片。"
            return
        }

        isGeneratingCopy = true
        defer { isGeneratingCopy = false }

        let promptBody = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        appendMessage(
            role: .user,
            title: "Generate Xiaohongshu Copy",
            body: buildUserPromptSummary(description: promptBody)
        )

        do {
            let client = try apiClient()
            let response = try await client.generateXiaohongshuCopy(
                XiaohongshuCopyRequest(
                    description: promptBody,
                    tone: draft.tone,
                    audience: draft.audience,
                    imageDataURLs: draft.referenceImages.map(\.dataURL)
                )
            )

            draft.title = response.title
            draft.body = response.body
            draft.hashtagsText = response.hashtags.joined(separator: " ")
            draft.imageSelectionHint = response.imageSelectionHint ?? draft.imageSelectionHint
            if !draft.referenceImages.isEmpty {
                draft.imageCount = draft.referenceImages.count
            }

            appendMessage(
                role: .assistant,
                title: response.title,
                body: "\(response.body)\n\n\(response.hashtags.joined(separator: " "))"
            )
            bannerText = "Copy generated for Xiaohongshu"
        } catch {
            present(error)
        }
    }

    func submitWorkflow() async {
        guard let device = selectedDevice, device.status == .connected else {
            lastError = "先连接一台 iPhone 真机。"
            return
        }

        isSubmittingWorkflow = true
        defer { isSubmittingWorkflow = false }

        do {
            let client = try apiClient()
            let task = try await client.createXiaohongshuPost(
                XiaohongshuWorkflowRequest(
                    model: draft.automationModel.rawValue,
                    instruction: draft.description,
                    deviceUDID: device.udid,
                    title: draft.title,
                    body: composePublishBody(),
                    imageCount: max(draft.imageCount, 1),
                    imageSelectionHint: draft.imageSelectionHint,
                    publishMode: draft.publishMode.rawValue,
                    maxSteps: 60
                )
            )

            tasks.insert(task, at: 0)
            bannerText = "Workflow queued for \(device.deviceName)"
            appendMessage(
                role: .assistant,
                title: "Task queued",
                body: "已将图文任务推送到 \(device.deviceName)。当前模式：\(draft.publishMode.label)，执行模型：\(draft.automationModel.rawValue)。"
            )
        } catch {
            present(error)
        }
    }

    func importImages(from urls: [URL]) {
        let loaded = urls.compactMap { url -> DraftReferenceImage? in
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return DraftReferenceImage(fileURL: url, data: data)
        }

        draft.referenceImages.append(contentsOf: loaded)
        if !loaded.isEmpty {
            draft.imageCount = draft.referenceImages.count
            bannerText = "Attached \(draft.referenceImages.count) reference image(s)"
        }
    }

    func removeImage(_ image: DraftReferenceImage) {
        draft.referenceImages.removeAll { $0.id == image.id }
        draft.imageCount = max(draft.referenceImages.count, 1)
    }

    func clearError() {
        lastError = nil
    }

    func launchBackend() {
        backendController.startIfPossible { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.syncBackendSnapshot(snapshot)
            }
        }
    }

    func stopBackend() {
        backendController.stop { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.syncBackendSnapshot(snapshot)
            }
        }
    }

    @discardableResult
    func applyWDAProjectPath() -> String {
        let normalized = wdaProjectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        wdaProjectPath = normalized
        userDefaults.set(normalized, forKey: Self.wdaProjectPathDefaultsKey)
        return normalized
    }

    @discardableResult
    func applyWDABundleID() -> String {
        let normalized = wdaBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        wdaBundleID = normalized
        userDefaults.set(normalized, forKey: Self.wdaBundleIDDefaultsKey)
        return normalized
    }

    private func reconcileSelection() {
        if let selectedDeviceID, devices.contains(where: { $0.id == selectedDeviceID }) {
            return
        }
        selectedDeviceID = connectedDevices.first?.id ?? devices.first?.id
    }

    private func apiClient() throws -> StudioAPIClient {
        try StudioAPIClient(baseURLString: serverURL)
    }

    private func appendMessage(role: ConversationMessage.Role, title: String, body: String) {
        conversation.append(ConversationMessage(role: role, title: title, body: body))
    }

    private func buildUserPromptSummary(description: String) -> String {
        let count = draft.referenceImages.count
        if count == 0 {
            return description
        }
        return "\(description)\n\n参考图：\(count) 张"
    }

    private func composePublishBody() -> String {
        let hashtags = draft.hashtagsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hashtags.isEmpty else {
            return draft.body
        }
        return "\(draft.body)\n\n\(hashtags)"
    }

    private func present(_ error: Error) {
        lastError = error.localizedDescription
        bannerText = "Action blocked"
    }

    private func syncBackendSnapshot(_ snapshot: BackendProcessController.Snapshot) {
        backendState = snapshot.state
        backendPort = snapshot.port
        backendLogTail = snapshot.logTail
        backendPID = snapshot.pid
        if let url = URL(string: "http://127.0.0.1:\(snapshot.port)") {
            serverURL = url.absoluteString
        }
        if snapshot.state == .running {
            bannerText = "Backend running on :\(snapshot.port)"
        }
        if let error = snapshot.lastError, !error.isEmpty {
            lastError = error
        }
    }
}
