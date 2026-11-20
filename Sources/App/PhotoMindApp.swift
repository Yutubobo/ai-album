import SwiftUI

@main
struct PhotoMindApp: App {
    @StateObject private var engine = PhotoEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .task { await engine.bootstrap() }
        }
    }
}
