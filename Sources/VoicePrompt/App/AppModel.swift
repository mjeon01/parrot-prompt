import AppKit
import AVFoundation
import Combine
import WhisperKit
import VoicePromptCore

enum DictationPhase: Equatable {
    case idle, starting, recording, finishing, inserting, complete, recoverable, failed, cancelling
    var busy: Bool { [.starting, .recording, .finishing, .inserting, .cancelling].contains(self) }
    var title: String {
        switch self {
        case .idle: return "말할 준비가 됐어요"
        case .starting: return "마이크 준비 중"
        case .recording: return "듣고 있어요"
        case .finishing: return "마지막 문장 처리 중"
        case .inserting: return "입력창에 넣고 있어요"
        case .complete: return "붙여넣기를 요청했어요"
        case .recoverable: return "전사한 내용을 복사해 주세요"
        case .failed: return "잠시 확인해 주세요"
        case .cancelling: return "취소 중"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var phase: DictationPhase = .idle
    @Published var transcript = TranscriptSnapshot()
    @Published var elapsed: Double = 0
    @Published var level: Float = 0
    @Published var message = ""
    @Published var modelReady = false
    @Published var preparing = false
    @Published var preparationText = "처음 한 번 모델을 다운로드해 주세요."
    @Published var preparationProgress: Double? = 0
    @Published var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var accessibilityGranted = TextInsertion.hasPermission
    @Published var devices: [AudioDevice] = []
    @Published var microphoneID: UInt32 = UInt32(UserDefaults.standard.integer(forKey: "microphoneID")) {
        didSet { UserDefaults.standard.set(Int(microphoneID), forKey: "microphoneID") }
    }
    @Published var shortcut: Shortcut = .standard
    @Published var shortcutError = ""
    @Published var shortcutNotice = ""
    @Published var shortcutFeedback = ""
    @Published var capturingShortcut = false
    @Published var testingShortcut = false
    @Published var shortcutTestCount = 0
    @Published var previewLagging = false
    @Published var finalizationSeconds: Double?
    @Published var technicalVocabularyEnabled = UserDefaults.standard.object(forKey: "technicalVocabularyEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(technicalVocabularyEnabled, forKey: "technicalVocabularyEnabled") }
    }
    @Published var customVocabulary = UserDefaults.standard.string(forKey: "customVocabulary") ?? "" {
        didSet { UserDefaults.standard.set(customVocabulary, forKey: "customVocabulary") }
    }

    let engine = SpeechEngine()
    let capture = AudioCapture()
    let hotkeys = Hotkeys()
    var showPanel: (() -> Void)?
    var hidePanel: (() -> Void)?
    var showSettings: (() -> Void)?
    private var task: Task<Void, Never>?
    private var session = SessionToken()
    private var target: TextInsertion.Target?
    private var timer: Timer?
    private var started = Date()
    private var lastPreview = Date()
    private var activeDecode: UUID?
    private var livePreview = LivePreview()
    private var shortcutMonitor: Any?

    init(registerHotkeys: Bool = true) {
        if let data = UserDefaults.standard.data(forKey: "shortcut"),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data) { shortcut = saved }
        if registerHotkeys {
            if let reason = shortcut.conflictReason {
                let previous = shortcut
                if hotkeys.register(.standard) {
                    shortcut = .standard
                    UserDefaults.standard.set(try? JSONEncoder().encode(previous), forKey: "shortcutBeforeConflictRepair")
                    UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut")
                    shortcutNotice = "\(previous.label)는 \(reason) \(shortcut.label)로 바꿨어요."
                } else { shortcutError = reason + " " + hotkeys.registrationError }
            } else if !hotkeys.register(shortcut) { shortcutError = hotkeys.registrationError }
        }
        hotkeys.onToggle = { [weak self] in self?.receiveShortcut() }
        hotkeys.onCancel = { [weak self] in self?.cancel() }
        refreshPermissions()
    }

    func refreshPermissions() {
        refreshPermissionStatus()
        devices = AudioProcessor.getAudioDevices()
    }

    func refreshPermissionStatus() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let access = TextInsertion.hasPermission
        if microphoneGranted != mic { microphoneGranted = mic }
        if accessibilityGranted != access { accessibilityGranted = access }
    }

