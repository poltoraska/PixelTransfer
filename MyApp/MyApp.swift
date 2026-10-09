import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup("PixelTransfer") { ContentView() }
            .defaultSize(width: 1160, height: 720)
            .windowToolbarStyle(.unified)
            .commands { TransferCommands() }
    }
}
