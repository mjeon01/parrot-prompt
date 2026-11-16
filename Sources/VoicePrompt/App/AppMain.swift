import AppKit
import SwiftUI
import Combine
import WhisperKit
import VoicePromptCore

final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var item: NSStatusItem!
    private var settings: NSWindow?
    private var panel: PreviewPanel?
    private var greeting: PreviewPanel?
    private var observation: AnyCancellable?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuIcon
        item.button?.toolTip = "VoicePrompt \(AppRelease.label) · 로컬 음성 입력"
        let menu = NSMenu()
        let versionItem = NSMenuItem(title: "VoicePrompt \(AppRelease.label)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        add("녹음 시작 / 완료", action: #selector(toggle), to: menu)
        add("전사 미리보기", action: #selector(showPreview), to: menu)
        menu.addItem(.separator())
        add("설정…", action: #selector(showSettings), to: menu)
        menu.addItem(.separator())
        add("VoicePrompt 종료", action: #selector(quit), to: menu)
        item.menu = menu
        model.showPanel = { [weak self] in self?.showPreview() }
        model.hidePanel = { [weak self] in self?.panel?.orderOut(nil) }
        model.showSettings = { [weak self] in self?.showSettings() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refreshPermissionStatus() }
        }
        observation = model.$phase.sink { [weak self] phase in
            self?.item.button?.image = phase == .recording
                ? NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: phase.title) : Self.menuIcon
            self?.item.button?.contentTintColor = phase == .recording ? .systemRed : nil
        }
        if SpeechEngine.installedModel != nil { model.prepare(download: false) }
        if SpeechEngine.installedModel == nil || !model.microphoneGranted || !model.accessibilityGranted
            || !model.shortcutNotice.isEmpty || !model.shortcutError.isEmpty { showSettings() }
        showGreeting()
        if CommandLine.arguments.contains("--preview-demo") {
            model.phase = .recording
            model.transcript = TranscriptSnapshot(confirmed: "오늘 회의에서 나온 내용을 정리해 줘.", draft: "SwiftUI로 만든 앱에 실시간 음성 입력 기능을")
            model.elapsed = 14; model.level = 0.6
            showPreview()
        }
    }

    private static let menuIcon: NSImage? = {
        let image = Bundle.main.image(forResource: "MenuIcon") ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        image?.isTemplate = true; image?.size = NSSize(width: 18, height: 18)
        image?.accessibilityDescription = "VoicePrompt"
        return image
    }()

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self; menu.addItem(entry)
    }
    @objc func toggle() { model.toggle() }
    @objc func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 730),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "VoicePrompt v\(AppRelease.version)"; window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.minSize = NSSize(width: 580, height: 650); window.isReleasedWhenClosed = false
            window.delegate = self; window.center(); settings = window
        }
        model.refreshPermissions(); settings?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showPreview() {
        greeting?.orderOut(nil); greeting = nil
        if panel == nil {
            let view = NSHostingView(rootView: DictationView(model: model))
            let window = PreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 102),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.contentView = view
            window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = true
            window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.hidesOnDeactivate = false; window.isMovableByWindowBackground = true; panel = window
        }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame { panel?.setFrameOrigin(NSPoint(x: frame.midX - 180, y: frame.minY + 30)) }
        panel?.orderFrontRegardless()
    }
    private func showGreeting() {
        let message = SpeechEngine.installedModel == nil
            ? "안녕하세요! 설정에서 음성 모델을 준비하면 제가 받아 적을게요."
            : "안녕하세요! \(model.shortcut.label)를 누르고 말하면 제가 그대로 받아 적을게요."
        let window = PreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 290, height: 104),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let state = Greeting(message: message)
        state.onFinish = { [weak self, weak window] in
            window?.orderOut(nil)
            if self?.greeting === window { self?.greeting = nil }
        }
        window.contentView = NSHostingView(rootView: GreetingView(greeting: state))
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
        window.level = .floating; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: frame.midX - 145, y: frame.minY + 30))
        }
        window.orderFrontRegardless(); greeting = window
        state.start()
    }

    func windowWillClose(_ notification: Notification) { model.endShortcutCapture() }
    @objc func quit() { model.capture.clear(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { model.capture.clear() }
}

@main
enum AppMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--version") {
            print("VoicePrompt \(AppRelease.version) (build \(AppRelease.build))")
            return
        }
        if CommandLine.arguments.contains("--check-hotkeys") {
            do { try HotkeyVerification.run(); exit(0) }
            catch { fputs("Hotkey verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--render-ui"), flag + 1 < CommandLine.arguments.count {
            do { try Verification.renderViews(to: CommandLine.arguments[flag + 1]); exit(0) }
            catch { fputs("Render failed: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--download-model") || CommandLine.arguments.contains("--transcribe-file") || CommandLine.arguments.contains("--stream-file") {
            Task {
                do {
                    let engine = SpeechEngine()
                    try await engine.prepare(allowDownload: CommandLine.arguments.contains("--download-model")) { progress, status in
                        if let progress { print("\(Int(progress * 100))% \(status)") } else { print(status) }
                    }
                    if let flag = CommandLine.arguments.firstIndex(of: "--transcribe-file"), flag + 1 < CommandLine.arguments.count {
                        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: CommandLine.arguments[flag + 1])
                        let start = Date()
                        let results = try await engine.transcribe(samples)
                        print(TechnicalVocabulary.standard.normalize(TranscriptAccumulator.join(results.map(\.text))))
                        print(String(format: "Transcription: %.2fs; audio: %.2fs", Date().timeIntervalSince(start), Double(samples.count) / 16000))
                    }
                    if let flag = CommandLine.arguments.firstIndex(of: "--stream-file"), flag + 1 < CommandLine.arguments.count {
                        try await Verification.streamFile(CommandLine.arguments[flag + 1], engine: engine)
                    }
                    exit(0)
                } catch { fputs("VoicePrompt: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            RunLoop.main.run(); return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