    func requestMicrophone() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refreshPermissions()
            if !microphoneGranted { openPrivacy("Privacy_Microphone") }
        }
    }

    func openPrivacy(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") { NSWorkspace.shared.open(url) }
    }

    func prepare(download: Bool) {
        guard !preparing, !modelReady else { return }
        preparing = true
        Task { [self] in
            do {
                try await engine.prepare(allowDownload: download) { [weak self] progress, text in
                    Task { @MainActor in self?.preparationProgress = progress; self?.preparationText = text }
                }
                modelReady = true; preparationText = "준비 완료 · 인터넷 없이 사용할 수 있어요"
            } catch {
                preparationText = "모델 준비 실패: \(error.localizedDescription)"
            }
            preparing = false
        }
    }

    func toggle() {
        guard !capturingShortcut else { return }
        testingShortcut = false
        if phase == .recording {
            capture.stop(); phase = .finishing; level = 0
            return
        }
        guard !phase.busy else { return }
        guard modelReady else {
            preparationText = preparing ? "모델을 준비하고 있어요. 완료 후 단축키를 다시 눌러 주세요." : "음성 모델 준비가 필요해요. 다운로드 또는 다시 준비를 눌러 주세요."
            if !preparing && SpeechEngine.installedModel != nil { prepare(download: false) }
            showSettings?(); return
        }
        refreshPermissions()
        guard microphoneGranted else { showSettings?(); requestMicrophone(); return }
        let token = session.invalidate()
        target = TextInsertion.capture()
        transcript = TranscriptSnapshot(); livePreview = LivePreview()
        message = ""; elapsed = 0; finalizationSeconds = nil
        phase = .starting
        showPanel?(); hotkeys.enableEscape(true)
        task = Task { await run(token) }
    }

    private func run(_ token: UUID) async {
        var accumulator = TranscriptAccumulator()
        let vocabulary = TechnicalVocabulary(enabled: technicalVocabularyEnabled, customTerms: customVocabulary)
        do {
            if microphoneID != 0 && !devices.contains(where: { $0.id == microphoneID }) { throw AudioCapture.CaptureError.deviceUnavailable }
            try capture.start(deviceID: microphoneID == 0 ? nil : microphoneID)
            started = Date(); lastPreview = started; phase = .recording
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            var lastDecodedCount = 0
            var lastSignalCount = 0
            while phase == .recording && session.accepts(token) {
                try Task.checkCancellation()
                let count = capture.count
                // Start the next pass as soon as a little new audio exists, so
                // passes run back to back and the preview tracks speech closely.
                if count - lastDecodedCount < 4_800 {
                    try await Task.sleep(for: .milliseconds(100)); continue
                }
                let newAudio = capture.snapshot(from: lastDecodedCount).samples
                if AudioGate.hasSignal(newAudio) { lastSignalCount = count }
                if count - lastSignalCount > 48_000 {
                    lastDecodedCount = count
                    lastPreview = Date()
                    continue
                }
                let offset = accumulator.confirmedEnd
                let audio = capture.snapshot(from: Int(offset * 16000)).samples
                lastDecodedCount = count
                let decodeID = UUID()
                activeDecode = decodeID
                let prefix = accumulator.snapshot.confirmed
                let segments = try await engine.transcribe(audio, interim: true, vocabulary: vocabulary) { [weak self] partial in
                    Task { @MainActor in
                        guard let self, self.session.accepts(token), self.activeDecode == decodeID,
                              self.phase == .recording || self.phase == .finishing else { return }
                        if self.livePreview.acceptPartial(TranscriptSnapshot(draft: vocabulary.normalize(TranscriptSnapshot(confirmed: prefix, draft: partial).text))) {
                            self.lastPreview = Date()
                        }
                    }
                }
                guard session.accepts(token) else { return }
                activeDecode = nil
                accumulator.update(segments, offset: offset, duration: Float(audio.count) / 16000, final: false)
                livePreview.settle(TranscriptSnapshot(draft: vocabulary.normalize(accumulator.snapshot.text)))
                publishPreview(); lastPreview = Date()
            }
            guard session.accepts(token) else { return }
            timer?.invalidate(); timer = nil
            let finishStart = Date()
            let offset = accumulator.confirmedEnd
            let remaining = capture.snapshot(from: Int(offset * 16000)).samples
            let segments = try await engine.transcribe(remaining, vocabulary: vocabulary)
            guard session.accepts(token) else { return }
            accumulator.update(segments, offset: offset, duration: Float(remaining.count) / 16000, final: true)
            livePreview.settle(TranscriptSnapshot(confirmed: vocabulary.normalize(accumulator.snapshot.text)), final: true)
            publishPreview()
            capture.clear(); level = 0; previewLagging = false
            finalizationSeconds = Date().timeIntervalSince(finishStart)
            if transcript.text.isEmpty {
                phase = .recoverable; message = "음성이 감지되지 않았어요. 마이크와 입력 음량을 확인해 주세요."
            } else {
                phase = .inserting
                hotkeys.enableEscape(false)
                let result = await TextInsertion.paste(transcript.text, into: target)
                guard session.accepts(token) else { return }
                switch result {
                case .posted:
                    phase = .complete; message = "커서 위치에 입력했어요. 내용을 확인한 뒤 직접 전송하세요."
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        if session.accepts(token), phase == .complete { hidePanel?() }
                    }
                case .permissionRequired:
                    accessibilityGranted = false; phase = .recoverable
                    message = "자동 입력을 사용하려면 손쉬운 사용에서 VoicePrompt를 허용해 주세요."
                case .noTarget:
                    phase = .recoverable; message = "시작할 때 입력할 창을 찾지 못했어요. 이번 결과는 복사해 주세요."
                case .targetChanged:
                    phase = .recoverable; message = "녹음 중 입력창이 바뀌었어요. 원래 입력창을 유지하면 자동으로 입력됩니다."
                case .unavailable:
                    phase = .recoverable; message = "자동 입력 요청에 실패했어요. 이번 결과는 복사해 주세요."
                }
            }
        } catch {
            guard session.accepts(token) else { return }
            phase = .failed; message = error.localizedDescription
            capture.clear()
        }
        if session.accepts(token) {
            timer?.invalidate(); timer = nil; hotkeys.enableEscape(false); level = 0
            task = nil; target = nil
        }
    }

    private func tick() {
        guard phase == .recording || phase == .finishing else { return }
        publishPreview()
        if phase == .recording {
            let seconds = floor(Date().timeIntervalSince(started))
            if elapsed != seconds { elapsed = seconds }
            let audio = capture.snapshot(from: capture.count)
            let nextLevel = level * 0.65 + audio.level * 0.35
            if abs(nextLevel - level) > 0.01 { level = nextLevel }
            if Date().timeIntervalSince(audio.lastBuffer) > 3 {
                cancel(reason: "마이크 입력이 끊겼습니다. 연결 상태를 확인해 주세요.")
                return
            }
            if elapsed >= Double(AudioCapture.maximumSeconds) { toggle() }
        }
        let lagging = Date().timeIntervalSince(lastPreview) > 4
        if previewLagging != lagging { previewLagging = lagging }
    }

    private func publishPreview() {
        if transcript != livePreview.snapshot { transcript = livePreview.snapshot }
    }

    func cancel(reason: String? = nil) {
        guard phase.busy, phase != .inserting, phase != .cancelling else { return }
        let previous = task
        let token = session.invalidate()
        phase = .cancelling; activeDecode = nil; capture.stop(); timer?.invalidate(); timer = nil
        previous?.cancel(); hotkeys.enableEscape(false)
        task = Task {
            await previous?.value
            guard session.accepts(token) else { return }
            capture.clear(); transcript = TranscriptSnapshot(); livePreview = LivePreview(); level = 0; target = nil
            phase = reason == nil ? .idle : .failed
            message = reason ?? ""
            if reason == nil { hidePanel?() }
            task = nil
        }
    }

    func copyResult() {
        guard !transcript.text.isEmpty else { return }
        TextInsertion.copy(transcript.text); message = "복사했어요. 원하는 입력창에 ⌘V로 붙여 넣으세요."
    }

    func beginShortcutCapture() {
        guard !phase.busy, !capturingShortcut else { return }
        testingShortcut = false
        shortcutError = ""; capturingShortcut = true
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard !event.isARepeat else { return nil }
            if event.keyCode == 53 { self.endShortcutCapture(); return nil }
            guard let proposed = Shortcut.from(event) else {
                self.shortcutError = "Control, Option 또는 Command와 다른 키를 함께 눌러 주세요."
                return nil
            }
            if self.applyShortcut(proposed) {
                self.endShortcutCapture()
            }
            return nil
        }
    }

    func endShortcutCapture() {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil; capturingShortcut = false
    }

    private func receiveShortcut() {
        if capturingShortcut { endShortcutCapture(); return }
        if testingShortcut {
            shortcutTestCount += 1
            shortcutFeedback = "입력 감지 \(shortcutTestCount)회 · 녹음하지 않습니다"
            return
        }
        switch phase {
        case .recording: shortcutFeedback = "입력 감지 · 녹음을 마무리합니다"
        case .starting: shortcutFeedback = "입력 감지 · 마이크를 준비하고 있습니다"
        case .finishing, .inserting, .cancelling: shortcutFeedback = "입력 감지 · 이전 작업이 끝나면 다시 시작할 수 있습니다"
        default:
            shortcutFeedback = modelReady ? "입력 감지 · 녹음을 시작합니다" : "입력 감지 · 음성 모델을 먼저 준비해 주세요"
        }
        toggle()
    }

    @discardableResult private func applyShortcut(_ proposed: Shortcut) -> Bool {
        guard hotkeys.register(proposed) else {
            shortcutError = hotkeys.registrationError
            return false
        }
        shortcut = proposed
        UserDefaults.standard.set(try? JSONEncoder().encode(proposed), forKey: "shortcut")
        shortcutError = ""; shortcutNotice = ""; shortcutFeedback = "단축키를 변경했습니다"
        return true
    }

    func useRecommendedShortcut() {
        guard !phase.busy else { return }
        testingShortcut = false
        if applyShortcut(.standard) { endShortcutCapture() }
    }

    func toggleShortcutTest() {
        guard !phase.busy, !capturingShortcut else { return }
        if testingShortcut { testingShortcut = false; return }
        guard hotkeys.register(shortcut) else { shortcutError = hotkeys.registrationError; return }
        shortcutError = ""; shortcutTestCount = 0; testingShortcut = true
        shortcutFeedback = "\(shortcut.label)를 눌러 보세요 · 녹음하지 않습니다"
    }
}
