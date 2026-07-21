import AppKit
import SwiftUI
import ScreenCaptureKit

enum CaptureError: Error {
    case noDisplay
    case permissionDenied
    case captureFailed(Error)
}

protocol ScreenCaptureProviding {
    func captureFullScreen() async throws -> NSImage
}

final class ScreenCaptureService: ScreenCaptureProviding {
    func captureFullScreen() async throws -> NSImage {
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

final class ScreenCaptureManager {
    private let service: ScreenCaptureProviding
    let store: ScreenshotStore

    init(service: ScreenCaptureProviding = ScreenCaptureService(), store: ScreenshotStore = ScreenshotStore.shared) {
        self.service = service
        self.store = store
    }

    func captureAndStore() async throws {
        let image = try await service.captureFullScreen()
        store.addScreenshot(image)
    }
}

final class ScreenshotStore: NSObject {
    static let shared = ScreenshotStore(storageDirectory: defaultStorageDirectory)

    private static var defaultStorageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "br.eti.elio.macos-ai-screening-assistant"
        let dir = appSupport.appendingPathComponent("\(bundleID)/screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private(set) var screenshots: [CapturedScreenshot] = []
    var saveToDisk: Bool = true {
        didSet { saveManifest() }
    }
    private let ioQueue = DispatchQueue(label: "screenshot-store", qos: .utility)
    let storageDirectory: URL?
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

    func addScreenshot(_ image: NSImage) {
        let fileURL: URL?
        if saveToDisk, let storageDirectory {
            let fileName = "screenshot_\(UUID().uuidString).tiff"
            fileURL = storageDirectory.appendingPathComponent(fileName)
            if let tiffData = image.tiffRepresentation {
                try? tiffData.write(to: fileURL!)
            }
        } else {
            fileURL = nil
        }
        let screenshot = CapturedScreenshot(id: UUID(), date: Date(), image: image, fileURL: fileURL)
        screenshots.append(screenshot)
        saveManifest()
    }

    func image(for id: UUID) -> NSImage? {
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
    let image: NSImage?
    let fileURL: URL?

    init(id: UUID, date: Date, image: NSImage?, fileURL: URL? = nil) {
        self.id = id
        self.date = date
        self.image = image
        self.fileURL = fileURL
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
