import ScreeningShared
#if os(macOS)
import AppKit
import ScreenCaptureKit
#else
import UIKit
#endif
import SwiftUI

enum CaptureError: Error {
    case noDisplay
    case permissionDenied
    case captureFailed(Error)
}

protocol ScreenCaptureProviding {
    func captureFullScreen() async throws -> PlatformImage
}

#if os(macOS)
final class ScreenCaptureService: ScreenCaptureProviding {
    func captureFullScreen() async throws -> PlatformImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw CaptureError.permissionDenied
        }
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw CaptureError.captureFailed(error)
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
#else
final class ScreenCaptureService: ScreenCaptureProviding {
    func captureFullScreen() async throws -> PlatformImage {
        return PlatformImage()
    }
}
#endif

final class ScreenCaptureManager {
    private let service: ScreenCaptureProviding
    private let uploadService: ScreenCaptureUploading?
    let store: ScreenshotStore

    init(
        service: ScreenCaptureProviding = ScreenCaptureService(),
        uploadService: ScreenCaptureUploading? = nil,
        store: ScreenshotStore = ScreenshotStore.shared
    ) {
        self.service = service
        self.uploadService = uploadService
        self.store = store
    }

    func captureAndStore() async throws {
        let image = try await service.captureFullScreen()
        let screenshot = store.addScreenshot(image)
        if let uploadService {
            do {
                let prompt = KeyBindingsController.shared.current.analysisPrompt
                let analysis = try await uploadService.uploadAndAnalyze(image: image, prompt: prompt)
                store.updateAnalysis(id: screenshot.id, response: analysis.response, model: analysis.model)
            } catch {
                store.updateAnalysis(id: screenshot.id, response: "Upload failed: \(error.localizedDescription)", model: nil)
            }
        }
    }
}

final class ScreenshotStore: NSObject {
    static let shared = ScreenshotStore(storageDirectory: URL(
        fileURLWithPath: KeyBindingsController.shared.current.screenshotStoragePath
    ))

    private(set) var screenshots: [CapturedScreenshot] = []
    var saveToDisk: Bool = true {
        didSet { saveManifest() }
    }
    var imageFormat: ImageFormat = .jpg
    private let ioQueue = DispatchQueue(label: "screenshot-store", qos: .utility)
    private(set) var storageDirectory: URL?
    var manifestURL: URL? {
        storageDirectory?.appendingPathComponent("manifest.json")
    }

    var count: Int { screenshots.count }

    init(storageDirectory: URL? = nil) {
        self.storageDirectory = storageDirectory
        if let dir = storageDirectory {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func changeStorageDirectory(to newURL: URL) {
        storageDirectory = newURL
        try? FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        saveManifest()
    }

    @discardableResult
    func addScreenshot(_ image: PlatformImage, response: String? = nil, model: String? = nil) -> CapturedScreenshot {
        let fileURL: URL?
        if saveToDisk, let storageDirectory {
            let fileName = "screenshot_\(UUID().uuidString).\(imageFormat.fileExtension)"
            fileURL = storageDirectory.appendingPathComponent(fileName)
            if let data = image.toData(format: imageFormat) {
                try? data.write(to: fileURL!)
            }
        } else {
            fileURL = nil
        }
        let screenshot = CapturedScreenshot(
            id: UUID(),
            date: Date(),
            image: image,
            fileURL: fileURL,
            analysisResult: response,
            analysisModel: model
        )
        screenshots.append(screenshot)
        saveManifest()
        return screenshot
    }

    func updateAnalysis(id: UUID, response: String, model: String?) {
        guard let index = screenshots.firstIndex(where: { $0.id == id }) else { return }
        let old = screenshots[index]
        screenshots[index] = CapturedScreenshot(
            id: old.id,
            date: old.date,
            image: old.image,
            fileURL: old.fileURL,
            analysisResult: response,
            analysisModel: model
        )
        saveManifest()
    }

    func image(for id: UUID) -> PlatformImage? {
        screenshots.first { $0.id == id }?.image
    }

    private func saveManifest() {
        guard let manifestURL else { return }
        do {
            let entries = screenshots.map { ScreenshotManifestEntry(id: $0.id, date: $0.date, fileURL: $0.fileURL) }
            let data = try JSONEncoder().encode(entries)
            try data.write(to: manifestURL, options: .atomicWrite)
        } catch {
            print("Failed to save manifest: \(error)")
        }
    }
}

struct CapturedScreenshot: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let image: PlatformImage?
    let fileURL: URL?
    let analysisResult: String?
    let analysisModel: String?

    init(
        id: UUID,
        date: Date,
        image: PlatformImage?,
        fileURL: URL? = nil,
        analysisResult: String? = nil,
        analysisModel: String? = nil
    ) {
        self.id = id
        self.date = date
        self.image = image
        self.fileURL = fileURL
        self.analysisResult = analysisResult
        self.analysisModel = analysisModel
    }

    static func == (lhs: CapturedScreenshot, rhs: CapturedScreenshot) -> Bool {
        lhs.id == rhs.id
    }
}

struct ScreenshotManifestEntry: Codable {
    let id: UUID
    let date: Date
    let fileURL: URL?
}

struct ScreenshotGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Screenshot Gallery")
            Button("Close") { dismiss() }
        }
    }
}
