import AppKit
import Carbon
import VoicePromptCore

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    static let standard = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | shiftKey), label: "⌃⇧Space")
    var chord: HotkeyChord { HotkeyChord(keyCode: keyCode, modifiers: modifiers) }

    @MainActor var conflictReason: String? {
        switch chord.conflict(in: Hotkeys.systemShortcuts()) {
        case .characterViewer: return "macOS 이모지·기호 창 단축키와 겹칩니다."
        case .inputSource: return "macOS 입력 언어 전환 단축키와 겹칩니다."
        case .system: return "사용 중인 macOS 시스템 단축키와 겹칩니다."
        case nil: return nil
        }
    }
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
    private var pressFilter = HotkeyPressFilter()
    private var nextID: UInt32 = 10
    private(set) var toggleID: UInt32?
    private(set) var registeredShortcut: Shortcut?
    private(set) var registrationError = ""
    private var handlerStatus: OSStatus = OSStatus(eventNotHandledErr)
    nonisolated static let signature: OSType = 0x5650524D
    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?

    init() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        handlerStatus = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context, Thread.isMainThread else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue()
            // Process synchronously, preserving the order of Carbon events.
            return MainActor.assumeIsolated { owner.receive(event) }
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: Shortcut) -> Bool {
        registrationError = ""
        guard handlerStatus == noErr, handler != nil else {
            registrationError = "단축키 수신을 시작하지 못했습니다 (\(handlerStatus)). 앱을 다시 실행해 주세요."
            return false
        }
        if let reason = shortcut.conflictReason {
            registrationError = reason + " 다른 조합을 선택해 주세요."
            return false
        }
        if registeredShortcut?.chord == shortcut.chord, hotkey != nil { return true }
        var replacement: EventHotKeyRef?
        let id = nextID; nextID += 1
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: id), GetEventDispatcherTarget(),
            OptionBits(kEventHotKeyExclusive), &replacement)
        guard status == noErr, let replacement else {
            registrationError = status == OSStatus(eventHotKeyExistsErr)
                ? "다른 앱에서 사용 중인 단축키입니다. 다른 조합을 선택해 주세요."
                : "단축키를 등록하지 못했습니다 (\(status)). 다른 조합을 선택해 주세요."
            return false
        }
        // Keep the working shortcut until the replacement has succeeded.
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = replacement; toggleID = id; registeredShortcut = shortcut
        pressFilter = HotkeyPressFilter()
        return true
    }

    func enableEscape(_ enabled: Bool) {
        if let escape { UnregisterEventHotKey(escape); self.escape = nil }
        if enabled {
            RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: Self.signature, id: 2),
                                GetEventDispatcherTarget(), 0, &escape)
        }
    }

    private func receive(_ event: EventRef) -> OSStatus {
        guard GetEventClass(event) == OSType(kEventClassKeyboard) else { return OSStatus(eventNotHandledErr) }
        var key = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
        guard status == noErr else { return status }
        guard key.signature == Self.signature,
              key.id == toggleID || (key.id == 2 && escape != nil) else { return OSStatus(eventNotHandledErr) }
        let kind = GetEventKind(event)
        if kind == kEventHotKeyReleased { return noErr }
        guard kind == kEventHotKeyPressed else { return OSStatus(eventNotHandledErr) }
        guard pressFilter.accept(id: key.id, timestamp: GetEventTime(event)) else { return noErr }
        if key.id == toggleID { onToggle?() } else { onCancel?() }
        return noErr
    }

    static func systemShortcuts() -> Set<HotkeyChord> {
        var result: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&result) == noErr,
              let entries = result?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return Set(entries.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? UInt32,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? UInt32 else { return nil }
            return HotkeyChord(keyCode: code, modifiers: modifiers)
        })
    }

    func shutdown() {
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        if let escape { UnregisterEventHotKey(escape); self.escape = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        toggleID = nil; registeredShortcut = nil
    }
}
