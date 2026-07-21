import XCTest
@testable import macos_ai_screening_assistant

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("Handler is not set.")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class UploadServiceTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        session = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeTestImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.set()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        return image
    }

    func testSuccessfulUploadAndAnalyze() async throws {
        let expectedResponse = AnalysisUploadResponse(model: "llama3.2-vision", response: "Screen contains Xcode IDE", processingMs: 120.5)
        let responseData = try JSONEncoder().encode(expectedResponse)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseData)
        }

        let uploadService = ScreenCaptureUploadService(serverURL: URL(string: "http://localhost:8000/api/analyze")!, session: session)
        let testImage = makeTestImage()

        let result = try await uploadService.uploadAndAnalyze(image: testImage, prompt: "Test prompt")
        XCTAssertEqual(result.model, "llama3.2-vision")
        XCTAssertEqual(result.response, "Screen contains Xcode IDE")
        XCTAssertEqual(result.processingMs, 120.5)
    }

    func testUploadHandlesServerError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let uploadService = ScreenCaptureUploadService(serverURL: URL(string: "http://localhost:8000/api/analyze")!, session: session)
        let testImage = makeTestImage()

        do {
            _ = try await uploadService.uploadAndAnalyze(image: testImage)
            XCTFail("Expected upload to throw UploadError.invalidResponse")
        } catch let error as UploadError {
            XCTAssertEqual(error, UploadError.invalidResponse(500))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
