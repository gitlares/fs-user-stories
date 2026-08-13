// SPDX-License-Identifier: MIT

import Foundation
import Network

enum MCPServerState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case failed(String)
}

struct MCPHTTPResource: Sendable {
    let url: URL
    let contentType: String
    let filename: String
}

final class LocalMCPServer: @unchecked Sendable {
    static let defaultPort: UInt16 = 49_231
    static let maximumRequestSize = 1_048_576

    typealias RequestHandler = @MainActor @Sendable (MCPRequest) -> MCPResponse?
    typealias ResourceHandler = @MainActor @Sendable (UUID) -> MCPHTTPResource?

    let port: UInt16
    private let handler: RequestHandler
    private let resourceHandler: ResourceHandler
    private let stateChanged: @MainActor @Sendable (MCPServerState) -> Void
    private let queue = DispatchQueue(label: "com.fsuserstories.mcp-server")
    private var listener: NWListener?

    init(
        port: UInt16 = LocalMCPServer.defaultPort,
        handler: @escaping RequestHandler,
        resourceHandler: @escaping ResourceHandler = { _ in nil },
        stateChanged: @escaping @MainActor @Sendable (MCPServerState) -> Void
    ) {
        self.port = port
        self.handler = handler
        self.resourceHandler = resourceHandler
        self.stateChanged = stateChanged
    }

    var endpointURL: URL {
        URL(string: "http://127.0.0.1:\(port)/mcp")!
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                switch state {
                case .setup, .waiting:
                    self.stateChanged(.starting)
                case .ready:
                    self.stateChanged(.running)
                case let .failed(error):
                    self.stateChanged(.failed(error.localizedDescription))
                case .cancelled:
                    self.stateChanged(.stopped)
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(from: connection, accumulated: Data())
    }

    private func receive(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var requestData = accumulated
            if let content {
                requestData.append(content)
            }

            guard requestData.count <= Self.maximumRequestSize else {
                self.send(status: 413, body: nil, to: connection)
                return
            }

            if let request = HTTPRequest.parse(requestData) {
                Task {
                    await self.respond(to: request, connection: connection)
                }
            } else if isComplete || error != nil {
                self.send(status: 400, body: nil, to: connection)
            } else {
                self.receive(from: connection, accumulated: requestData)
            }
        }
    }

    private func respond(to request: HTTPRequest, connection: NWConnection) async {
        guard validHost(request.headers["host"]) else {
            send(status: 403, body: nil, to: connection)
            return
        }
        guard validOrigin(request.headers["origin"]) else {
            send(status: 403, body: nil, to: connection)
            return
        }

        if request.method == "GET", request.path.hasPrefix("/attachments/") {
            await sendAttachment(for: request.path, to: connection)
            return
        }

        guard request.path == "/mcp" else {
            send(status: 404, body: nil, to: connection)
            return
        }

        switch request.method {
        case "GET":
            send(status: 405, body: nil, extraHeaders: ["Allow": "POST, DELETE"], to: connection)
        case "DELETE":
            send(status: 200, body: nil, to: connection)
        case "POST":
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true else {
                send(status: 415, body: nil, to: connection)
                return
            }

            let decoded: MCPRequest
            do {
                decoded = try JSONDecoder().decode(MCPRequest.self, from: request.body)
            } catch {
                let response = MCPResponse.failure(id: .null, code: -32700, message: "Parse error")
                sendJSON(response, status: 400, to: connection)
                return
            }

            guard decoded.jsonrpc == "2.0" else {
                let response = MCPResponse.failure(id: decoded.id ?? .null, code: -32600, message: "Invalid Request")
                sendJSON(response, status: 400, to: connection)
                return
            }

            guard let response = await handler(decoded) else {
                send(status: 202, body: nil, to: connection)
                return
            }
            sendJSON(response, status: 200, to: connection)
        default:
            send(status: 405, body: nil, extraHeaders: ["Allow": "POST, DELETE"], to: connection)
        }
    }

    private func validHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "127.0.0.1:\(port)" || host == "localhost:\(port)"
    }

    private func validOrigin(_ origin: String?) -> Bool {
        guard let origin else { return true }
        guard let components = URLComponents(string: origin), let host = components.host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func sendAttachment(for path: String, to connection: NWConnection) async {
        let rawID = String(path.dropFirst("/attachments/".count))
        guard
            !rawID.contains("/"),
            let attachmentID = UUID(uuidString: rawID),
            let resource = await resourceHandler(attachmentID),
            let data = try? Data(contentsOf: resource.url, options: .mappedIfSafe)
        else {
            send(status: 404, body: nil, to: connection)
            return
        }

        let encodedFilename = resource.filename.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? "attachment"
        send(
            status: 200,
            body: data,
            extraHeaders: [
                "Content-Type": resource.contentType,
                "Content-Disposition": "inline; filename*=UTF-8''\(encodedFilename)",
                "X-Content-Type-Options": "nosniff"
            ],
            to: connection
        )
    }

    private func sendJSON(_ response: MCPResponse, status: Int, to connection: NWConnection) {
        do {
            let encoder = JSONEncoder()
            let body = try encoder.encode(response)
            send(
                status: status,
                body: body,
                extraHeaders: ["Content-Type": "application/json; charset=utf-8"],
                to: connection
            )
        } catch {
            send(status: 500, body: nil, to: connection)
        }
    }

    private func send(
        status: Int,
        body: Data?,
        extraHeaders: [String: String] = [:],
        to connection: NWConnection
    ) {
        let reason = Self.reasonPhrase(for: status)
        let body = body ?? Data()
        var headers = [
            "Content-Length": "\(body.count)",
            "Connection": "close",
            "Cache-Control": "no-store"
        ]
        headers.merge(extraHeaders) { _, new in new }
        let headerLines = headers.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
        var response = Data("HTTP/1.1 \(status) \(reason)\r\n\(headerLines)\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        default: "Internal Server Error"
        }
    }
}

private struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard
            let headerRange = data.range(of: delimiter),
            let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard lines.count > 0 else { return nil }
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }

        return HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: String(requestLine[1]),
            headers: headers,
            body: data.subdata(in: bodyStart..<(bodyStart + contentLength))
        )
    }
}
