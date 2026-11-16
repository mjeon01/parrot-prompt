import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    static let standard = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥Space")
    static func from(_ event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty,
              event.keyCode != kVK_Escape else { return nil }
        var modifiers: UInt32 = 0
        var prefix = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); prefix += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); prefix += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); prefix += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); prefix += "⌘" }
        let key = event.keyCode == kVK_Space ? "Space" : (event.charactersIgnoringModifiers?.uppercased() ?? "")
        guard !key.isEmpty else { return nil }
        return Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: prefix + key)
    }
}

@MainActor
final class Hotkeys {
    private var hotkey: EventHotKeyRef?
    private var escape: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var held = Set<UInt32>()
    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?

    init() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            let id = key.id
            let pressed = GetEventKind(event) == kEventHotKeyPressed
            let owner = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in owner.receive(id, pressed: pressed) }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: Shortcut) -> Bool {
        var replacement: EventHotKeyRef?
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        held.removeAll()
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: 0x5650524D, id: 1), GetApplicationEventTarget(), 0, &replacement)
        hotkey = replacement
        return status == noErr
    }

    func enableEscape(_ enabled: Bool) {
        if let escape { UnregisterEventHotKey(escape); self.escape = nil }
        held.remove(2)
        if enabled {
            RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x5650524D, id: 2),
                                GetApplicationEventTarget(), 0, &escape)
        }
    }

    private func receive(_ id: UInt32, pressed: Bool) {
        if !pressed { held.remove(id); return }
        guard held.insert(id).inserted else { return }
        if id == 1 { onToggle?() }
        if id == 2 { onCancel?() }
    }
}
