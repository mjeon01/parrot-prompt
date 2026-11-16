enum AppRelease {
    // Compiled into the executable so an old process cannot report the version
    // of a newer Info.plist that was installed while it was still running.
    static let version = "0.3.0"
    static let build = "3"
    static let label = "v\(version) · 빌드 \(build)"
}
