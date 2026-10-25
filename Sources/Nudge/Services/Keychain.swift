import Foundation

/// Session storage for the sync sign-in.
///
/// Stored as a 0600 file in Application Support rather than the Keychain: this app is ad-hoc
/// signed, so every rebuild gets a new code identity and the Keychain would prompt for the login
/// password on each launch. The file is readable only by the current user.
enum Keychain {
    private static var dir: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let d = support.appendingPathComponent("Nudge", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func url(_ key: String) -> URL {
        dir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".secret")
    }

    static func save(_ data: Data, key: String) {
        let u = url(key)
        try? data.write(to: u, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
    }

    static func load(key: String) -> Data? {
        try? Data(contentsOf: url(key))
    }

    static func delete(key: String) {
        try? FileManager.default.removeItem(at: url(key))
    }
}
