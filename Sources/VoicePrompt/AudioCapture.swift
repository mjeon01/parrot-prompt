import AVFoundation
import CoreAudio
import WhisperKit

/// AVAudioEngine's tap writes only to this lock-protected, memory-only buffer.
final class AudioCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var rms: Float = 0
    private var lastBuffer = Date()
    private var accepting = false
    private var engine: AVAudioEngine?
    static let sampleRate = 16000
    static let maximumSeconds = 600

    struct Snapshot {
        let samples: [Float]
        let level: Float
        let lastBuffer: Date
    }

    func snapshot(from index: Int = 0) -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(samples: Array(samples.dropFirst(max(0, index))), level: rms, lastBuffer: lastBuffer)
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return samples.count }

    func start(deviceID: AudioDeviceID?) throws {
        stop()
        lock.lock()
        samples.removeAll(keepingCapacity: false); rms = 0; lastBuffer = Date(); accepting = true
        lock.unlock()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if var deviceID, let unit = input.audioUnit {
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw CaptureError.deviceUnavailable }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: output) else { throw CaptureError.deviceUnavailable }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / format.sampleRate)) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, let channel = converted.floatChannelData?[0] else { return }
            let values = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            let energy = sqrt(values.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, values.count)))
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.accepting else { return }
            let remaining = Self.maximumSeconds * Self.sampleRate - self.samples.count
            self.samples.append(contentsOf: values.prefix(max(0, remaining)))
            self.rms = min(1, energy * 12)
            self.lastBuffer = Date()
        }
        self.engine = engine
        do { engine.prepare(); try engine.start() }
        catch { stop(); throw error }
    }

    func stop() {
        lock.lock(); accepting = false; lock.unlock()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    func clear() {
        stop()
        lock.lock(); samples.removeAll(keepingCapacity: false); rms = 0; lock.unlock()
    }

    enum CaptureError: LocalizedError {
        case deviceUnavailable
        var errorDescription: String? { "마이크를 사용할 수 없습니다. 연결 상태와 선택한 마이크를 확인해 주세요." }
    }
}
