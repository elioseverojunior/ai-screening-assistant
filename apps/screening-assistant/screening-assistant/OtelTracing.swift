import Foundation

// MARK: - OTel data types

struct SpanRef {
    let traceId: String
    let spanId: String
}

enum SpanStatus {
    case ok
    case error(String)
    case unset
}

private struct RawSpan {
    let traceId: String
    let spanId: String
    let parentSpanId: String?
    let name: String
    let kind: Int
    let startTime: Date
    var endTime: Date?
    var attributes: [(String, String)]
    var status: SpanStatus
}

private struct RawLog {
    let timestamp: Date
    let severityText: String
    let severityNumber: Int
    let body: String
    let attributes: [(String, String)]
}

// MARK: - OTel Tracer

final class OtelTracer {
    static let shared = OtelTracer()

    private let collectorURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let queue = DispatchQueue(label: "otel-tracer", qos: .utility)

    private let serviceName: String
    private let resourceAttrs: [(String, String)]

    private var pendingSpans: [RawSpan] = []
    private var pendingLogs: [RawLog] = []
    private var flushTimer: DispatchSourceTimer?
    private var isRunning = false

    private init() {
        let env = ProcessInfo.processInfo.environment
        let host = env["OTEL_COLLECTOR_HOST"] ?? "localhost"
        let port = env["OTEL_COLLECTOR_HTTP_PORT"] ?? "4318"
        collectorURL = URL(string: "http://\(host):\(port)")!

        serviceName = "screening-assistant"

        let defaultAttrs: [(String, String)] = [
            ("service.name", serviceName),
            ("telemetry.sdk.name", "opentelemetry"),
            ("telemetry.sdk.language", "swift"),
            ("telemetry.sdk.version", "1.0.0"),
            ("deployment.environment", env["DEPLOYMENT_ENVIRONMENT"] ?? "development")
        ]
        resourceAttrs = defaultAttrs

        session = URLSession(configuration: .ephemeral)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        startFlushTimer()
    }

    // MARK: - Span lifecycle

    func startSpan(_ name: String, parent: SpanRef? = nil, attributes: [String: String] = [:]) -> SpanRef {
        let traceId = parent?.traceId ?? generateHexId(16)
        let spanId = generateHexId(8)
        let attrs = attributes.map { ($0.key, $0.value) }

        let span = RawSpan(
            traceId: traceId,
            spanId: spanId,
            parentSpanId: parent?.spanId,
            name: name,
            kind: 1,
            startTime: Date(),
            endTime: nil,
            attributes: attrs,
            status: .unset
        )

        queue.async { [weak self] in
            self?.pendingSpans.append(span)
        }
        return SpanRef(traceId: traceId, spanId: spanId)
    }

    func endSpan(_ ref: SpanRef, status: SpanStatus = .ok) {
        queue.async { [weak self] in
            guard let self else { return }
            if let idx = self.pendingSpans.firstIndex(where: { $0.spanId == ref.spanId }) {
                var span = self.pendingSpans[idx]
                span.endTime = Date()
                span.status = status
                self.pendingSpans[idx] = span
            }
        }
    }

    // MARK: - Logging

    func log(_ message: String, severity: String = "INFO", severityNumber: Int = 9, attributes: [String: String] = [:]) {
        let log = RawLog(
            timestamp: Date(),
            severityText: severity,
            severityNumber: severityNumber,
            body: message,
            attributes: attributes.map { ($0.key, $0.value) }
        )
        queue.async { [weak self] in
            self?.pendingLogs.append(log)
        }
    }

    // MARK: - Export

    private func startFlushTimer() {
        isRunning = true
        flushTimer = DispatchSource.makeTimerSource(queue: queue)
        flushTimer?.schedule(deadline: .now() + 5, repeating: 5, leeway: .seconds(1))
        flushTimer?.setEventHandler { [weak self] in
            self?.flush()
        }
        flushTimer?.resume()
    }

    private func flush() {
        let spans = pendingSpans
        let logs = pendingLogs
        pendingSpans = []
        pendingLogs = []

        if !spans.isEmpty {
            sendTraces(spans)
        }
        if !logs.isEmpty {
            sendLogs(logs)
        }
    }

    private func sendTraces(_ spans: [RawSpan]) {
        let completed = spans.compactMap { span -> [String: Any]? in
            guard let end = span.endTime else { return nil }
            return [
                "traceId": span.traceId,
                "spanId": span.spanId,
                "parentSpanId": span.parentSpanId as Any,
                "name": span.name,
                "kind": span.kind,
                "startTimeUnixNano": otlpTimestamp(span.startTime),
                "endTimeUnixNano": otlpTimestamp(end),
                "attributes": span.attributes.map { ["key": $0.0, "value": ["stringValue": $0.1]] },
                "status": statusJSON(span.status)
            ]
        }
        guard !completed.isEmpty else { return }

        let body: [String: Any] = [
            "resourceSpans": [
                [
                    "resource": [
                        "attributes": resourceAttrs.map { ["key": $0.0, "value": ["stringValue": $0.1]] }
                    ],
                    "scopeSpans": [
                        [
                            "scope": ["name": serviceName],
                            "spans": completed
                        ]
                    ]
                ]
            ]
        ]
        postJSON(body, to: "/v1/traces")
    }

    private func sendLogs(_ logs: [RawLog]) {
        let records = logs.map { log -> [String: Any] in
            [
                "timeUnixNano": otlpTimestamp(log.timestamp),
                "severityText": log.severityText,
                "severityNumber": log.severityNumber,
                "body": ["stringValue": log.body],
                "attributes": log.attributes.map { ["key": $0.0, "value": ["stringValue": $0.1]] }
            ]
        }

        let body: [String: Any] = [
            "resourceLogs": [
                [
                    "resource": [
                        "attributes": resourceAttrs.map { ["key": $0.0, "value": ["stringValue": $0.1]] }
                    ],
                    "scopeLogs": [
                        [
                            "scope": ["name": serviceName],
                            "logRecords": records
                        ]
                    ]
                ]
            ]
        ]
        postJSON(body, to: "/v1/logs")
    }

    private func postJSON(_ body: [String: Any], to path: String) {
        guard let url = URL(string: path, relativeTo: collectorURL),
              let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        session.dataTask(with: req) { _, res, err in
            if let err = err {
                NSLog("[OTel] Export failed: \(err.localizedDescription)")
                return
            }
            if let http = res as? HTTPURLResponse, http.statusCode >= 300 {
                NSLog("[OTel] Export returned \(http.statusCode)")
            }
        }.resume()
    }

    // MARK: - Helpers

    private func generateHexId(_ bytes: Int) -> String {
        (0..<bytes).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    private func otlpTimestamp(_ date: Date) -> UInt64 {
        UInt64(date.timeIntervalSince1970 * 1_000_000_000)
    }

    private func statusJSON(_ status: SpanStatus) -> [String: Any] {
        switch status {
        case .ok:
            return ["code": 1]
        case .error(let desc):
            return ["code": 2, "message": desc]
        case .unset:
            return ["code": 0]
        }
    }
}
