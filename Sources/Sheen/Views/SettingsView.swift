import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var remoteURL = ""
    @State private var branch = "main"
    @State private var token = ""
    @State private var showFolderPicker = false
    @State private var showResetConfirmation = false
    @State private var autoSyncEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Vault Path") {
                    HStack {
                        Text(appState.config.vaultPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Change") { showFolderPicker = true }
                    }
                }

                Section("Remote Repository") {
                    TextField("Repository URL", text: $remoteURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                    TextField("Branch", text: $branch)
                        .autocorrectionDisabled()
                }

                Section("Access Token") {
                    SecureField("GitHub PAT", text: $token)
                        .textContentType(.password)
                    if appState.keychainManager.hasToken {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Token stored in Keychain")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Save Changes") {
                        save()
                    }
                    .disabled(remoteURL.isEmpty)
                }

                Section {
                    Toggle(isOn: $autoSyncEnabled) {
                        Label("Auto-sync vault changes", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .onChange(of: autoSyncEnabled) { _, enabled in
                        if enabled {
                            appState.syncEngine?.startAutoSync(vaultURL: appState.vaultURL)
                        } else {
                            appState.syncEngine?.stopAutoSync()
                        }
                    }

                    if appState.syncEngine?.isAutoSyncEnabled == true {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Auto-sync is active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Sync Behavior")
                } footer: {
                    Text("When enabled, file changes in your vault are automatically committed and pushed. When disabled, use Push/Pull manually or set up Shortcuts automation.")
                }

                Section {
                    Button("Reset All Settings", role: .destructive) {
                        showResetConfirmation = true
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    appState.config.vaultPath = url.path
                }
            }
            .alert("Reset Settings?", isPresented: $showResetConfirmation) {
                Button("Reset", role: .destructive) {
                    appState.keychainManager.deleteToken()
                    appState.resetConfig()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all configuration and the sync token.")
            }
            .onAppear {
                remoteURL = appState.config.remoteURL
                branch = appState.config.branch
                token = appState.keychainManager.getToken() ?? ""
                autoSyncEnabled = appState.syncEngine?.isAutoSyncEnabled ?? false
            }
        }
    }

    private func save() {
        appState.config.remoteURL = remoteURL
        appState.config.branch = branch
        if !token.isEmpty {
            appState.keychainManager.saveToken(token)
        }
        appState.saveConfig()
        dismiss()
    }
}
