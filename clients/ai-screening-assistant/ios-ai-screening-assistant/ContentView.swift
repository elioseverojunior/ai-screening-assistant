//
//  ContentView.swift
//  ios-ai-screening-assistant
//
//  Created by Elio Severo Junior on 09/07/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var clientManager = WebSocketClientManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Header status bar
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(clientManager.isConnected ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(clientManager.isConnected ? "Connected to macOS Node" : "Connecting...")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
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
                .padding(.horizontal)

                if let latest = clientManager.latestAnalysis {
                    // Latest Vision Analysis Display Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.blue)
                            Text("Latest Screen Analysis")
                                .font(.headline)
                            Spacer()
                            Text(latest.model)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                        }

                        Divider()

                        ScrollView {
                            Text(latest.response)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else {
                    // Waiting state
                    VStack(spacing: 12) {
                        Image(systemName: "macbook.and.iphone")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Awaiting Screen Intelligence Stream")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Press the hotkey (⌘⌥⇧+.) on your macOS node to capture and analyze screen content.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Historical analysis log
                if !clientManager.history.isEmpty {
                    VStack(alignment: .leading) {
                        Text("History (\(clientManager.history.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

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
                                    .lineLimit(2)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Screen Intelligence")
            .onAppear {
                clientManager.connect()
            }
        }
    }
}

#Preview {
    ContentView()
}
