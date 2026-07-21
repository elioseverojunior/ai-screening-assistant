import Foundation

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

public enum ImageFormat: String {
    case jpg
    case jpeg
    case png

    public var fileExtension: String { rawValue }

    public var mimeType: String {
        switch self {
        case .jpg, .jpeg: "image/jpeg"
        case .png: "image/png"
        }
    }
}

extension PlatformImage {
    public func toJPEGData(compressionQuality: Double = 0.8) -> Data? {
        #if os(macOS)
        representationData(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        #else
        self.jpegData(compressionQuality: CGFloat(compressionQuality))
        #endif
    }

    public func toPNGData() -> Data? {
        #if os(macOS)
        representationData(using: .png, properties: [:])
        #else
        self.pngData()
        #endif
    }

    public func toData(format: ImageFormat, compressionQuality: Double = 0.8) -> Data? {
        switch format {
        case .png:
            toPNGData()
        case .jpg, .jpeg:
            toJPEGData(compressionQuality: compressionQuality)
        }
    }

    #if os(macOS)
    private func representationData(using type: NSBitmapImageRep.FileType, properties: [NSBitmapImageRep.PropertyKey: Any]) -> Data? {
        if let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            return bitmapRep.representation(using: type, properties: properties)
        }
        if let tiffData = self.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData) {
            return bitmapRep.representation(using: type, properties: properties)
        }
        return nil
    }
    #endif
}
