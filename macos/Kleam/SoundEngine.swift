import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

struct SoundSettings: Equatable {
    var enabled: Bool
    var volume: Float
    var randomPitch: Bool
    var spatial: Bool
    var upDown: Bool
}

struct OutputDevice: Identifiable, Hashable {
    var id: String { uid }
    let uid: String
    let name: String
}

enum Stroke {
    case down
    case up
}

struct Played {
    var stroke: Stroke
    var pitch: Float
    var cents: Int
}

final class SoundEngine {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private var players: [AVAudioPlayerNode] = []
    private var inflight: [Int: AVAudioPCMBuffer] = [:]
    private var busy: [Bool] = []
    private var generation: [Int] = []
    private var cursor = 0
    private var down: [AVAudioPCMBuffer] = []
    private var up: [AVAudioPCMBuffer] = []
    private var mouseDown: AVAudioPCMBuffer?
    private var mouseUp: AVAudioPCMBuffer?
    private var settings = SoundSettings(
        enabled: true,
        volume: 0.82,
        randomPitch: true,
        spatial: true,
        upDown: true
    )
    private let voiceCount = 24
    private var outputDeviceUID = ""
    private var configurationObserver: NSObjectProtocol?
    private var rebuildingGraph = false
    private var previewToken = 0
    private var previewCache: [String: (down: AVAudioPCMBuffer, up: AVAudioPCMBuffer)] = [:]

