import AppKit
import ApplicationServices
import SwiftUI

final class AppModel: ObservableObject {
    @Published var enabled: Bool
    @Published var volume: Double
    @Published var randomPitch: Bool
    @Published var spatial: Bool
    @Published var upDown: Bool
    @Published var mouseClicks: Bool
    @Published var selectedSwitch: String
    @Published var outputDeviceUID: String
    @Published var outputDevices: [OutputDevice]
    @Published var trusted: Bool
    @Published var lastCents: String
    @Published var status: String
    @Published var showAbout = false
    @Published var switchMenuOpen = false

    let engine = SoundEngine()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var trustTimer: Timer?
    private var heldModifiers = Set<UInt16>()

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        volume = defaults.object(forKey: Keys.volume) as? Double ?? 0.82
        randomPitch = defaults.object(forKey: Keys.randomPitch) as? Bool ?? true
        spatial = defaults.object(forKey: Keys.spatial) as? Bool ?? true
        upDown = defaults.object(forKey: Keys.upDown) as? Bool ?? true
        mouseClicks = defaults.object(forKey: Keys.mouseClicks) as? Bool ?? false
        selectedSwitch = SwitchCatalog.resolvedSlug(
            defaults.string(forKey: Keys.selectedSwitch) ?? SwitchCatalog.defaultSlug
        )
        outputDeviceUID = defaults.string(forKey: Keys.outputDeviceUID) ?? ""
        outputDevices = SoundEngine.outputDevices()
        trusted = AXIsProcessTrusted()
        lastCents = "a new pitch each press"
        status = ""
        showAbout = false
        switchMenuOpen = false
    }

    func start() {
        do {
            try engine.prepare(slug: selectedSwitch, outputUID: outputDeviceUID)
            status = ""
        } catch {
            status = "Audio didn't start"
        }
        applyAudio()
        installMonitors()
        refreshTrust(prompt: true)
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshTrust(prompt: false)
        }
    }

    func applyAudio() {
        UserDefaults.standard.set(enabled, forKey: Keys.enabled)
        UserDefaults.standard.set(volume, forKey: Keys.volume)
        UserDefaults.standard.set(randomPitch, forKey: Keys.randomPitch)
        UserDefaults.standard.set(spatial, forKey: Keys.spatial)
        UserDefaults.standard.set(upDown, forKey: Keys.upDown)
        UserDefaults.standard.set(mouseClicks, forKey: Keys.mouseClicks)
        UserDefaults.standard.set(selectedSwitch, forKey: Keys.selectedSwitch)
        UserDefaults.standard.set(outputDeviceUID, forKey: Keys.outputDeviceUID)
        engine.update(
            SoundSettings(
                enabled: enabled,
                volume: Float(volume),
                randomPitch: randomPitch,
                spatial: spatial,
                upDown: upDown
            )
        )
    }

    func selectSwitch(_ slug: String) {
        let resolved = SwitchCatalog.resolvedSlug(slug)
        guard resolved != selectedSwitch else { return }
        do {
            try engine.loadBank(slug: resolved)
            selectedSwitch = resolved
            applyAudio()
            status = ""
        } catch {
            status = "Couldn't load switch"
        }
    }

    func previewSwitch(_ slug: String) {
        do {
            try engine.preview(slug: slug)
            status = ""
        } catch {
            status = "Couldn't preview switch"
        }
    }

    func refreshOutputDevices() {
        outputDevices = SoundEngine.outputDevices()
        if !outputDeviceUID.isEmpty, !outputDevices.contains(where: { $0.uid == outputDeviceUID }) {
            outputDeviceUID = ""
            applyOutputDevice()
        }
    }

    func applyOutputDevice() {
        do {
            try engine.setOutputDevice(uid: outputDeviceUID)
            applyAudio()
            status = ""
        } catch {
            status = "Couldn't set output"
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func revealAccessibility() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    private func installMonitors() {
        let keyMask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: keyMask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: keyMask) { [weak self] event in
            self?.handle(event)
            return event
        }

        let mouseMask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
        ]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] event in
            self?.handleMouse(event)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self] event in
            self?.handleMouse(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        if isMuteHotkey(event) {
            if event.type == .keyDown && !event.isARepeat {
                enabled.toggle()
                applyAudio()
            }
            return
        }
        if event.type == .flagsChanged {
            handleFlags(event)
            return
        }
        if event.isARepeat || Self.modifierCodes.contains(event.keyCode) { return }
        let stroke: Stroke = event.type == .keyUp ? .up : .down
        note(engine.play(keyCode: event.keyCode, stroke: stroke))
    }

    private func handleMouse(_ event: NSEvent) {
        guard mouseClicks else { return }
        let stroke: Stroke
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            stroke = .down
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            stroke = .up
        default:
            return
        }
        _ = engine.playMouse(stroke: stroke)
    }

    private func isMuteHotkey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown || event.type == .keyUp else { return false }
        guard event.keyCode == Self.muteKeyCode else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == [.control, .option, .command]
    }

    /// Shift, Control, Option, and Command arrive as flag changes, not key events.
    private func handleFlags(_ event: NSEvent) {
        let code = event.keyCode
        let down = modifierIsDown(code, flags: flagsRaw(event))
        if down {
            guard heldModifiers.insert(code).inserted else { return }
            note(engine.play(keyCode: code, stroke: .down))
        } else {
            guard heldModifiers.remove(code) != nil else { return }
            _ = engine.play(keyCode: code, stroke: .up)
        }
    }

    private func flagsRaw(_ event: NSEvent) -> UInt64 {
        if let raw = event.cgEvent?.flags.rawValue {
            return raw
        }
        return UInt64(event.modifierFlags.rawValue)
    }

    private func modifierIsDown(_ keyCode: UInt16, flags: UInt64) -> Bool {
        switch keyCode {
        case 0x38: return deviceBit(flags, 0x0002) ?? symbolic(flags, .shift)
        case 0x3C: return deviceBit(flags, 0x0004) ?? symbolic(flags, .shift)
        case 0x3B: return deviceBit(flags, 0x0001) ?? symbolic(flags, .control)
        case 0x3E: return deviceBit(flags, 0x2000) ?? symbolic(flags, .control)
        case 0x3A: return deviceBit(flags, 0x0020) ?? symbolic(flags, .option)
        case 0x3D: return deviceBit(flags, 0x0040) ?? symbolic(flags, .option)
        case 0x37: return deviceBit(flags, 0x0008) ?? symbolic(flags, .command)
        case 0x36: return deviceBit(flags, 0x0010) ?? symbolic(flags, .command)
        case 0x3F: return symbolic(flags, .function)
        case 0x39:
            // Caps Lock's flag stays on after the key is released, so each event flips the key.
            return !heldModifiers.contains(keyCode)
        default:
            return !heldModifiers.contains(keyCode)
        }
    }

    /// Left and right modifiers have their own bits. If the event only carries the shared flag, return nil.
    private func deviceBit(_ flags: UInt64, _ mask: UInt64) -> Bool? {
        let deviceBits: UInt64 = 0x207F
        guard flags & deviceBits != 0 else { return nil }
        return flags & mask != 0
    }

    private func symbolic(_ flags: UInt64, _ flag: NSEvent.ModifierFlags) -> Bool {
        flags & UInt64(flag.rawValue) != 0
    }

    private static let modifierCodes: Set<UInt16> = [
        0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F,
    ]

    /// Physical key code for K — mute hotkey is ⌃⌥⌘K.
    private static let muteKeyCode: UInt16 = 0x28

    private func note(_ played: Played?) {
        guard let played, played.stroke == .down else { return }
        if randomPitch {
            lastCents = formatCents(played.cents)
        } else {
            lastCents = "pitch locked"
        }
    }

    private func refreshTrust(prompt: Bool) {
        if prompt {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [key: true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }
    }
}

private enum Keys {
    static let enabled = "enabled"
    static let volume = "volume"
    static let randomPitch = "randomPitch"
    static let spatial = "spatial"
    static let upDown = "upDown"
    static let mouseClicks = "mouseClicks"
    static let selectedSwitch = "selectedSwitch"
    static let outputDeviceUID = "outputDeviceUID"
}

private func formatCents(_ cents: Int) -> String {
    if cents > 0 { return "+\(cents)¢" }
    if cents < 0 { return "−\(abs(cents))¢" }
    return "0¢"
}
