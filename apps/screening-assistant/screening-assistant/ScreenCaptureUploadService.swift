import ScreeningShared
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

public protocol ScreenCaptureUploading {
    func uploadAndAnalyze(image: PlatformImage, prompt: String) async throws -> AnalysisUploadResponse
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

    public var uploadFormat: ImageFormat = .jpg

    public func uploadAndAnalyze(image: PlatformImage, prompt: String = "Analyze this screen content") async throws -> AnalysisUploadResponse {
        guard let imageData = image.toData(format: uploadFormat, compressionQuality: 0.8) else {
            throw UploadError.invalidImageData
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".utf8))
        body.append(Data("\(prompt)\r\n".utf8))

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"screenshot.\(uploadFormat.fileExtension)\"\r\n".utf8))
        body.append(Data("Content-Type: \(uploadFormat.mimeType)\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n".utf8))

        body.append(Data("--\(boundary)--\r\n".utf8))
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
