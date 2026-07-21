import ScreeningShared
#if os(macOS)
import AppKit
import ScreenCaptureKit
#else
import UIKit
#endif
import SwiftUI
import Combine

enum CaptureError: Error {
    case noDisplay
    case permissionDenied
    case captureFailed(Error)
    case userCancelled
}

protocol ScreenCaptureProviding {
    func captureFullScreen() async throws -> PlatformImage
    func captureArea(_ rect: CGRect) async throws -> PlatformImage
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

    func captureArea(_ rect: CGRect) async throws -> PlatformImage {
        // Capture full screen first, then crop to the selected area
        let fullImage = try await captureFullScreen()
        guard let cgImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.captureFailed(NSError(domain: "CaptureError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get CGImage"]))
        }
        
        let screenRect = NSScreen.main?.frame ?? .zero
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        
        // Convert screen coordinates to image pixel coordinates
        // Screen origin is bottom-left, image origin is top-left
        let imageRect = CGRect(
            x: rect.origin.x * scale,
            y: (screenRect.height - rect.origin.y - rect.height) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        guard let croppedCGImage = cgImage.cropping(to: imageRect) else {
            throw CaptureError.captureFailed(NSError(domain: "CaptureError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to crop image"]))
        }
        
        let croppedImage = NSImage(cgImage: croppedCGImage, size: NSSize(width: rect.width, height: rect.height))
        return croppedImage
    }
}
#else
final class ScreenCaptureService: ScreenCaptureProviding {
    func captureFullScreen() async throws -> PlatformImage {
        return PlatformImage()
    }
    
    func captureArea(_ rect: CGRect) async throws -> PlatformImage {
        return PlatformImage()
    }
}
#endif

// Area Selection Overlay
#if os(macOS)
final class AreaSelectionOverlay: NSWindow {
    static let shared = AreaSelectionOverlay()
    
    private var selectionRect: CGRect = .zero
    private var startPoint: CGPoint = .zero
    private var isSelecting = false
    private var continuation: CheckedContinuation<CGRect, Error>?
    private let overlayView = SelectionView()
    
    private override init(contentRect: CGRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: NSScreen.main?.frame ?? .zero, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        self.level = .screenSaver + 1
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = overlayView
        overlayView.delegate = self
    }
    
    func selectArea() async throws -> CGRect {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.selectionRect = .zero
            self.isSelecting = false
            self.overlayView.needsDisplay = true
            
            if let screen = NSScreen.main {
                self.setFrame(screen.frame, display: true)
            }
            self.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func cancel() {
        continuation?.resume(throwing: CaptureError.userCancelled)
        continuation = nil
        orderOut(nil)
    }
}

protocol SelectionViewDelegate: AnyObject {
    func selectionDidChange(_ rect: CGRect)
    func selectionDidComplete(_ rect: CGRect)
    func selectionWasCancelled()
}

final class SelectionView: NSView {
    weak var delegate: SelectionViewDelegate?
    private var startPoint: CGPoint = .zero
    private var currentRect: CGRect = .zero
    private var isSelecting = false
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTrackingArea()
    }
    
    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseMoved, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let trackingArea = NSTrackingArea(rect: bounds, options: [.inVisibleRect, .mouseMoved, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentRect = CGRect(origin: point, size: .zero)
        isSelecting = true
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        let point = convert(event.locationInWindow, from: nil)
        let x = min(startPoint.x, point.x)
        let y = min(startPoint.y, point.y)
        let width = abs(point.x - startPoint.x)
        let height = abs(point.y - startPoint.y)
        currentRect = CGRect(x: x, y: y, width: width, height: height)
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isSelecting else { return }
        isSelecting = false
        if currentRect.width > 10 && currentRect.height > 10 {
            delegate?.selectionDidComplete(currentRect)
        } else {
            delegate?.selectionWasCancelled()
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            delegate?.selectionWasCancelled()
        } else {
            super.keyDown(with: event)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw semi-transparent overlay
        context.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        context.fill(bounds)
        
        // Clear the selection area
        if !currentRect.isEmpty && isSelecting {
            context.clear(currentRect)
            
            // Draw selection border
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.stroke(currentRect)
            
            // Draw dimension label
            let dimText = "\(Int(currentRect.width)) x \(Int(currentRect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.black,
                .strokeWidth: -3
            ]
            let textRect = CGRect(x: currentRect.origin.x, y: currentRect.origin.y - 24, width: 120, height: 20)
            (dimText as NSString).draw(in: textRect, withAttributes: attrs)
        }
        
        // Draw instructions
        let instructionText = "Drag to select area • Esc to cancel"
        let instructionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -4
        ]
        let instructionRect = CGRect(x: 20, y: bounds.height - 60, width: bounds.width - 40, height: 40)
        (instructionText as NSString).draw(in: instructionRect, withAttributes: instructionAttrs)
    }
}

extension AreaSelectionOverlay: SelectionViewDelegate {
    func selectionDidChange(_ rect: CGRect) {
        // Update selection rect for visual feedback
    }
    
    func selectionDidComplete(_ rect: CGRect) {
        continuation?.resume(returning: rect)
        continuation = nil
        orderOut(nil)
    }
    
    func selectionWasCancelled() {
        continuation?.resume(throwing: CaptureError.userCancelled)
        continuation = nil
        orderOut(nil)
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
        let bindings = KeyBindingsController.shared.current
        let image: PlatformImage
        
        switch bindings.captureMode {
        case .fullScreen:
            image = try await service.captureFullScreen()
        case .areaSelection:
            let selectionRect = try await AreaSelectionOverlay.shared.selectArea()
            image = try await service.captureArea(selectionRect)
        }
        
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
