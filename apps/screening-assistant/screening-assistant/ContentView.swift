import SwiftUI
import ScreeningShared

struct ContentView: View {
    @StateObject private var clientManager = WebSocketClientManager(
        serverURL: URL(string: KeyBindingsController.shared.current.webSocketURL)!
    )

    var body: some View {
        AnalysisDisplayView(clientManager: clientManager)
            .frame(minWidth: 420, minHeight: 500)
            .onAppear {
                clientManager.connect()
            }
            .onDisappear {
                clientManager.disconnect()
            }
    }
}
