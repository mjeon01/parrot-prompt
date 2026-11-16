import Foundation

/// Carbon key codes/modifiers, independent of AppKit and keyboard layout.
public struct HotkeyChord: Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & (Self.command | Self.shift | Self.option | Self.control)
    }

    public static let recommended = HotkeyChord(keyCode: 49, modifiers: control | shift)

    public enum Conflict: Equatable { case characterViewer, inputSource, system }

    public func conflict(in enabledSystemHotkeys: Set<HotkeyChord>) -> Conflict? {
        // Character Viewer is also installed by AppKit menus and may not appear
        // in CopySymbolicHotKeys. It is unsuitable for a cross-app shortcut.
        if keyCode == 49, modifiers == Self.control | Self.command { return .characterViewer }
        guard enabledSystemHotkeys.contains(self) else { return nil }
        if keyCode == 49, modifiers == Self.control || modifiers == Self.control | Self.option {
            return .inputSource
        }
        return .system
    }
}

/// Carbon delivers one HotKeyPressed per press (raw key repeats are separate).
/// Deduplicate event identity without a held latch that can get stuck if a
/// release is lost during a menu, focus change, sleep, or re-registration.
public struct HotkeyPressFilter: Sendable {
    private var latest: [UInt32: TimeInterval] = [:]
    public init() {}

    public mutating func accept(id: UInt32, timestamp: TimeInterval) -> Bool {
        guard timestamp.isFinite, latest[id].map({ timestamp > $0 }) ?? true else { return false }
        latest[id] = timestamp
        return true
    }
}
