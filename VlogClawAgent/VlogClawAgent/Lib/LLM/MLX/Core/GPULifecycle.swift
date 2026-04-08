import Foundation
#if canImport(UIKit) && !XCTEST_AGENT
import UIKit
#endif

// MARK: - MLXLocalLLMService GPU + app lifecycle extension
//
// XCTest 环境下：进程始终为前台状态，GPU 可直接使用，无需生命周期监听。
// UIKit App 环境下：监听 UIApplication 生命周期，防止后台 Metal compute 被 jetsam kill。

extension MLXLocalLLMService {

    func ensureForegroundGPUExecution() async throws {
        #if canImport(UIKit) && !XCTEST_AGENT
        let isActive = await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
        setForegroundGPUAllowed(isActive)
        guard isActive else {
            throw MLXError.gpuExecutionRequiresForeground
        }
        #elseif XCTEST_AGENT
        // XCTest 进程始终前台运行，GPU 可用
        setForegroundGPUAllowed(true)
        #endif
    }

    func configureLifecycleObservers() {
        #if canImport(UIKit) && !XCTEST_AGENT
        let center = NotificationCenter.default
        lifecycleObserverTokens = [
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.handleApplicationLeavingForeground()
            },
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.handleApplicationLeavingForeground()
            },
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setForegroundGPUAllowed(true)
            },
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setForegroundGPUAllowed(true)
            }
        ]

        Task { [weak self] in
            guard let self else { return }
            let isActive = await MainActor.run {
                UIApplication.shared.applicationState == .active
            }
            self.setForegroundGPUAllowed(isActive)
        }
        #elseif XCTEST_AGENT
        // XCTest 环境：无需监听生命周期，始终视为前台
        setForegroundGPUAllowed(true)
        #endif
    }

    func handleApplicationLeavingForeground() {
        setForegroundGPUAllowed(false)
        cancelled = true
        currentGenerationTask?.cancel()
        currentLoadTask?.cancel()
    }

    func setForegroundGPUAllowed(_ allowed: Bool) {
        foregroundStateLock.lock()
        foregroundGPUAllowed = allowed
        foregroundStateLock.unlock()
    }

    func isForegroundGPUAllowed() -> Bool {
        foregroundStateLock.lock()
        let allowed = foregroundGPUAllowed
        foregroundStateLock.unlock()
        return allowed
    }
}
