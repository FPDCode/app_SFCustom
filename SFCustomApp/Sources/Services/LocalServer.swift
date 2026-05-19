import Foundation
import Network

/// Lightweight HTTP server on localhost for Figma plugin communication
/// Accepts icon data from the plugin and returns processing status
@MainActor
class LocalServer {

    let port: UInt16
    private var listener: NWListener?
    private weak var appState: AppState?

    init(port: UInt16 = 8787) {
        self.port = port
    }

    // MARK: - Lifecycle

    func start(appState: AppState) async throws {
        self.appState = appState

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[LocalServer] Listening on localhost:\(self.port)")
            case .failed(let error):
                print("[LocalServer] Failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        print("[LocalServer] Stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self = self, let data = data else {
                    connection.cancel()
                    return
                }

                let response = self.routeRequest(data: data)
                self.sendResponse(response, on: connection)
            }
        }
    }

    // MARK: - Routing

    private func routeRequest(data: Data) -> HTTPResponse {
        guard let request = parseHTTPRequest(data) else {
            return HTTPResponse(status: 400, body: ["error": "Invalid request"])
        }

        switch (request.method, request.path) {
        case ("GET", "/api/status"):
            return handleStatus()
        case ("POST", "/api/icons"):
            return handleAddIcon(body: request.body)
        case ("GET", "/api/icons"):
            return handleListIcons()
        case ("POST", "/api/export/template"):
            return handleExportTemplate(body: request.body)
        case ("POST", "/api/export/font"):
            return handleExportFont()
        case ("OPTIONS", _):
            return HTTPResponse(status: 200, body: ["ok": true], corsHeaders: true)
        default:
            return HTTPResponse(status: 404, body: ["error": "Not found"])
        }
    }

    // MARK: - Route Handlers

    private func handleStatus() -> HTTPResponse {
        HTTPResponse(status: 200, body: [
            "status": "running",
            "version": "1.0",
            "iconCount": appState?.library.icons.count ?? 0
        ])
    }

    private func handleAddIcon(body: Data?) -> HTTPResponse {
        guard let body = body else {
            return HTTPResponse(status: 400, body: ["error": "Missing request body"])
        }

        // Expected JSON: { "name": "...", "svgPath": "...", "weightMode": "uniform"|"single"|"full", "sourceWeight": "regular" }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let name = json["name"] as? String,
              let svgPath = json["svgPath"] as? String else {
            return HTTPResponse(status: 400, body: ["error": "Invalid JSON. Required: name, svgPath"])
        }

        let weightModeStr = json["weightMode"] as? String ?? "uniform"
        let sourceWeightStr = json["sourceWeight"] as? String ?? "regular"

        let weightMode: WeightMode
        switch weightModeStr {
        case "single":
            let sourceWeight = WeightMasters.SourceWeight(rawValue: sourceWeightStr) ?? .regular
            weightMode = .singleGenerate(sourceWeight)
        case "full":
            weightMode = .fullControl
        default:
            weightMode = .uniform
        }

        let tags = (json["tags"] as? [String]) ?? []
        let fullSVG = json["fullSVG"] as? String

        let icon = Icon(
            name: name,
            svgPath: svgPath,
            weightMode: weightMode,
            tags: tags,
            sourceSVG: fullSVG
        )

        appState?.addIcon(icon)

        return HTTPResponse(status: 201, body: [
            "success": true,
            "iconId": icon.id.uuidString,
            "name": icon.name
        ])
    }

    private func handleListIcons() -> HTTPResponse {
        let icons = appState?.library.icons ?? []
        let list = icons.map { ["id": $0.id.uuidString, "name": $0.name] }
        return HTTPResponse(status: 200, body: ["icons": list])
    }

    private func handleExportTemplate(body: Data?) -> HTTPResponse {
        guard let body = body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let iconId = json["iconId"] as? String,
              let uuid = UUID(uuidString: iconId),
              let icon = appState?.library.icons.first(where: { $0.id == uuid }) else {
            return HTTPResponse(status: 400, body: ["error": "Icon not found"])
        }

        do {
            let _ = try appState?.exportTemplate(for: icon)
            return HTTPResponse(status: 200, body: ["success": true, "iconName": icon.name])
        } catch {
            return HTTPResponse(status: 500, body: ["error": error.localizedDescription])
        }
    }

    private func handleExportFont() -> HTTPResponse {
        do {
            let url = try appState?.exportFont()
            return HTTPResponse(status: 200, body: [
                "success": true,
                "fontPath": url?.path ?? ""
            ])
        } catch {
            return HTTPResponse(status: 500, body: ["error": error.localizedDescription])
        }
    }

    // MARK: - HTTP Parsing

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data?
    }

    private func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }

        let parts = raw.components(separatedBy: "\r\n\r\n")
        let headerSection = parts[0]
        let bodyString = parts.count > 1 ? parts[1] : nil

        let lines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let requestParts = requestLine.components(separatedBy: " ")
        guard requestParts.count >= 2 else { return nil }

        let method = requestParts[0]
        let path = requestParts[1]

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let kv = line.components(separatedBy: ": ")
            if kv.count == 2 {
                headers[kv[0].lowercased()] = kv[1]
            }
        }

        return HTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: bodyString?.data(using: .utf8)
        )
    }

    // MARK: - HTTP Response

    private struct HTTPResponse {
        let status: Int
        let body: Any
        var corsHeaders: Bool = true
    }

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let jsonData = (try? JSONSerialization.data(withJSONObject: response.body)) ?? Data()
        let statusText = response.status == 200 ? "OK" : (response.status == 201 ? "Created" : "Error")

        var header = "HTTP/1.1 \(response.status) \(statusText)\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(jsonData.count)\r\n"
        if response.corsHeaders {
            header += "Access-Control-Allow-Origin: *\r\n"
            header += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            header += "Access-Control-Allow-Headers: Content-Type\r\n"
        }
        header += "\r\n"

        var responseData = Data(header.utf8)
        responseData.append(jsonData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
