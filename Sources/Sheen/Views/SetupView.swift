import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @State private var remoteURL = ""
    @State private var token = ""
    @State private var showFolderPicker = false
    @State private var vaultBookmark: Data?
    @State private var isInitializing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Obsidian Vault") {
                    HStack {
                        if appState.config.vaultPath.isEmpty {
                            Text("Select vault folder")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(appState.config.vaultPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Browse") { showFolderPicker = true }
                    }
                }

                Section("Remote Repository") {
                    TextField("https://github.com/user/repo.git", text: $remoteURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                    TextField("Branch", text: Binding(
                        get: { appState.config.branch },
                        set: { appState.config.branch = $0 }
                    ))
                    .autocorrectionDisabled()
                }

                Section("GitHub Access Token") {
                    SecureField("Personal Access Token", text: $token)
                        .textContentType(.password)
                    if !token.isEmpty {
                        Button("Validate Token") {
                            validateToken()
                        }
                        .font(.caption)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button(action: initialize) {
                        if isInitializing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Save & Start Syncing")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isInitializing || !isFormValid)
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Setup Sheen")
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    appState.config.vaultPath = url.path
                    vaultBookmark = try? url.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
            }
        }
    }

    private var isFormValid: Bool {
        !appState.config.vaultPath.isEmpty && !remoteURL.isEmpty && !token.isEmpty
    }

    private func validateToken() {
        guard token.count > 10 else {
            errorMessage = "Token looks too short"
            return
        }
        errorMessage = nil
    }

    private func initialize() {
        isInitializing = true
        errorMessage = nil
        appState.config.remoteURL = remoteURL
        appState.keychainManager.saveToken(token)
        appState.saveConfig()

        Task {
            do {
                let gs = GitService()
                let engine = SyncEngine(gitService: gs, appState: appState)
                try await engine.initializeRepository()

                appState.gitService = gs
                appState.syncEngine = engine
                appState.syncState = .idle
                appState.log("Setup complete")
                appState.saveConfig()
            } catch {
                errorMessage = error.localizedDescription
                appState.keychainManager.deleteToken()
                appState.resetConfig()
            }
            isInitializing = false
        }
    }
}
