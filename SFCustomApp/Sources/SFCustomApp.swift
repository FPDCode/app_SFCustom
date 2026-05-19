import SwiftUI

@main
struct SFCustomApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    if !appState.isServerRunning {
                        appState.startServer()
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 750)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
