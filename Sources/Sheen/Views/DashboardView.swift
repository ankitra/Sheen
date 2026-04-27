import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                syncStatusCard
                    .padding()

                actionButtons
                    .padding(.horizontal)

                Divider()
                    .padding(.vertical)

                activityLog
            }
            .navigationTitle("Sheen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") {
                        showSettings = true
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var syncStatusCard: some View {
        VStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: 40))
                .foregroundStyle(statusColor)

            Text(statusText)
                .font(.headline)

            if case .success(let date) = appState.syncState {
                Text("Last synced: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: .rect(cornerRadius: 12))
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(action: push) {
                Label("Push", systemImage: "arrow.up.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)

            Button(action: pull) {
                Label("Pull", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)
        }
    }

    private var activityLog: some View {
        List {
            Section("Activity") {
                if appState.activityLog.isEmpty {
                    Text("No activity yet")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(appState.activityLog, id: \.self) { entry in
                        Text(entry)
                            .font(.caption)
                            .monospaced()
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var isBusy: Bool {
        if case .syncing = appState.syncState { return true }
        return false
    }

    private var statusIcon: String {
        switch appState.syncState {
        case .idle:       return "checkmark.circle"
        case .syncing:    return "arrow.triangle.2.circlepath"
        case .success:    return "checkmark.circle.fill"
        case .error:      return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch appState.syncState {
        case .idle:       return .secondary
        case .syncing:    return .blue
        case .success:    return .green
        case .error:      return .red
        }
    }

    private var statusText: String {
        switch appState.syncState {
        case .idle:       return "Ready"
        case .syncing:    return "Syncing..."
        case .success:    return "Synced"
        case .error(let e): return e
        }
    }

    private func push() {
        guard let engine = appState.syncEngine else { return }
        Task { await engine.push() }
    }

    private func pull() {
        guard let engine = appState.syncEngine else { return }
        Task { await engine.pull() }
    }
}
