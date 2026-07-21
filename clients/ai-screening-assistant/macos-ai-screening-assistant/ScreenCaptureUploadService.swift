#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

public protocol ScreenCaptureUploading {
    func uploadAndAnalyze(image: PlatformImage, prompt: String) async throws -> AnalysisUploadResponse
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

public enum UploadError: Error, LocalizedError, Equatable {
    case invalidImageData
    case invalidResponse(Int)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Failed to encode image to JPEG representation"
        case .invalidResponse(let statusCode):
            return "Server responded with HTTP status code \(statusCode)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

public final class ScreenCaptureUploadService: ScreenCaptureUploading {
    private let serverURL: URL
    private let session: URLSession

    public init(serverURL: URL = URL(string: "http://localhost:8000/api/analyze")!, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.session = session
    }

    public func uploadAndAnalyze(image: PlatformImage, prompt: String = "Analyze this screen content") async throws -> AnalysisUploadResponse {
        guard let jpegData = image.toJPEGData(compressionQuality: 0.8) else {
            throw UploadError.invalidImageData
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Append prompt field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(prompt)\r\n".data(using: .utf8)!)

        // Append image file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"screenshot.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UploadError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw UploadError.invalidResponse(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(AnalysisUploadResponse.self, from: data)
    }
}
