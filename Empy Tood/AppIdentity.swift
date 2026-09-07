import Foundation
import Darwin

/// The single canonical identity for this app and its local data.
enum AppIdentity {
    /// Resolve the login user's home independently of sandbox-relative NSHomeDirectory.
    /// All installed and development builds use this single store.
    static var dataDirectory: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(storageDirectory, isDirectory: true)
    }
    static let displayName = "Empy Tood"
    static var storageDirectory: String {
        #if DEBUG
        // UI regressions can launch a debug build against an isolated store
        // instead of touching the person's real stickies. Keep the override
        // deliberately to a single path component so it can never redirect
        // persistence outside Application Support.
        if let override = ProcessInfo.processInfo.environment["EMPY_TOOD_STORAGE_DIRECTORY"],
           !override.isEmpty,
           !override.contains("/") {
            return override
        }
        #endif
        return "com.empy.EmpyTood"
    }
    static let keychainService = "com.empy.EmpyTood"
}
