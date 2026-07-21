import XCTest
@testable import screening_assistant

final class ScreenshotsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testMakeTestImage() {
        let image = makeTestImage()
        XCTAssertNotNil(image.tiffRepresentation)
    }

    func testCaptureServiceUsesScreenCaptureService() {
        let service = MockCaptureService()
        let expectation = expectation(description: "capture completes")
        Task {
            let image = try await service.captureFullScreen()
            XCTAssertNotNil(image)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    func testStoreAddsScreenshot() {
        let store = ScreenshotStore()
        XCTAssertEqual(store.count, 0)
        store.addScreenshot(makeTestImage())
        XCTAssertEqual(store.count, 1)
    }

    func testStoreRetrievesScreenshot() {
        let store = ScreenshotStore()
        let img = makeTestImage()
        store.addScreenshot(img)
        let id = store.screenshots[0].id
        let retrieved = store.image(for: id)
        XCTAssertNotNil(retrieved)
    }

    func testStoreCountIncrements() {
        let store = ScreenshotStore()
        store.addScreenshot(makeTestImage())
        store.addScreenshot(makeTestImage())
        store.addScreenshot(makeTestImage())
        XCTAssertEqual(store.count, 3)
    }

    func testCaptureManagerCapturesAndStores() async throws {
        let service = MockCaptureService()
        let store = ScreenshotStore()
        let manager = ScreenCaptureManager(service: service, store: store)
        try await manager.captureAndStore()
        XCTAssertEqual(store.count, 1)
    }

    func testStoreWithStorageDirectory() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = ScreenshotStore(storageDirectory: tmp)
        store.saveToDisk = true
        store.addScreenshot(makeTestImage())
        XCTAssertEqual(store.count, 1)
        try? FileManager.default.removeItem(at: tmp)
    }

    func testStoreUsesSharedInstance() {
        let store = ScreenshotStore.shared
        store.addScreenshot(makeTestImage())
        XCTAssertTrue(store.count >= 1)
    }

}

private class MockCaptureService: ScreenCaptureProviding {
    func captureFullScreen() async throws -> NSImage {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.blue.set()
        NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        image.unlockFocus()
        return image
    }
}

private func makeTestImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 1, height: 1))
    image.lockFocus()
    NSColor.red.set()
    NSRect(x: 0, y: 0, width: 1, height: 1).fill()
    image.unlockFocus()
    return image
}
