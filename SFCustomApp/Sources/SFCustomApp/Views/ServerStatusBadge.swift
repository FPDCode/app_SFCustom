import SwiftUI

struct ServerStatusBadge: View {
    @EnvironmentObject var server: LocalServer

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(server.isRunning ? Color.green : Color.gray.opacity(0.6))
                .frame(width: 8, height: 8)
            Text(server.isRunning ? "Plugin bridge: on (port \(server.port))" : "Plugin bridge: off")
                .font(.caption)
                .foregroundStyle(server.isRunning ? .primary : .secondary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { server.isRunning },
                set: { newValue in
                    if newValue { server.start(on: server.port) } else { server.stop() }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
    }
}
