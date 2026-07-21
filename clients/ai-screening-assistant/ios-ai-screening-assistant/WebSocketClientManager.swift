import Foundation
import Combine

public struct AnalysisPayload: Codable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let model: String
    public let response: String
    public let imageBase64: String?

    public init(id: UUID = UUID(), timestamp: Date = Date(), model: String, response: String, imageBase64: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.model = model
        self.response = response
        self.imageBase64 = imageBase64
    }
}

public final class WebSocketClientManager: ObservableObject {
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var latestAnalysis: AnalysisPayload?
    @Published public private(set) var history: [AnalysisPayload] = []

    private var webSocketTask: URLSessionWebSocketTask?
    private let serverURL: URL

    public init(serverURL: URL = URL(string: "ws://localhost:8000/ws/analysis")!) {
        self.serverURL = serverURL
    }

    public func connect() {
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        isConnected = true
        receiveMessage()
    }

    public func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async {
                    self.isConnected = false
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let payload = try? JSONDecoder().decode(AnalysisPayload.self, from: data) {
                        DispatchQueue.main.async {
                            self.latestAnalysis = payload
                            self.history.append(payload)
                        }
                    }
                case .data(let data):
                    if let payload = try? JSONDecoder().decode(AnalysisPayload.self, from: data) {
                        DispatchQueue.main.async {
                            self.latestAnalysis = payload
                            self.history.append(payload)
                        }
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()
            }
        }
    }
}
