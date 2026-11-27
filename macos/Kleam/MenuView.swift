import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            sectionDivider
            volume
            sectionDivider
            switches
            sectionDivider
            option("Randomized pitching", isOn: $model.randomPitch)
            Text(model.randomPitch ? model.lastCents : "pitch locked")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            option("Spatial audio", isOn: $model.spatial)
            option("Up/down keystrokes", isOn: $model.upDown)
            option("Mouse clicks", isOn: $model.mouseClicks)
            sectionDivider
            outputPicker
            Text("Mute  ⌃⌥⌘K")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
            if !model.trusted {
                accessNote
            }
            if !model.inputMonitoring {
                inputMonitoringNote
            }
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
            HStack(spacing: 16) {
                Button("About Kleam") { model.showAbout = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { model.quit() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        }
        .alert("Kleam 1.0.0", isPresented: $model.showAbout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                """
                Free & open source · Apache License 2.0

                Kleam is an independent project and is not affiliated with, endorsed by, or associated with Klack, Keychron, Cherry, Gateron, NovelKeys, Everglide, or Flurples.

                Inspired by mechanical-switch aesthetics · original synthesis.
                """
            )
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { model.refreshOutputDevices() }
        .onChange(of: model.enabled) { _, _ in model.applyAudio() }
        .onChange(of: model.volume) { _, _ in model.applyAudio() }
        .onChange(of: model.randomPitch) { _, _ in model.applyAudio() }
        .onChange(of: model.spatial) { _, _ in model.applyAudio() }
        .onChange(of: model.upDown) { _, _ in model.applyAudio() }
        .onChange(of: model.mouseClicks) { _, _ in model.applyAudio() }
        .onChange(of: model.outputDeviceUID) { _, _ in model.applyOutputDevice() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kleam")
                    .font(.headline)
                Text("Keyboard sounds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Sound", isOn: $model.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Toggle sound")
        }
        .padding(.bottom, 4)
    }

    private var volume: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volume")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $model.volume, in: 0...1)
                .accessibilityLabel("Sound volume")
        }
        .padding(.vertical, 8)
    }

    private var switches: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Switch")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(SwitchCatalog.all) { pack in
                switchRow(pack)
            }
        }
        .padding(.vertical, 6)
    }

    private func switchRow(_ pack: SwitchPack) -> some View {
        let selected = model.selectedSwitch == pack.slug
        return Button {
            model.selectSwitch(pack.slug)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: pack.colors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(pack.name)
                            .foregroundStyle(.primary)
                        if pack.isNew {
                            Text("New")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(pack.feel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var outputPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio output")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Audio output", selection: $model.outputDeviceUID) {
                ForEach(model.outputDevices) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(.vertical, 4)
    }

    private var inputMonitoringNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kleam needs Input Monitoring to play letter keys on the lock screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Input Monitoring Settings") {
                model.revealInputMonitoring()
            }
        }
        .padding(.top, 8)
    }

    private var accessNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kleam needs Accessibility to hear keys typed in other apps.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Accessibility Settings") {
                model.revealAccessibility()
            }
        }
        .padding(.top, 8)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.vertical, 6)
    }

    private func option(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .font(.callout)
            .padding(.vertical, 3)
    }
}