    func prepare(slug: String = SwitchCatalog.defaultSlug, outputUID: String = "") throws {
        outputDeviceUID = outputUID
        try loadBank(slug: slug)
        guard players.isEmpty else { return }
        guard let format = down.first?.format else {
            throw EngineError.missingSamples
        }

        engine.attach(environment)
        environment.renderingAlgorithm = .HRTFHQ
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        environment.reverbParameters.enable = false
        environment.distanceAttenuationParameters.rolloffFactor = 0.25
        engine.connect(environment, to: engine.mainMixerNode, format: nil)

        for _ in 0..<voiceCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: environment, format: format)
            player.renderingAlgorithm = .HRTFHQ
            players.append(player)
            busy.append(false)
            generation.append(0)
        }

        installConfigurationObserver()
        try setOutputDevice(uid: outputDeviceUID)
    }

    func loadBank(slug: String) throws {
        let resolved = SwitchCatalog.resolvedSlug(slug)
        let nextDown = try loadStrokeBank(slug: resolved, name: "down")
        let nextUp = try loadStrokeBank(slug: resolved, name: "up")
        let nextMouseDown = try loadSample(slug: resolved, name: "mouse-down")
        let nextMouseUp = try loadSample(slug: resolved, name: "mouse-up")
        down = nextDown
        up = nextUp
        mouseDown = nextMouseDown
        mouseUp = nextMouseUp
    }

    func update(_ settings: SoundSettings) {
        self.settings = settings
        applyMixerVolume()
    }

    func setOutputDevice(uid: String) throws {
        let deviceID = try resolveDeviceID(uid: uid)
        outputDeviceUID = uid
        for player in players {
            player.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
        try assignOutputDevice(deviceID)
        if !players.isEmpty {
            try reconnectGraph()
        }
        try engine.start()
        for player in players {
            player.play()
        }
        applyMixerVolume()
    }

    /// Plays one click from `slug` without changing the active bank.
    /// Audible even while muted, so a menu preview can be heard.
    func preview(slug: String) throws {
        if !engine.isRunning {
            handleConfigurationChange()
        }
        guard engine.isRunning else { throw EngineError.outputDevice }
        let resolved = SwitchCatalog.resolvedSlug(slug)
        let sample = try previewSample(slug: resolved)
        let level: Float = settings.volume > 0.05 ? settings.volume : 0.82
        engine.mainMixerNode.outputVolume = level
        _ = schedule(
            sample.down,
            pitch: 1,
            volume: 1,
            x: 0,
            y: 0.05,
            z: settings.spatial ? -0.55 : 0,
            spatial: settings.spatial,
            stroke: .down,
            centsBase: 1
        )
        if settings.upDown {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self else { return }
                _ = self.schedule(
                    sample.up,
                    pitch: 1,
                    volume: 0.9,
                    x: 0,
                    y: 0.02,
                    z: self.settings.spatial ? -0.45 : 0,
                    spatial: self.settings.spatial,
                    stroke: .up,
                    centsBase: 1
                )
            }
        }
        previewToken += 1
        let token = previewToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.previewToken == token else { return }
            self.applyMixerVolume()
        }
    }

    static func outputDevices() -> [OutputDevice] {
        var devices: [OutputDevice] = [
            OutputDevice(uid: "", name: "System Default"),
        ]
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return devices
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &ids
        ) == noErr else {
            return devices
        }
        for id in ids {
            guard hasOutputChannels(id) else { continue }
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { continue }
            let name = stringProperty(id, kAudioDevicePropertyDeviceNameCFString) ?? uid
            devices.append(OutputDevice(uid: uid, name: name))
        }
        return devices
    }

    @discardableResult
    func play(keyCode: UInt16, stroke: Stroke) -> Played? {
        if stroke == .up && !settings.upDown { return nil }
        if !settings.enabled || settings.volume <= 0.001 { return nil }
        let bank = stroke == .down ? down : up
        guard !bank.isEmpty, !players.isEmpty else { return nil }

        let variant = Int(keyCode) % bank.count
        let source = bank[variant]
        let pitch = baseRate(keyCode) * (settings.randomPitch ? randomPitch() : 1)
        return schedule(
            source,
            pitch: pitch,
            volume: settings.randomPitch ? Float.random(in: 0.9...1.05) : 1,
            x: (position(keyCode) - 0.5) * (settings.spatial ? 2.1 : 0.2),
            y: rowLift(keyCode),
            z: settings.spatial ? -0.6 : 0,
            spatial: settings.spatial,
            stroke: stroke,
            centsBase: pitch / baseRate(keyCode)
        )
    }

    @discardableResult
    func playMouse(stroke: Stroke) -> Played? {
        if !settings.enabled || settings.volume <= 0.001 { return nil }
        let source = stroke == .down ? mouseDown : mouseUp
        guard let source, !players.isEmpty else { return nil }
        let pitch = settings.randomPitch ? randomPitch() : 1
        return schedule(
            source,
            pitch: pitch,
            volume: 0.85,
            x: 0,
            y: -0.05,
            z: settings.spatial ? -0.45 : 0,
            spatial: settings.spatial,
            stroke: stroke,
            centsBase: pitch
        )
    }

    private func schedule(
        _ source: AVAudioPCMBuffer,
        pitch: Float,
        volume: Float,
        x: Float,
        y: Float,
        z: Float,
        spatial: Bool,
        stroke: Stroke,
        centsBase: Float
    ) -> Played {
        let (index, player) = takeVoice()
        generation[index] += 1
        let token = generation[index]
        let buffer = resample(source, rate: pitch)
        inflight[index] = buffer
        player.volume = volume
        player.position = AVAudio3DPoint(x: x, y: y, z: z)
        player.renderingAlgorithm = spatial ? .HRTFHQ : .equalPowerPanning
        player.scheduleBuffer(buffer, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self, index < self.busy.count, self.generation[index] == token else { return }
                self.busy[index] = false
                self.inflight[index] = nil
            }
        })
        if !player.isPlaying {
            player.play()
        }
        return Played(stroke: stroke, pitch: pitch, cents: cents(from: centsBase))
    }

    private func takeVoice() -> (Int, AVAudioPlayerNode) {
        if let free = busy.firstIndex(of: false) {
            busy[free] = true
            return (free, players[free])
        }
        let index = cursor % players.count
        cursor += 1
        players[index].stop()
        players[index].play()
        busy[index] = true
        return (index, players[index])
    }

    private func resample(_ buffer: AVAudioPCMBuffer, rate: Float) -> AVAudioPCMBuffer {
        let clamped = min(1.25, max(0.75, rate))
        if abs(clamped - 1) < 0.004 { return buffer }
        guard let channels = buffer.floatChannelData else { return buffer }
        let inputFrames = Int(buffer.frameLength)
        let outputFrames = max(1, Int(Float(inputFrames) / clamped))
        guard let output = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: AVAudioFrameCount(outputFrames)
        ), let destination = output.floatChannelData else {
            return buffer
        }
        output.frameLength = AVAudioFrameCount(outputFrames)
        let channelCount = Int(buffer.format.channelCount)
        let last = max(0, inputFrames - 1)
        for channel in 0..<channelCount {
            let source = channels[channel]
            let target = destination[channel]
            for frame in 0..<outputFrames {
                let position = Float(frame) * clamped
                let left = min(Int(position), last)
                let right = min(left + 1, last)
                let fraction = position - Float(left)
                target[frame] = source[left] * (1 - fraction) + source[right] * fraction
            }
        }
        return output
    }

    /// Changing the output device posts `AVAudioEngineConfigurationChange` and stops the engine.
    /// The environment graph stays wired to the previous sample rate, so playback stays silent
    /// until the process is restarted. Rebuild the graph and start the players again.
    private func installConfigurationObserver() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func handleConfigurationChange() {
        guard !players.isEmpty, !rebuildingGraph else { return }
        rebuildingGraph = true
        defer { rebuildingGraph = false }
        do {
            for player in players {
                player.stop()
            }
            try reconnectGraph()
            if !engine.isRunning {
                try engine.start()
            }
            for player in players {
                player.play()
            }
            applyMixerVolume()
        } catch {
            return
        }
    }

    private func reconnectGraph() throws {
        guard let format = down.first?.format else { return }
        engine.disconnectNodeOutput(environment)
        for player in players {
            engine.disconnectNodeOutput(player)
        }
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        for player in players {
            engine.connect(player, to: environment, format: format)
            player.renderingAlgorithm = .HRTFHQ
        }
    }

    private func applyMixerVolume() {
        engine.mainMixerNode.outputVolume = settings.enabled ? settings.volume : 0
    }

    private func assignOutputDevice(_ deviceID: AudioDeviceID) throws {
        guard let unit = engine.outputNode.audioUnit else {
            throw EngineError.outputDevice
        }
        var id = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            throw EngineError.outputDevice
        }
    }

    private func previewSample(slug: String) throws -> (down: AVAudioPCMBuffer, up: AVAudioPCMBuffer) {
        if let cached = previewCache[slug] {
            return cached
        }
        let sample = (
            down: try loadSample(slug: slug, name: "down-0"),
            up: try loadSample(slug: slug, name: "up-0")
        )
        previewCache[slug] = sample
        return sample
    }

    private func resolveDeviceID(uid: String) throws -> AudioDeviceID {
        if uid.isEmpty {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var deviceID = AudioDeviceID()
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                &deviceID
            )
            guard status == noErr else { throw EngineError.outputDevice }
            return deviceID
        }
        guard let deviceID = deviceID(forUID: uid) else {
            throw EngineError.outputDevice
        }
        return deviceID
    }

    private func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return nil
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &ids
        ) == noErr else {
            return nil
        }
        for id in ids {
            if stringProperty(id, kAudioDevicePropertyDeviceUID) == uid {
                return id
            }
        }
        return nil
    }

    private func loadStrokeBank(slug: String, name: String) throws -> [AVAudioPCMBuffer] {
        var buffers: [AVAudioPCMBuffer] = []
        for index in 0..<6 {
            buffers.append(try loadSample(slug: slug, name: "\(name)-\(index)"))
        }
        return buffers
    }

    private func loadSample(slug: String, name: String) throws -> AVAudioPCMBuffer {
        let subdirectory = "sounds/\(slug)"
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "wav",
            subdirectory: subdirectory
        ) else {
            throw EngineError.missingSamples
        }
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw EngineError.missingSamples
        }
        try file.read(into: buffer)
        return buffer
    }
}

