import Foundation

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

extension PlatformImage {
    public func toJPEGData(compressionQuality: Double = 0.8) -> Data? {
        #if os(macOS)
        if let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        }
        if let tiffData = self.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData) {
            return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        }
        return nil
        #else
        return self.jpegData(compressionQuality: CGFloat(compressionQuality))
        #endif
    }
}
