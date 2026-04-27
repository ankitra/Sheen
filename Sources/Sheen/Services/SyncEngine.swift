import Foundation
import Combine

final class SyncEngine {
    let gitService: GitService
    private let appState: AppState
    private var vaultMonitor: VaultMonitor?
    private var autoSyncCancellable: AnyCancellable?

    init(gitService: GitService, appState: AppState) {
        self.gitService = gitService
        self.appState = appState
    }

    // MARK: - Setup

    func initializeRepository() async throws {
        guard let token = appState.keychainManager.getToken() else {
            throw SyncError.noToken
        }
        let vaultURL = appState.vaultURL

        let repoURL = appState.config.remoteURL
        let gitDir = vaultURL.appendingPathComponent(".git")

        if FileManager.default.fileExists(atPath: gitDir.path) {
            try await gitService.openRepository(at: vaultURL)
        } else {
            try await gitService.cloneRepository(from: repoURL, credentialsToken: token, to: vaultURL)
        }
    }

    /// Reopen an already-set-up repository from config (used by App Intents).
    func resume() async throws {
        guard appState.keychainManager.getToken() != nil else {
            throw SyncError.noToken
        }
        let vaultURL = appState.vaultURL
        let gitDir = vaultURL.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            throw SyncError.notInitialized
        }
        try await gitService.openRepository(at: vaultURL)
    }

    // MARK: - Auto Sync (optional)

    var isAutoSyncEnabled: Bool { vaultMonitor != nil }

    func startAutoSync(vaultURL: URL) {
        guard vaultMonitor == nil else { return }

        let monitor = VaultMonitor()
        do {
            try monitor.startMonitoring(url: vaultURL)
        } catch {
            appState.log("Auto-sync failed to start: \(error.localizedDescription)")
            return
        }
        vaultMonitor = monitor

        autoSyncCancellable = monitor.changePublisher
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] changes in
                guard let self else { return }
                Task { await self.autoSync(changes: changes) }
            }
    }

    func stopAutoSync() {
        vaultMonitor?.stopMonitoring()
        vaultMonitor = nil
        autoSyncCancellable = nil
    }

    private func autoSync(changes: [FileChange]) async {
        appState.syncState = .syncing

        do {
            guard let token = appState.keychainManager.getToken() else {
                throw SyncError.noToken
            }
            guard try await gitService.hasChanges() else {
                appState.syncState = .idle
                return
            }

            let fileList = changes.map(\.path).joined(separator: ", ")
            let message = "Auto-sync: \(fileList)"

            try await gitService.stageAll()
            try await gitService.commit(message: message)
            try await gitService.push(credentialsToken: token)

            appState.syncState = .success(Date())
            appState.log("Pushed \(changes.count) change(s)")
        } catch {
            appState.syncState = .error(error.localizedDescription)
            appState.log("Sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Manual Operations

    func push() async {
        appState.syncState = .syncing
        do {
            guard let token = appState.keychainManager.getToken() else {
                throw SyncError.noToken
            }
            guard try await gitService.hasChanges() else {
                appState.syncState = .idle
                appState.log("Nothing to push")
                return
            }

            try await gitService.stageAll()
            try await gitService.commit(message: "Manual sync")
            try await gitService.push(credentialsToken: token)

            appState.syncState = .success(Date())
            appState.log("Push succeeded")
        } catch {
            appState.syncState = .error(error.localizedDescription)
            appState.log("Push failed: \(error.localizedDescription)")
        }
    }

    func pull() async {
        appState.syncState = .syncing
        do {
            guard let token = appState.keychainManager.getToken() else {
                throw SyncError.noToken
            }

            try await gitService.pull(credentialsToken: token)

            appState.syncState = .success(Date())
            appState.log("Pull succeeded")
        } catch {
            appState.syncState = .error(error.localizedDescription)
            appState.log("Pull failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        stopAutoSync()
    }
}

enum SyncError: LocalizedError {
    case noToken
    case invalidVaultPath
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .noToken:          return "GitHub token not configured"
        case .invalidVaultPath: return "Invalid vault path"
        case .notInitialized:  return "Sync engine not initialized"
        }
    }
}
