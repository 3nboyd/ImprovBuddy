import Foundation
import SwiftData

enum ModelContainerFactory {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Song.self, PracticeSession.self, LibraryItem.self])
        let storeURL = storeURL()
        let config = ModelConfiguration(url: storeURL)

        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }

        purgeStore(at: storeURL)

        if let recovered = try? ModelContainer(for: schema, configurations: [config]) {
            return recovered
        }

        let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        if let inMemory = try? ModelContainer(for: schema, configurations: [memoryConfig]) {
            return inMemory
        }

        fatalError("Failed to initialize SwiftData container.")
    }

    private static func storeURL() -> URL {
        let fm = FileManager.default
        let supportRoot = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let appDirectory = supportRoot.appendingPathComponent("ImprovBuddy", isDirectory: true)
        if !fm.fileExists(atPath: appDirectory.path) {
            try? fm.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }
        return appDirectory.appendingPathComponent("ImprovBuddy.store", isDirectory: false)
    }

    private static func purgeStore(at url: URL) {
        let fm = FileManager.default
        let urls = [
            url,
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-wal")
        ]
        for candidate in urls where fm.fileExists(atPath: candidate.path) {
            try? fm.removeItem(at: candidate)
        }
    }
}
