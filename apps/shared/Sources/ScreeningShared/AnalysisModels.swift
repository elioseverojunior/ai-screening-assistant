import Foundation

public struct AnalysisPayload: Codable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let model: String
    public let response: String
    public let prompt: String?
    public let imageBase64: String?

    public init(id: UUID = UUID(), timestamp: Date = Date(), model: String, response: String, prompt: String? = nil, imageBase64: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.model = model
        self.response = response
        self.prompt = prompt
        self.imageBase64 = imageBase64
    }
}

public struct AnalysisUploadResponse: Codable, Equatable {
    public let model: String
    public let response: String
    public let processingMs: Double?

    enum CodingKeys: String, CodingKey {
        case model
        case response
        case processingMs = "processing_ms"
    }

    public init(model: String, response: String, processingMs: Double? = nil) {
        self.model = model
        self.response = response
        self.processingMs = processingMs
    }
}
