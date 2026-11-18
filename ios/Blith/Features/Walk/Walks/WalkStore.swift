import BlithCore
import Foundation

/// Recorded walks on this iPhone: the finished ones, plus a checkpoint of the walk in progress
/// so an interrupted walk can be resumed or saved on the next launch.
///
/// The checkpoint is written while the phone may be locked in a pocket, so it uses
/// "complete until first unlock" protection; finished walks use the stricter complete protection.
/// Neither file goes to iCloud backup (the GPS route lives in Apple Health as well).
enum WalkStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appendingPathComponent("Walks", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        return url
    }

    private static var walksURL: URL { directory.appendingPathComponent("walks.json") }
    private static var activeURL: URL { directory.appendingPathComponent("active-walk.json") }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    // MARK: Finished walks

    static func loadWalks() -> [RecordedWalk] {
        guard let data = try? Data(contentsOf: walksURL),
              let walks = try? decoder.decode([RecordedWalk].self, from: data) else { return [] }
        return walks.sorted { $0.start > $1.start }
    }

    static func saveWalks(_ walks: [RecordedWalk]) {
        guard let data = try? encoder.encode(walks) else { return }
        try? data.write(to: walksURL, options: [.atomic, .completeFileProtection])
    }

    // MARK: Walk in progress

    struct Checkpoint: Codable {
        var walk: RecordedWalk
        var isPaused: Bool
        /// Steps over the moving stretches before the current one.
        var completedSteps: Int?
    }

    static func saveCheckpoint(_ checkpoint: Checkpoint) {
        guard let data = try? encoder.encode(checkpoint) else { return }
        try? data.write(to: activeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func loadCheckpoint() -> Checkpoint? {
        guard let data = try? Data(contentsOf: activeURL) else { return nil }
        return try? decoder.decode(Checkpoint.self, from: data)
    }

    /// Profile › Delete all Blith data. Walks already saved in Apple Health stay there.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func clearCheckpoint() {
        try? FileManager.default.removeItem(at: activeURL)
    }
}
