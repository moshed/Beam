import SwiftUI

@main
struct BeamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("", id: "hidden") {
            EmptyView()
        }
        .defaultSize(width: 0, height: 0)
    }
}
