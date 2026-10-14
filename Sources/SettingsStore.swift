import Foundation

struct AppSettings: Codable {
    var target: DisplayIdentity?
    var placement: SavedPlacement?
    var shortcut: String = "option"
}

final class SettingsStore {
    let url: URL
    private(set) var settings: AppSettings

    init(url: URL? = nil) throws {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.url = url ?? base.appendingPathComponent("ProjectorSwitch/settings.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            settings = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: self.url))
        } else {
            settings = AppSettings()
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) throws {
        var proposed = settings
        mutate(&proposed)
        let data = try JSONEncoder().encode(proposed)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Persist before a display change, so even a process crash leaves a recovery record.
        try data.write(to: url, options: .atomic)
        settings = proposed
    }
}
