import AppIntents
import Foundation

// MARK: - Push Intent

struct PushChangesIntent: AppIntent {
    static var title: LocalizedStringResource = "Push Obsidian Changes"
    static var description = IntentDescription("Commits and pushes vault changes to the remote repository.")

    func perform() async throws -> some IntentResult {
        let appState = AppState()
        guard appState.hasSetup else {
            return .result(dialog: "Sheen is not set up yet. Open the app to configure it.")
        }

        let gs = GitService()
        let engine = SyncEngine(gitService: gs, appState: appState)

        do {
            try await engine.resume()
        } catch {
            return .result(dialog: "Could not open repository. Reopen the app first.")
        }

        await engine.push()

        if case .error(let message) = appState.syncState {
            return .result(dialog: "Push failed: \(message)")
        }
        return .result(dialog: "Changes pushed successfully.")
    }
}

// MARK: - Pull Intent

struct PullChangesIntent: AppIntent {
    static var title: LocalizedStringResource = "Pull Remote Changes"
    static var description = IntentDescription("Pulls the latest changes from the remote repository.")

    func perform() async throws -> some IntentResult {
        let appState = AppState()
        guard appState.hasSetup else {
            return .result(dialog: "Sheen is not set up yet. Open the app to configure it.")
        }

        let gs = GitService()
        let engine = SyncEngine(gitService: gs, appState: appState)

        do {
            try await engine.resume()
        } catch {
            return .result(dialog: "Could not open repository. Reopen the app first.")
        }

        await engine.pull()

        if case .error(let message) = appState.syncState {
            return .result(dialog: "Pull failed: \(message)")
        }
        return .result(dialog: "Remote changes pulled successfully.")
    }
}

// MARK: - Status Intent

struct GetSyncStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Sync Status"
    static var description = IntentDescription("Checks the current sync status of the vault.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let appState = AppState()
        guard appState.hasSetup else {
            return .result(value: "Not configured")
        }

        let status: String
        switch appState.syncState {
        case .idle:
            status = "Ready"
        case .syncing:
            status = "Syncing..."
        case .success(let date):
            status = "Synced at \(date.formatted(date: .omitted, time: .shortened))"
        case .error(let message):
            status = "Error: \(message)"
        }

        return .result(value: status)
    }
}

// MARK: - Shortcuts Provider

struct SheenShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PushChangesIntent(),
            phrases: [
                "Push vault changes with \(.applicationName)",
                "Sync Obsidian with \(.applicationName)"
            ],
            shortTitle: "Push",
            systemImageName: "arrow.up.circle"
        )
        AppShortcut(
            intent: PullChangesIntent(),
            phrases: [
                "Pull remote changes with \(.applicationName)"
            ],
            shortTitle: "Pull",
            systemImageName: "arrow.down.circle"
        )
        AppShortcut(
            intent: GetSyncStatusIntent(),
            phrases: [
                "Check sync status with \(.applicationName)",
                "What is the sync status on \(.applicationName)"
            ],
            shortTitle: "Status",
            systemImageName: "info.circle"
        )
    }
}
