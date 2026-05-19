import Foundation
import Network

/// Tiny localhost HTTP server the Figma plugin posts to.
///
/// Endpoints:
///   GET  /api/status       → { "ok": true, "iconCount": N }
///   POST /api/icons        ← { "name": "...", "svg": "<svg>..." }
///                          → { "ok": true, "id": "...", "name": "..." }
///
/// Listens on 127.0.0.1 only. CORS is open (`*`) since the plugin's UI
/// iframe origin isn't predictable.
@MainActor
final class LocalServer: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var port: UInt16 = 8787
    @Published private(set) var lastError: String?

    private var listener: NWListener?
    private weak var library: IconLibrary?

    func attach(library: IconLibrary) {
        self.library = library
    }

    func start(on requestedPort: UInt16 = 8787) {
        stop()
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: .init(rawValue: requestedPort)!)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.lastError = nil
                        self.port = requestedPort
                    case .failed(let err):
                        self.isRunning = false
                        self.lastError = err.localizedDescription
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in
                    self?.handle(conn)
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener
        } catch {
            self.lastError = error.localizedDescription
            self.isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receive(connection: connection, buffer: Data())
    }

    private func receive(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            var newBuffer = buffer
            if let data { newBuffer.append(data) }

            if let request = HTTPRequest.parse(newBuffer) {
                Task { @MainActor in
                    self.route(request, on: connection)
                }
            } else if !isComplete {
                Task { @MainActor in
                    self.receive(connection: connection, buffer: newBuffer)
                }
            } else {
                Task { @MainActor in
                    self.respond(.badRequest("Malformed HTTP request"), on: connection)
                }
            }
        }
    }

    private func route(_ request: HTTPRequest, on connection: NWConnection) {
        // CORS preflight
        if request.method == "OPTIONS" {
            respond(.corsPreflight, on: connection)
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/api/status"):
            let count = library?.icons.count ?? 0
            respond(.json(["ok": true, "iconCount": count, "port": Int(port)]), on: connection)

        case ("POST", "/api/icons"):
            handleIngest(request, on: connection)

        default:
            respond(.notFound, on: connection)
        }
    }

    private func handleIngest(_ request: HTTPRequest, on connection: NWConnection) {
        guard let library else {
            respond(.json(["ok": false, "error": "library_unavailable"]), on: connection)
            return
        }
        guard let body = request.body,
              let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let name = dict["name"] as? String,
              let svg = dict["svg"] as? String
        else {
            respond(.json(["ok": false, "error": "invalid_payload"]), on: connection)
            return
        }
        let icon = library.add(name: name, sourceSVG: svg)
        respond(.json([
            "ok": true,
            "id": icon.id.uuidString,
            "name": icon.name,
            "codepoint": Int(icon.codepoint),
        ]), on: connection)
    }

    private func respond(_ response: HTTPResponse, on connection: NWConnection) {
        let data = response.serialize()
        connection.send(content: data, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}

// MARK: - Minimal HTTP types

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data?

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: 0..<headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let bodyStart = headerEndRange.upperBound
        var body: Data? = nil
        if bodyStart < data.endIndex {
            let candidate = data.subdata(in: bodyStart..<data.endIndex)
            if let lengthStr = headers["content-length"], let expected = Int(lengthStr) {
                guard candidate.count >= expected else { return nil }
                body = candidate.prefix(expected)
            } else {
                body = candidate
            }
        } else if let lengthStr = headers["content-length"], let expected = Int(lengthStr), expected > 0 {
            return nil // body not received yet
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}

private enum HTTPResponse {
    case json([String: Any])
    case notFound
    case badRequest(String)
    case corsPreflight

    func serialize() -> Data {
        switch self {
        case .json(let dict):
            let body = (try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])) ?? Data("{}".utf8)
            return makeResponse(status: "200 OK", contentType: "application/json", body: body)
        case .notFound:
            return makeResponse(status: "404 Not Found", contentType: "text/plain", body: Data("not found".utf8))
        case .badRequest(let msg):
            return makeResponse(status: "400 Bad Request", contentType: "text/plain", body: Data(msg.utf8))
        case .corsPreflight:
            return makeResponse(status: "204 No Content", contentType: "text/plain", body: Data())
        }
    }

    private func makeResponse(status: String, contentType: String, body: Data) -> Data {
        let headers = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Connection: close\r
        \r

        """
        var data = Data(headers.utf8)
        data.append(body)
        return data
    }
}
