import SwiftUI

@main
struct VlogClawStudioApp: App {
    @State private var model = StudioModel()

    var body: some Scene {
        WindowGroup {
            StudioRootView(model: model)
                .frame(minWidth: 1440, minHeight: 920)
        }
        .defaultSize(width: 1580, height: 980)
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
        }
    }
}
