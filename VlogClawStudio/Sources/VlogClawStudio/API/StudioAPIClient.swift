import Foundation

enum StudioAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case emptyResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Backend URL 无效。"
        case .invalidResponse:
            return "后端返回了无法识别的响应。"
        case .emptyResponse:
            return "后端没有返回数据。"
        case .server(let message):
            return message
        }
    }
}

struct StudioAPIClient {
    private let baseURL: URL
    private let session: URLSession

    private struct HealthResponse: Decodable {
        let status: String
    }

    init(baseURLString: String, session: URLSession = .shared) throws {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw StudioAPIError.invalidBaseURL
        }
        self.baseURL = url
        self.session = session
    }

    func listDevices() async throws -> [StudioDevice] {
        let data = try await performRequest(path: "/api/v1/devices", method: "GET")
        return try decodeEnvelope([StudioDevice].self, from: data)
    }

    func getDevice(udid: String) async throws -> StudioDevice {
        let data = try await performRequest(path: "/api/v1/devices/\(udid)", method: "GET")
        return try decodeEnvelope(StudioDevice.self, from: data)
    }

    func connectDevice(udid: String) async throws {
        _ = try await performRequest(path: "/api/v1/devices/\(udid)/connect", method: "POST")
    }

    func disconnectDevice(udid: String) async throws {
        _ = try await performRequest(path: "/api/v1/devices/\(udid)/connect", method: "DELETE")
    }

    func listTasks() async throws -> [StudioTask] {
        let data = try await performRequest(path: "/api/v1/tasks", method: "GET")
        return try decodeEnvelope([StudioTask].self, from: data)
    }

    func generateXiaohongshuCopy(_ request: XiaohongshuCopyRequest) async throws -> XiaohongshuCopyResponse {
        let body = try JSONEncoder().encode(request)
        let data = try await performRequest(path: "/api/v1/workflows/xiaohongshu/copy", method: "POST", body: body)
        return try decodeEnvelope(XiaohongshuCopyResponse.self, from: data)
    }

    func createXiaohongshuPost(_ request: XiaohongshuWorkflowRequest) async throws -> StudioTask {
        let body = try JSONEncoder().encode(request)
        let data = try await performRequest(path: "/api/v1/workflows/xiaohongshu/posts", method: "POST", body: body)
        return try decodeEnvelope(StudioTask.self, from: data)
    }

    func ensureHealthyBackend() async throws {
        let delays: [Duration] = [.milliseconds(150), .milliseconds(250), .milliseconds(350), .milliseconds(500), .milliseconds(750)]
        var lastError: Error?

        for (index, delay) in delays.enumerated() {
            do {
                try await ensureHealthyBackendOnce()
                return
            } catch {
                lastError = error
                guard isRetryableHealthError(error), index < delays.count - 1 else {
                    throw error
                }
                try? await Task.sleep(for: delay)
            }
        }
        throw lastError ?? StudioAPIError.server("VlogClaw backend 健康检查失败。")
    }

    private func ensureHealthyBackendOnce() async throws {
        var request = URLRequest(url: baseURL.appending(path: "/health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StudioAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw StudioAPIError.server("当前 Backend URL 指向的服务不是 VlogClaw backend，`/health` 返回了 404。")
            }
            throw StudioAPIError.server("VlogClaw backend 健康检查失败，HTTP \(httpResponse.statusCode)")
        }
        let health = try JSONDecoder().decode(HealthResponse.self, from: data)
        guard health.status == "ok" else {
            throw StudioAPIError.server("VlogClaw backend 健康检查返回了异常状态。")
        }
    }

    private func isRetryableHealthError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [
                .cannotFindHost,
                .cannotConnectToHost,
                .networkConnectionLost,
                .timedOut,
            ].contains(urlError.code)
        }
        return false
    }

    private func performRequest(path: String, method: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 60
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StudioAPIError.invalidResponse
        }
        if (200 ..< 300).contains(httpResponse.statusCode) {
            return data
        }
        if let message = try? decodeBasicError(from: data) {
            throw StudioAPIError.server(message)
        }
        throw StudioAPIError.server("请求失败，HTTP \(httpResponse.statusCode)")
    }

    private func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        if !envelope.success {
            throw StudioAPIError.server(envelope.error ?? "请求失败")
        }
        guard let payload = envelope.data else {
            throw StudioAPIError.emptyResponse
        }
        return payload
    }

    private func decodeBasicError(from data: Data) throws -> String {
        let envelope = try decoder.decode(BasicEnvelope.self, from: data)
        return envelope.error ?? "请求失败"
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let basic = ISO8601DateFormatter()
            basic.formatOptions = [.withInternetDateTime]
            if let date = fractional.date(from: string) ?? basic.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date: \(string)")
        }
        return decoder
    }
}
