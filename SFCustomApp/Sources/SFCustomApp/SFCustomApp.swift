import SwiftUI

@main
struct SFCustomApp: App {
    @StateObject private var library = IconLibrary()
    @StateObject private var server = LocalServer()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup("SF Custom") {
            ContentView()
                .environmentObject(library)
                .environmentObject(server)
                .environmentObject(settings)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    server.attach(library: library)
                    if settings.startServerAutomatically {
                        server.start(on: UInt16(settings.serverPort))
                    }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import SVG…") {
                    NotificationCenter.default.post(name: .sfcImportSVG, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(server)
        }
    }
}

extension Notification.Name {
    static let sfcImportSVG = Notification.Name("SFCustomImportSVG")
}
