import Foundation
import Combine

@MainActor
public final class WebSocketClientManager: ObservableObject {
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var latestAnalysis: AnalysisPayload?
    @Published public private(set) var history: [AnalysisPayload] = []

    private var webSocketTask: URLSessionWebSocketTask?
    public var serverURL: URL

    public init(serverURL: URL = URL(string: "ws://localhost:8000/ws/analysis")!) {
        self.serverURL = serverURL
    }

    public func connect() {
        disconnect()
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        isConnected = true
        receiveMessage()
    }

    public func reconnect(to newURL: URL) {
        serverURL = newURL
        connect()
    }

    public func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .failure:
                    isConnected = false
                case .success(let message):
                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8),
                           let payload = try? JSONDecoder().decode(AnalysisPayload.self, from: data) {
                            latestAnalysis = payload
                            history.append(payload)
                        }
                    case .data(let data):
                        if let payload = try? JSONDecoder().decode(AnalysisPayload.self, from: data) {
                            latestAnalysis = payload
                            history.append(payload)
                        }
                    @unknown default:
                        break
                    }
                    receiveMessage()
                }
            }
        }
    }
}
