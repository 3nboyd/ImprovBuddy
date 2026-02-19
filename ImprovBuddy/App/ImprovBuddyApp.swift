import SwiftData
import SwiftUI

@main
struct ImprovBuddyApp: App {
    @StateObject private var appEnvironment = AppEnvironment()
    @StateObject private var services = ServiceContainer()
    private let modelContainer = ModelContainerFactory.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appEnvironment)
                .environmentObject(services)
                .preferredColorScheme(.dark)
                .tint(appEnvironment.accentColor)
        }
        .modelContainer(modelContainer)
    }
}
