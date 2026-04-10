import Foundation

/// Swift/ObjC bridge for LLM and Agent functionality.
/// Exposed to ObjC via @objcMembers. Internally delegates to
/// MLXLocalLLMService (local), RemoteLLMService (cloud), and AutomationAgent.
@objcMembers
public class VCLLMBridge: NSObject {

    // MARK: - Singleton

    private static let _shared = VCLLMBridge()
    public static func shared() -> VCLLMBridge { _shared }

    // MARK: - State

    private var localLLM: MLXLocalLLMService?
    private var remoteService: RemoteLLMService?
    private var agent: AutomationAgent?

    public var isModelLoaded: Bool {
        return localLLM?.isLoaded ?? false
    }

    public var isRemoteConfigured: Bool {
        return remoteService != nil
    }

    // MARK: - Local LLM Management

    public func loadModel(_ modelID: String?, completion: @escaping (Bool, Error?) -> Void) {
        Task {
            do {
                let service = MLXLocalLLMService()
                let targetID = modelID ?? "gemma-4-e2b-it-4bit"
                try await service.load()
                self.localLLM = service
                self.agent = AutomationAgent(localLLM: service, remoteLLM: self.remoteService)
                completion(true, nil)
            } catch {
                completion(false, error)
            }
        }
    }

    public func unloadModel() {
        localLLM?.unload()
        localLLM = nil
    }

    public func modelStatus() -> [AnyHashable: Any] {
        var status: [String: Any] = [
            "localLoaded": isModelLoaded,
            "remoteConfigured": isRemoteConfigured
        ]
        if let llm = localLLM {
            status["modelId"] = llm.modelId
        }
        return status
    }

    // MARK: - Screenshot Analysis (Local LLM)

    public func analyzeScreenshot(
        _ screenshotBase64: String,
        goal: String,
        history historyJSON: String,
        completion: @escaping (String?, Error?) -> Void
    ) {
        guard let agent = agent else {
            completion(nil, NSError(
                domain: "VCLLMBridge",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Agent not initialized. Load model first."]
            ))
            return
        }
        Task {
            do {
                let history = try parseHistory(historyJSON)
                let result = try await agent.analyzeScreenshot(
                    base64: screenshotBase64,
                    goal: goal,
                    actionHistory: history
                )
                let json = try JSONEncoder().encode(result)
                completion(String(data: json, encoding: .utf8), nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    // MARK: - Remote LLM Configuration

    public func configureRemoteProvider(
        _ provider: String,
        apiKey: String,
        baseURL: String?,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        Task {
            do {
                let service = try RemoteLLMService(
                    provider: provider,
                    apiKey: apiKey,
                    baseURL: baseURL
                )
                self.remoteService = service
                if let llm = localLLM {
                    self.agent = AutomationAgent(localLLM: llm, remoteLLM: service)
                }
                completion(true, nil)
            } catch {
                completion(false, error)
            }
        }
    }

    // MARK: - Agent Operations

    public func executeAgentLoop(
        _ goal: String,
        maxSteps: Int,
        completion: @escaping (String?, Error?) -> Void
    ) {
        guard let agent = agent else {
            completion(nil, NSError(
                domain: "VCLLMBridge",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Agent not initialized. Load model first."]
            ))
            return
        }
        Task {
            do {
                let result = try await agent.executeLoop(goal: goal, maxSteps: maxSteps)
                let json = try JSONEncoder().encode(result)
                completion(String(data: json, encoding: .utf8), nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    public func agentStep(
        _ goal: String,
        history historyJSON: String,
        completion: @escaping (String?, Error?) -> Void
    ) {
        guard let agent = agent else {
            completion(nil, NSError(
                domain: "VCLLMBridge",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Agent not initialized."]
            ))
            return
        }
        Task {
            do {
                let history = try parseHistory(historyJSON)
                let result = try await agent.singleStep(goal: goal, actionHistory: history)
                let json = try JSONEncoder().encode(result)
                completion(String(data: json, encoding: .utf8), nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    // MARK: - Remote LLM Operations

    public func generateContent(
        _ type: String,
        context: String,
        completion: @escaping (String?, Error?) -> Void
    ) {
        guard let remote = remoteService else {
            completion(nil, NSError(
                domain: "VCLLMBridge",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Remote LLM not configured. Call configureRemoteProvider first."]
            ))
            return
        }
        Task {
            do {
                let generator = ContentGenerator(remoteLLM: remote)
                let result = try await generator.generate(type: type, context: context)
                let json = try JSONEncoder().encode(result)
                completion(String(data: json, encoding: .utf8), nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    public func planWorkflow(
        _ instruction: String,
        completion: @escaping (String?, Error?) -> Void
    ) {
        guard let remote = remoteService else {
            completion(nil, NSError(
                domain: "VCLLMBridge",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Remote LLM not configured."]
            ))
            return
        }
        Task {
            do {
                let planner = WorkflowPlanner(remoteLLM: remote)
                let plan = try await planner.plan(instruction: instruction)
                let json = try JSONEncoder().encode(plan)
                completion(String(data: json, encoding: .utf8), nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    public func decomposeInstruction(
        _ instruction: String,
        completion: @escaping (String?, Error?) -> Void
    ) {
        guard let remote = remoteService else {
            completion(nil, NSError(
                domain: "VCLLMBridge",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Remote LLM not configured."]
            ))
            return
        }
        Task {
            do {
                let parser = InstructionParser(remoteLLM: remote)
                let steps = try await parser.decompose(instruction: instruction)
                let json = try JSONEncoder().encode(steps)
                completion(String(data: json, encoding: .utf8), nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    // MARK: - Helpers

    private func parseHistory(_ json: String) throws -> [AgentAction] {
        guard let data = json.data(using: .utf8) else { return [] }
        if json.isEmpty || json == "[]" { return [] }
        return try JSONDecoder().decode([AgentAction].self, from: data)
    }
}