private enum EngineError: Error {
    case missingSamples
    case outputDevice
}

private func stringProperty(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, pointer)
    }
    guard status == noErr else { return nil }
    return value as String?
}

private func hasOutputChannels(_ device: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
        return false
    }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, raw) == noErr else {
        return false
    }
    let list = raw.assumingMemoryBound(to: AudioBufferList.self)
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    var channels = 0
    for buffer in buffers {
        channels += Int(buffer.mNumberChannels)
    }
    return channels > 0
}

private func randomPitch() -> Float {
    let spread = Float.random(in: 0...1) + Float.random(in: 0...1) - 1
    return 1 + spread * 0.05
}

private func cents(from pitch: Float) -> Int {
    Int((1200 * log2(max(pitch, 0.01))).rounded())
}

private func baseRate(_ keyCode: UInt16) -> Float {
    switch body(keyCode) {
    case .space:
        return 0.84
    case .modifier:
        return 0.92
    case .number:
        return 1.06
    case .letter:
        return 1
    }
}

private enum KeyBody {
    case space
    case modifier
    case number
    case letter
}

private func body(_ keyCode: UInt16) -> KeyBody {
    if keyCode == 0x31 { return .space }
    let modifiers: Set<UInt16> = [
        0x24, 0x30, 0x33, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F,
    ]
    if modifiers.contains(keyCode) { return .modifier }
    let numbers: Set<UInt16> = [
        0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x32,
    ]
    if numbers.contains(keyCode) { return .number }
    return .letter
}

