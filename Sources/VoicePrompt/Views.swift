import SwiftUI

private let accent = Color(red: 0.12, green: 0.49, blue: 0.43)

struct SettingsView: View {
    @ObservedObject var model: AppModel
    private var card: Color { Color(nsColor: .controlBackgroundColor) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("VoicePrompt").font(.system(size: 20, weight: .semibold, design: .rounded))
                            Text("v\(AppRelease.version)").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Text("내 Mac에서만 처리하는 음성 입력").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("로컬 전용", systemImage: "lock.shield").font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(accent.opacity(0.08), in: Capsule())
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("말하면, 바로 입력.").font(.system(size: 30, weight: .bold))
                    Text("단축키로 시작하고, 말하는 내용을 실시간으로 확인하세요.\n다시 누르면 완성된 문장이 원래 입력창에 들어갑니다.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("사용 준비").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("처음 한 번만 설정하면 돼요").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(18)
                    Divider().padding(.horizontal, 18)
                    setupRow(icon: "waveform", title: "음성 인식 모델", detail: model.preparationText, ready: model.modelReady) {
                        if model.preparing { ProgressView().controlSize(.small).frame(width: 80) }
                        else if !model.modelReady {
                            Button(SpeechEngine.installedModel == nil ? "다운로드" : "다시 준비") { model.prepare(download: true) }
                                .buttonStyle(.borderedProminent).tint(accent).controlSize(.small)
                        }
                    }
                    if model.preparing, let progress = model.preparationProgress {
                        ProgressView(value: progress).tint(accent).padding(.horizontal, 18).padding(.bottom, 12)
                    }
                    Divider().padding(.leading, 56)
                    setupRow(icon: "mic", title: "마이크", detail: model.microphoneGranted ? "말하는 동안에만 마이크를 사용합니다." : "음성을 듣기 위한 접근 권한이 필요합니다.", ready: model.microphoneGranted) {
                        if !model.microphoneGranted { Button("허용하기") { model.requestMicrophone() }.controlSize(.small) }
                    }
                    Divider().padding(.leading, 56)
                    setupRow(icon: "cursorarrow.and.square.on.square.dashed", title: "자동 입력", detail: model.accessibilityGranted ? "현재 커서 위치에 최종 결과를 붙여 넣습니다." : "손쉬운 사용 권한을 켜면 자동으로 입력할 수 있어요.", ready: model.accessibilityGranted) {
                        if !model.accessibilityGranted {
                            Button("설정 열기") { TextInsertion.requestPermission(); model.openPrivacy("Privacy_Accessibility") }.controlSize(.small)
                        }
                    }
                }.background(card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.06)))
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("녹음 단축키").font(.system(size: 13, weight: .semibold))
                            Text("한 번 누르면 시작, 다시 누르면 완료").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(model.capturingShortcut ? "새 단축키를 누르세요…" : model.shortcut.label) { model.beginShortcutCapture() }
                            .font(.system(size: 14, weight: .medium, design: .monospaced)).buttonStyle(.bordered).disabled(model.phase.busy)
                    }
                    if !model.shortcutError.isEmpty { Text(model.shortcutError).font(.caption).foregroundStyle(.red) }
                    if model.capturingShortcut { Text("Control / Option / Command + 키 · Esc로 취소").font(.caption).foregroundStyle(.secondary) }
                    Divider()
                    HStack {
                        Text("입력 마이크").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Picker("입력 마이크", selection: $model.microphoneID) {
                            Text("시스템 기본 마이크").tag(UInt32(0))
                            ForEach(model.devices) { device in Text(device.name).tag(device.id) }
                            if model.microphoneID != 0 && !model.devices.contains(where: { $0.id == model.microphoneID }) {
                                Text("연결되지 않은 마이크").tag(model.microphoneID)
                            }
                        }.labelsHidden().frame(maxWidth: 250).disabled(model.phase.busy)
                    }
                }.padding(18).background(card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.06)))
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle").accessibilityHidden(true)
                    Text("한국어와 영어 용어를 함께 말할 수 있어요. 음성과 전사 기록은 저장하지 않으며, 입력한 내용은 직접 확인하고 전송하세요.").lineSpacing(3)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Text("입력할 앱에 커서를 두고 \(model.shortcut.label)를 누르세요.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.phase == .recording ? "녹음 완료" : "녹음 테스트") { model.toggle() }
                        .disabled(!model.modelReady || (model.phase.busy && model.phase != .recording))
                }
                HStack {
                    Text("\(AppRelease.label) · 로컬 전사").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button("권한 다시 확인") { model.refreshPermissions() }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(accent)
                }
            }.padding(28)
        }.background(Color(nsColor: .windowBackgroundColor))
            .frame(minWidth: 560, idealWidth: 600, minHeight: 640)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermissions() }
    }

    private func setupRow<Action: View>(icon: String, title: String, detail: String, ready: Bool, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if ready { Label("완료", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(accent) }
            else { action() }
        }.padding(.horizontal, 18).padding(.vertical, 15)
    }
}

