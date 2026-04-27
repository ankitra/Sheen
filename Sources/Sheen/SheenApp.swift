import SwiftUI

@main
struct SheenApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.hasSetup {
                DashboardView()
            } else {
                SetupView()
            }
        }
        .environment(appState)
    }
}
