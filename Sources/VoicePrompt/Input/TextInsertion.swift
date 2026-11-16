import AppKit
import ApplicationServices
import Carbon

@MainActor
final class TextInsertion {
    struct Target {
        let pid: pid_t
        let window: AXUIElement?
    }

    enum Result {
        case posted, permissionRequired, noTarget, targetChanged, unavailable
    }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        guard !hasPermission else { return }
        // Register once; reopening Settings must not summon the same system
        // permission alert repeatedly while TCC is still refreshing its state.
        let promptKey = "accessibilityPromptRequested"
        guard !UserDefaults.standard.bool(forKey: promptKey) else { return }
        UserDefaults.standard.set(true, forKey: promptKey)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func focusedElement(pid: pid_t) -> AXUIElement? {
        guard hasPermission else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func capture() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        if let element = focusedElement(pid: app.processIdentifier),
           attribute(element, kAXSubroleAttribute) as? String == "AXSecureTextField" { return nil }
        return Target(pid: app.processIdentifier, window: focusedWindow(pid: app.processIdentifier))
    }

    private static func focusedWindow(pid: pid_t) -> AXUIElement? {
        guard hasPermission else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let value = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func isCurrent(_ target: Target) -> Bool {
        guard hasPermission, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else { return false }
        // Browser and Electron editors recreate AX elements during dictation.
        // Keep the app/window stable, then paste at the user's current caret.
        if let window = target.window {
            guard let currentWindow = focusedWindow(pid: target.pid), CFEqual(window, currentWindow) else { return false }
        }
        if let current = focusedElement(pid: target.pid),
           attribute(current, kAXSubroleAttribute) as? String == "AXSecureTextField" { return false }
        return true
    }

    /// Reports why a paste cannot safely be requested. It never presses Enter.
    static func paste(_ text: String, into target: Target?) async -> Result {
        guard hasPermission else { return .permissionRequired }
        guard let target else { return .noTarget }
        guard !text.isEmpty, isCurrent(target) else { return .targetChanged }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return .unavailable }
        let board = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        // Materializing promised clipboard data can take time; revalidate focus.
        guard isCurrent(target) else { return .targetChanged }
        board.clearContents()
        board.setString(text, forType: .string)
        let ourChange = board.changeCount
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(900))
        if board.changeCount == ourChange {
            board.clearContents()
            let items = saved.map { data -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, value) in data { item.setData(value, forType: type) }
                return item
            }
            if !items.isEmpty { board.writeObjects(items) }
        }
        return .posted
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
