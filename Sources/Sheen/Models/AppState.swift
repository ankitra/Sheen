import Foundation
import Observation

@Observable
final class AppState {
    var config = RepositoryConfig()
    var syncState: SyncState = .idle
    var hasSetup = false
    var activityLog: [String] = []

    let keychainManager = KeychainManager()
    var gitService: GitService?
    var syncEngine: SyncEngine?

    private let defaults = UserDefaults.standard

    init() {
        loadConfig()
    }

    func loadConfig() {
        guard let data = defaults.data(forKey: "repoConfig"),
              let decoded = try? JSONDecoder().decode(RepositoryConfig.self, from: data) else {
            return
        }
        config = decoded
        hasSetup = !config.vaultPath.isEmpty && !config.remoteURL.isEmpty
    }

    func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: "repoConfig")
        hasSetup = !config.vaultPath.isEmpty && !config.remoteURL.isEmpty
    }

    func resetConfig() {
        defaults.removeObject(forKey: "repoConfig")
        config = RepositoryConfig()
        syncState = .idle
        hasSetup = false
        activityLog.removeAll()
        gitService = nil
        syncEngine = nil
    }

    var vaultURL: URL {
        URL(fileURLWithPath: config.vaultPath)
    }

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        activityLog.insert("[\(timestamp)] \(message)", at: 0)
    }
}
