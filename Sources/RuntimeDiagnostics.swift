import Foundation

struct RuntimeDiagnostics: Codable {
    let pid: Int32
    let shortcut: String?
    let shortcutRegistered: Bool
    let target: String?
    let projectorOnline: Bool?
    let lastError: String?

    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ProjectorSwitch/runtime.json")
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: Self.url, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data(("Runtime diagnostics: \(error.localizedDescription)\n").utf8))
        }
    }

    static func read() throws -> RuntimeDiagnostics {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
