import AppKit
import Carbon
import VoicePromptCore

/// Exercises the installed Carbon handler in this process. Does not synthesize
/// system keyboard input, record audio, paste text, or change saved shortcuts.
enum HotkeyVerification {
    struct Failure: LocalizedError { let errorDescription: String? }

    @MainActor static func run() throws {
        // Initialize the same AppKit event environment as the GUI app, without
        // showing a window or taking focus from the user's current application.
        NSApplication.shared.setActivationPolicy(.prohibited)
        var checks = 0
        func require(_ condition: Bool, _ detail: String) throws {
            guard condition else { throw Failure(errorDescription: detail) }
            checks += 1
        }

        let system = Hotkeys.systemShortcuts()
        print("Enabled system shortcuts: \(system.count)")
        print("Recommended \(Shortcut.standard.label): \(Shortcut.standard.conflictReason ?? "no system conflict")")
        let preferences = Bundle.main.bundleIdentifier == "local.voiceprompt.mac"
            ? UserDefaults.standard : UserDefaults(suiteName: "local.voiceprompt.mac")
        if let data = preferences?.data(forKey: "shortcut"),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            print("Saved \(saved.label): \(saved.conflictReason ?? "no system conflict")")
        }
        try require(Shortcut.standard.chord == .recommended, "UI and core recommended shortcuts differ")

        // Use a dedicated uncommon chord, so the running app retains its keys.
        let testShortcut = Shortcut(keyCode: UInt32(kVK_F18), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "test F18")
        let driver = Hotkeys()
        let contender = Hotkeys()
        defer { driver.shutdown(); contender.shutdown() }
        var toggles = 0
        var cancellations = 0
        driver.onToggle = { toggles += 1 }
        driver.onCancel = { cancellations += 1 }
        try require(driver.register(testShortcut), "Carbon registration: \(driver.registrationError)")
        guard let id = driver.toggleID else { throw Failure(errorDescription: "Missing registration ID") }

        func send(_ kind: UInt32, id: UInt32, time: Double, signature: OSType = Hotkeys.signature) throws -> OSStatus {
            var created: EventRef?
            let status = CreateEvent(nil, OSType(kEventClassKeyboard), kind, time,
                                     EventAttributes(kEventAttributeUserEvent), &created)
            guard status == noErr, let event = created else { throw Failure(errorDescription: "CreateEvent: \(status)") }
            defer { ReleaseEvent(event) }
            var key = EventHotKeyID(signature: signature, id: id)
            let parameter = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                              MemoryLayout<EventHotKeyID>.size, &key)
            guard parameter == noErr else { throw Failure(errorDescription: "SetEventParameter: \(parameter)") }
            return SendEventToEventTarget(event, GetEventDispatcherTarget())
        }

        try require(try send(UInt32(kEventHotKeyPressed), id: id, time: 1) == noErr && toggles == 1, "First press did not arrive synchronously")
        _ = try send(UInt32(kEventHotKeyPressed), id: id, time: 1.1)
        try require(toggles == 2, "Second press was lost when the release was omitted")
        _ = try send(UInt32(kEventHotKeyPressed), id: id, time: 1.1)
        try require(toggles == 2, "Duplicate event toggled twice")
        _ = try send(UInt32(kEventHotKeyReleased), id: id, time: 1.2)
        try require(toggles == 2, "Release must not toggle")
        _ = try send(UInt32(kEventHotKeyPressed), id: id, time: 1.3)
        try require(toggles == 3, "Press following a release was lost")
        for index in 0..<100 {
            _ = try send(UInt32(kEventHotKeyPressed), id: id, time: 2 + Double(index) * 0.05)
        }
        try require(toggles == 103, "Not all 100 successive events arrived")
        _ = try send(UInt32(kEventHotKeyPressed), id: id, time: 20, signature: 0x54455354)
        _ = try send(UInt32(kEventHotKeyPressed), id: id + 100, time: 21)
        try require(toggles == 103, "Foreign or stale events triggered dictation")

        try require(!contender.register(testShortcut), "Duplicate Carbon registration was accepted")
        let emoji = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | cmdKey), label: "⌃⌘Space")
        try require(!driver.register(emoji), "Reserved emoji shortcut was accepted")
        try require(driver.toggleID == id && driver.registeredShortcut == testShortcut, "Failed replacement discarded the working shortcut")
        _ = try send(UInt32(kEventHotKeyPressed), id: id, time: 23)
        try require(toggles == 104, "Working shortcut stopped after a failed replacement")
        driver.enableEscape(true)
        _ = try send(UInt32(kEventHotKeyPressed), id: 2, time: 24)
        try require(cancellations == 1, "Cancel shortcut did not arrive")
        driver.enableEscape(false)
        _ = try send(UInt32(kEventHotKeyPressed), id: 2, time: 25)
        try require(cancellations == 1, "Disabled cancel shortcut was accepted")
        print("Passed \(checks) Carbon integration checks; 100/100 consecutive presses delivered.")
        print("Physical keyboard delivery must be checked with Settings → 단축키 검사.")
    }
}
