import Foundation

enum StudioSection: String, CaseIterable, Identifiable {
    case dashboard
    case workflow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .workflow:
            return "Workflow"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard:
            return "Connect phones"
        case .workflow:
            return "Preview + publish"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:
            return "square.grid.2x2.fill"
        case .workflow:
            return "point.3.connected.trianglepath.dotted"
        }
    }
}

enum BackendRuntimeState: String, Sendable {
    case idle
    case launching
    case running
    case failed
    case stopped

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .launching:
            return "Launching"
        case .running:
            return "Running"
        case .failed:
            return "Failed"
        case .stopped:
            return "Stopped"
        }
    }
}

struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: String?
}

struct BasicEnvelope: Decodable {
    let success: Bool
    let error: String?
}

enum DeviceConnectionState: String, Codable, CaseIterable {
    case disconnected
    case connecting
    case connected
    case error

    var label: String {
        switch self {
        case .disconnected:
            return "Offline"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Live"
        case .error:
            return "Blocked"
        }
    }
}

struct StudioDevice: Decodable, Identifiable, Hashable {
    let udid: String
    let deviceName: String
    let generationName: String?
    let productVersion: String?
    let productType: String?
    let status: DeviceConnectionState
    let wdaURL: String?
    let mjpegPort: Int?
    let mjpegURL: String?
    let lastError: String?
    let updatedAt: Date?

    var id: String { udid }

    var displayName: String {
        generationName.flatMap { !$0.isEmpty ? "\(deviceName) \($0)" : nil } ?? deviceName
    }

    var compactVersion: String {
        productVersion.map { "iOS \($0)" } ?? "iOS"
    }

    var shortUDID: String {
        if udid.count <= 8 {
            return udid
        }
        return "\(udid.prefix(4))…\(udid.suffix(4))"
    }
}

enum WorkflowPublishMode: String, CaseIterable, Identifiable {
    case draft
    case publish

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft:
            return "Draft"
        case .publish:
            return "Publish"
        }
    }
}

enum AutomationModel: String, CaseIterable, Identifiable {
    case openai
    case claude

    var id: String { rawValue }
}

enum StudioTaskStatus: String, Decodable {
    case pending
    case running
    case completed
    case failed
    case cancelled

    var label: String { rawValue.capitalized }
}

struct StudioAction: Decodable, Hashable {
    let type: String
}

struct StudioTaskStep: Decodable, Hashable {
    let index: Int
    let analysis: String
    let actions: [StudioAction]
    let timestamp: Date
}

struct StudioTask: Decodable, Identifiable, Hashable {
    let id: String
    let instruction: String
    let deviceUDID: String
    let bundleID: String
    let workflow: String?
    let model: String
    let maxSteps: Int
    let title: String?
    let body: String?
    let imageCount: Int?
    let imageSelectionHint: String?
    let publishMode: String?
    let status: StudioTaskStatus
    let steps: [StudioTaskStep]
    let error: String?
    let createdAt: Date
    let updatedAt: Date
}

struct XiaohongshuCopyRequest: Encodable {
    let description: String
    let tone: String
    let audience: String
    let imageDataURLs: [String]

    enum CodingKeys: String, CodingKey {
        case description
        case tone
        case audience
        case imageDataURLs = "image_data_urls"
    }
}

struct XiaohongshuCopyResponse: Decodable {
    let title: String
    let body: String
    let hashtags: [String]
    let imageSelectionHint: String?

    enum CodingKeys: String, CodingKey {
        case title
        case body
        case hashtags
        case imageSelectionHint = "image_selection_hint"
    }
}

struct XiaohongshuWorkflowRequest: Encodable {
    let model: String
    let instruction: String
    let deviceUDID: String
    let title: String
    let body: String
    let imageCount: Int
    let imageSelectionHint: String
    let publishMode: String
    let maxSteps: Int

    enum CodingKeys: String, CodingKey {
        case model
        case instruction
        case deviceUDID = "device_udid"
        case title
        case body
        case imageCount = "image_count"
        case imageSelectionHint = "image_selection_hint"
        case publishMode = "publish_mode"
        case maxSteps = "max_steps"
    }
}

struct ConversationMessage: Identifiable, Hashable {
    enum Role: String, Hashable {
        case assistant
        case user
    }

    let id: UUID
    let role: Role
    let title: String
    let body: String
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, title: String, body: String, timestamp: Date = .now) {
        self.id = id
        self.role = role
        self.title = title
        self.body = body
        self.timestamp = timestamp
    }
}

struct DraftReferenceImage: Identifiable, Hashable {
    let id: UUID
    let fileURL: URL
    let fileName: String
    let data: Data

    init(fileURL: URL, data: Data) {
        self.id = UUID()
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
        self.data = data
    }

    var dataURL: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private var mimeType: String {
        switch fileURL.pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "heic", "heif":
            return "image/heic"
        case "webp":
            return "image/webp"
        default:
            return "image/jpeg"
        }
    }
}

struct XiaohongshuDraft: Hashable {
    var description = ""
    var tone = "真实、克制、有生活感"
    var audience = "18-35 岁关注效率与审美的人群"
    var title = ""
    var body = ""
    var hashtagsText = ""
    var imageSelectionHint = "选择最近添加、主体清晰的图片"
    var imageCount = 3
    var publishMode: WorkflowPublishMode = .draft
    var automationModel: AutomationModel = .openai
    var referenceImages: [DraftReferenceImage] = []
}