private func position(_ keyCode: UInt16) -> Float {
    let columns: [UInt16: Float] = [
        0x32: 0, 0x12: 1, 0x13: 2, 0x14: 3, 0x15: 4, 0x17: 5, 0x16: 6, 0x1A: 7, 0x1C: 8,
        0x19: 9, 0x1D: 10, 0x1B: 11, 0x18: 12, 0x33: 13,
        0x30: 0, 0x0C: 1.5, 0x0D: 2.5, 0x0E: 3.5, 0x0F: 4.5, 0x11: 5.5, 0x10: 6.5, 0x20: 7.5,
        0x22: 8.5, 0x1F: 9.5, 0x23: 10.5, 0x21: 11.5, 0x1E: 12.5, 0x2A: 13.5,
        0x39: 0, 0x00: 1.8, 0x01: 2.8, 0x02: 3.8, 0x03: 4.8, 0x05: 5.8, 0x04: 6.8, 0x26: 7.8,
        0x28: 8.8, 0x25: 9.8, 0x29: 10.8, 0x27: 11.8, 0x24: 13,
        0x38: 0, 0x06: 2.2, 0x07: 3.2, 0x08: 4.2, 0x09: 5.2, 0x0B: 6.2, 0x2D: 7.2, 0x2E: 8.2,
        0x2B: 9.2, 0x2F: 10.2, 0x2C: 11.2, 0x3C: 13,
        0x3F: 0, 0x3B: 0.8, 0x3A: 2.2, 0x37: 3.6, 0x31: 6.5, 0x36: 10, 0x3D: 11.2, 0x3E: 12.6,
        0x7B: 9.5, 0x7D: 10.6, 0x7C: 11.7, 0x7E: 10.6,
    ]
    guard let column = columns[keyCode] else { return 0.5 }
    return min(1, max(0, column / 13))
}

private func rowLift(_ keyCode: UInt16) -> Float {
    let home: Set<UInt16> = [0x00, 0x01, 0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25, 0x29, 0x27]
    if home.contains(keyCode) { return 0.05 }
    if keyCode == 0x31 { return -0.15 }
    return 0
}