/// Compact preview: one status row and the latest two lines of speech.
struct DictationView: View {
    @ObservedObject var model: AppModel

    private var line: String {
        let text = model.transcript.text
        if !text.isEmpty { return text }
        if !model.phase.busy && !model.message.isEmpty { return model.message }
        switch model.phase {
        case .recording: return "편하게 말해 주세요."
        case .starting, .finishing, .inserting, .cancelling: return "잠시만 기다려 주세요."
        default: return "인식된 내용이 없습니다."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: model.phase == .recording ? "waveform" : (model.phase == .complete ? "checkmark.circle.fill" : "waveform.bubble"))
                    .font(.system(size: 11)).foregroundStyle(model.phase == .recording ? Color.red : accent).accessibilityHidden(true)
                Text(model.phase.title).font(.system(size: 11, weight: .semibold))
                if model.phase == .recording {
                    Meter(level: model.level).frame(width: 34, height: 12).accessibilityLabel("마이크 입력 음량")
                } else if model.phase.busy {
                    ProgressView().controlSize(.mini)
                }
                Spacer(minLength: 4)
                if model.phase.busy {
                    Text(String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60))
                        .font(.system(size: 10, design: .monospaced)).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    if !model.accessibilityGranted {
                        Button("자동 입력 허용") { TextInsertion.requestPermission(); model.openPrivacy("Privacy_Accessibility") }.controlSize(.mini)
                    }
                    if !model.transcript.text.isEmpty && model.phase != .complete {
                        Button("복사") { model.copyResult() }.controlSize(.mini)
                    }
                }
                if model.phase != .inserting {
                    Button { model.phase.busy ? model.cancel() : model.hidePanel?() } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 16, height: 16)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel(model.phase.busy ? "녹음 취소" : "미리보기 닫기")
                }
            }
            // Head truncation keeps the newest words visible as speech grows.
            Text(line).font(.system(size: 13)).lineSpacing(2).lineLimit(2).truncationMode(.head)
                .foregroundStyle(model.transcript.text.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                .help(model.transcript.text.isEmpty ? model.message : model.transcript.text)
        }.padding(.horizontal, 14).padding(.vertical, 11).frame(width: 340, height: 82)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.12))).padding(10)
            .transaction { $0.animation = nil }
    }
}

private struct Meter: View {
    let level: Float
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<7) { index in
                Capsule().fill(accent.opacity(Double(level) > Double(index) / 9 ? 1 : 0.2))
                    .frame(width: 3, height: CGFloat(5 + (3 - abs(index - 3)) * 3))
            }
        }
    }
}

/// Launch greeting: the parrot mascot "says" a hint, typing it out while it bobs.
/// The command-line toolchain has no SwiftUI macros (@State), so state lives here.
@MainActor
final class Greeting: ObservableObject {
    let message: String
    @Published var shown = ""
    @Published var hop = false
    @Published var visible = false
    var onFinish: (() -> Void)?
    private var task: Task<Void, Never>?

    init(message: String) { self.message = message }

    func start() {
        task = Task {
            withAnimation(.spring(duration: 0.35)) { visible = true }
            try? await Task.sleep(for: .milliseconds(300))
            for (index, character) in message.enumerated() {
                guard !Task.isCancelled else { return }
                shown.append(character)
                if index % 2 == 0 { hop.toggle() }
                try? await Task.sleep(for: .milliseconds(character == " " ? 30 : 55))
            }
            hop = false
            try? await Task.sleep(for: .seconds(2.4))
            dismiss()
        }
    }

    func dismiss() {
        task?.cancel(); task = nil
        withAnimation(.easeOut(duration: 0.25)) { visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.onFinish?(); self?.onFinish = nil }
    }
}

struct GreetingView: View {
    @ObservedObject var greeting: Greeting
    private let mascot = Bundle.main.image(forResource: "Mascot") ?? NSApp.applicationIconImage ?? NSImage()

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Image(nsImage: mascot).resizable().frame(width: 52, height: 52)
                .offset(y: greeting.hop ? -4 : 0).rotationEffect(.degrees(greeting.hop ? -4 : 0), anchor: .bottom)
                .animation(.easeInOut(duration: 0.09), value: greeting.hop).accessibilityHidden(true)
            Text(greeting.shown).font(.system(size: 11.5, weight: .medium)).lineSpacing(2)
                .frame(width: 186, alignment: .topLeading).frame(minHeight: 30, alignment: .topLeading)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.1)))
                .padding(.bottom, 26).accessibilityLabel(greeting.message)
        }.padding(8).frame(width: 290, height: 104, alignment: .bottomLeading)
            .opacity(greeting.visible ? 1 : 0).scaleEffect(greeting.visible ? 1 : 0.92, anchor: .bottomLeading)
            .onTapGesture { greeting.dismiss() }
    }
}
