import SwiftUI

#if os(macOS)
private let systemGray6 = Color(nsColor: .textBackgroundColor)
private let systemGray5 = Color(nsColor: .controlBackgroundColor)
private let secondarySystemBackground = Color(nsColor: .windowBackgroundColor)
#else
private let systemGray6 = Color(.systemGray6)
private let systemGray5 = Color(.systemGray5)
private let secondarySystemBackground = Color(.secondarySystemBackground)
#endif

public struct AnalysisDisplayView: View {
    @ObservedObject var clientManager: WebSocketClientManager

    public init(clientManager: WebSocketClientManager) {
        self.clientManager = clientManager
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(clientManager.isConnected ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(clientManager.isConnected ? "Connected" : "Connecting...")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(systemGray6)
                .clipShape(Capsule())

                Spacer()

                if clientManager.isConnected {
                    Button("Disconnect") { clientManager.disconnect() }
                        .font(.caption)
                } else {
                    Button("Reconnect") { clientManager.connect() }
                        .font(.caption)
                }
            }

            if let latest = clientManager.latestAnalysis {
                analysisCard(latest)
            } else {
                waitingState
            }

            if !clientManager.history.isEmpty {
                historySection
            }
        }
    }

    @ViewBuilder
    private func analysisCard(_ analysis: AnalysisPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text("Latest Analysis")
                    .font(.headline)
                Spacer()
                Text(analysis.model)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
            }

            if let prompt = analysis.prompt, !prompt.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt")
                        .font(.caption).bold()
                        .foregroundColor(.secondary)
                    Text(prompt)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(systemGray5)
                .cornerRadius(8)
            }

            Divider()

            ScrollView {
                MarkdownRendererView(text: analysis.response)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(secondarySystemBackground)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var waitingState: some View {
        VStack(spacing: 12) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Awaiting Screen Intelligence Stream")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Press the hotkey on your macOS node to capture and analyze screen content.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading) {
            Text("History (\(clientManager.history.count))")
                .font(.caption)
                .foregroundColor(.secondary)

            List(clientManager.history.reversed()) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.model)
                            .font(.caption)
                            .bold()
                        Spacer()
                        Text(item.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(item.response)
                        .font(.subheadline)
                        .lineLimit(3)
                }
            }
            .listStyle(.plain)
        }
    }
}
