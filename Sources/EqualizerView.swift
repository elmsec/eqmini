import AppKit
import Combine
import ServiceManagement
import SwiftUI

struct EqualizerPanel: View {
  @ObservedObject var model: EqualizerModel
  var panelHeight: CGFloat = 640
  private let accent = Color(red: 0.32, green: 0.88, blue: 0.72)
  private let labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
  private let frequencies = [
    "32 Hz", "64 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz",
  ]

  var body: some View {
    VStack(spacing: 0) {
      header.padding(20)
      Divider().overlay(Color.white.opacity(0.04))
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 18) {
          if model.choosingApps { appPicker } else { audioControls }
          if let error = model.error {
            VStack(alignment: .leading, spacing: 8) {
              Label(error, systemImage: "exclamationmark.circle")
                .font(.system(size: 12)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
              if model.audioPermissionDenied {
                Button("Open Audio Recording Settings") {
                  NSWorkspace.shared.open(
                    URL(
                      string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
                    )!)
                }
              }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
          }
        }
        .padding(20).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollIndicators(.visible)
      .id(model.choosingApps)
      Divider()
      soundControls.padding(.horizontal, 20).padding(.vertical, 16)
      Divider()
      powerBar.padding(.horizontal, 20).padding(.vertical, 14)
    }
    .frame(width: 480, height: panelHeight)
    .background(Color(red: 0.075, green: 0.085, blue: 0.095))
    .foregroundStyle(Color.white.opacity(0.92))
    .tint(accent).preferredColorScheme(.dark)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "waveform.path")
        .font(.system(size: 22, weight: .medium)).foregroundStyle(accent)
        .frame(width: 42, height: 42)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text("eqmini").font(.system(size: 24, weight: .bold, design: .rounded))
        Text(
          model.restarting
            ? "Reconnecting audio…"
            : model.enabled && !model.waitingForApps ? model.output : "Your sound, a little fuller."
        )
        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        .help(model.output)
      }
      Spacer()
      if model.choosingApps {
        Button("Done") { model.choosingApps = false }
          .buttonStyle(.borderedProminent).controlSize(.small)
      } else {
        Menu {
          Button("Open Equalizer Window") {
            (NSApp.delegate as? AppDelegate)?.showEqualizerWindow()
          }
          .keyboardShortcut("o")
          Button("About eqmini") { (NSApp.delegate as? AppDelegate)?.showAbout() }
          Button("Settings…") { (NSApp.delegate as? AppDelegate)?.showSettings() }
            .keyboardShortcut(",")
          Link("Privacy Policy", destination: AppLinks.privacy)
          Link("Terms of Use", destination: AppLinks.terms)
          Divider()
          Button("Reset equalizer") { model.resetEqualizer() }
          Button("Reset output gain") { model.setOutputGain(0) }
          Divider()
          Button("Quit eqmini") {
            NSApplication.shared.terminate(nil)
          }
          .keyboardShortcut("q")
        } label: {
          Image(systemName: "ellipsis.circle").font(.system(size: 19)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(
          "More options")
      }
    }
  }

  private var audioControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: "speaker.wave.2").font(.system(size: 16)).foregroundStyle(accent)
          .accessibilityHidden(true)
        Text("Apply to").font(.system(size: 11)).foregroundStyle(.secondary)
        Menu {
          Button("All audio") { model.setSelectedOnly(false) }
          Button("Selected apps") { model.setSelectedOnly(true) }
          Divider()
          Button("Choose apps…") {
            model.setSelectedOnly(true)
            model.choosingApps = true
          }
        } label: {
          Text(model.selectedOnly ? model.scopeSummary : "All audio")
            .font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .menuStyle(.borderlessButton).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Audio routing").help(
          model.selectedOnly ? model.scopeSummary : "Applies to all audio")
      }
      .padding(12).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))

      VStack(alignment: .leading, spacing: 9) {
        HStack {
          Text("PRESETS").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(
            .secondary)
          Spacer()
          if model.customGains != nil {
            Button {
              model.restoreCustom()
            } label: {
              Label(model.preset == "Custom" ? "Custom" : "Saved custom", systemImage: "bookmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.preset == "Custom" ? accent : Color.white.opacity(0.65))
            }.buttonStyle(.plain).help("Restore your saved Custom curve")
          }
        }
        HStack(spacing: 9) {
          presetTile(.flat, title: "Flat", icon: "line.3.horizontal")
          presetTile(.bass, title: "Bass Boost", icon: "waveform.path")
          presetTile(.warm, title: "Warm", icon: "sun.max")
        }
      }

      HStack(spacing: 12) {
        Text("Equalizer").font(.system(size: 13, weight: .semibold))
        Spacer(minLength: 4)
        HStack(spacing: 3) {
          editorModeButton("Simple", selected: model.simpleMode) { model.setSimpleMode(true) }
          editorModeButton("10 bands", selected: !model.simpleMode) { model.setSimpleMode(false) }
        }
        .padding(3).frame(width: 170)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        Button {
          model.resetEqualizer()
        } label: {
          Label("Reset", systemImage: "arrow.counterclockwise")
            .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
        }
        .buttonStyle(.plain).accessibilityLabel("Reset EQ")
        .help(
          "Clears all bands, saved Custom, tone controls, and Speaker bass. App selection and output volume stay unchanged."
        )
      }.padding(.top, 2)
      if model.simpleMode { simpleEqualizer } else { equalizer }
      Toggle(isOn: Binding(get: { model.speakerBass }, set: model.setSpeakerBass)) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Speaker bass").font(.system(size: 12, weight: .semibold))
          Text("Adds audible bass harmonics for small speakers. Changes the tone.")
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.toggleStyle(.switch).accessibilityLabel("Speaker bass")
    }
  }

  private func presetTile(_ preset: Preset, title: String, icon: String) -> some View {
    let selected = model.preset == preset.rawValue
    return Button {
      model.apply(preset)
    } label: {
      HStack(spacing: 8) {
        Image(systemName: icon).font(.system(size: 16, weight: .medium))
        Text(title).font(.system(size: 12, weight: .semibold))
      }
      .frame(maxWidth: .infinity).frame(height: 44)
      .foregroundStyle(selected ? accent : Color.white.opacity(0.7))
      .background(
        selected ? accent.opacity(0.12) : Color.white.opacity(0.035),
        in: RoundedRectangle(cornerRadius: 12)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12).stroke(
          selected ? accent.opacity(0.55) : Color.white.opacity(0.055), lineWidth: 1))
    }
    .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func editorModeButton(_ title: String, selected: Bool, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Text(title).font(.system(size: 12, weight: .semibold))
        .frame(maxWidth: .infinity).frame(height: 29)
        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.8))
        .background(selected ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    .transaction { $0.animation = nil }
  }

  private var simpleEqualizer: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("These controls follow your current EQ. Adjust by ear.")
        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
      ForEach(0..<3, id: \.self) { i in
        VStack(alignment: .leading, spacing: 3) {
          HStack {
            Text(["Bass", "Voices", "Detail"][i]).font(.system(size: 13, weight: .semibold))
            Text(["Kick & warmth", "Vocals & speech", "Crispness"][i])
              .font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Button {
              model.setSimpleTone(i, 0)
            } label: {
              Text(
                model.simpleTones[i] == 0
                  ? "Neutral" : String(format: "%+.1f", model.simpleTones[i])
              )
              .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }.buttonStyle(.plain).help("Reset this adjustment")
          }
          Slider(
            value: Binding(
              get: { Double(model.simpleTones[i]) }, set: { model.setSimpleTone(i, Float($0)) }),
            in: -12...12, step: 0.5
          )
          .accessibilityLabel(["Bass", "Voices", "Detail"][i])
        }
      }
    }.padding(14).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
  }

  private var equalizer: some View {
    VStack(spacing: 16) {
      HStack {
        Text(model.preset.uppercased()).tracking(1.2)
        Spacer()
        Text("±12 dB")
      }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
      HStack(spacing: 5) {
        ForEach(0..<10, id: \.self) { i in
          VStack(spacing: 10) {
            Text(
              String(
                format: model.gains[i].truncatingRemainder(dividingBy: 1) == 0 ? "%+.0f" : "%+.1f",
                model.gains[i])
            )
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            VerticalFader(
              value: Binding(get: { Double(model.gains[i]) }, set: { model.setBand(i, Float($0)) }),
              label: frequencies[i]
            )
            .frame(height: 112)
            Text(labels[i]).font(.system(size: 10, weight: .medium, design: .monospaced))
          }.frame(maxWidth: .infinity)
        }
      }
    }
    .padding(16).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
  }

  private var appPicker: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Choose apps").font(.system(size: 16, weight: .semibold))
          Text("\(model.selectedBundleIDs.count) selected · changes apply immediately")
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Done") { model.choosingApps = false }.buttonStyle(.borderedProminent).controlSize(
          .small)
      }
      TextField("Search apps", text: $model.appSearch).textFieldStyle(.roundedBorder)
      ForEach(
        model.appChoices.filter {
          model.appSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(model.appSearch)
        }
      ) { app in
        Toggle(
          isOn: Binding(
            get: { model.selectedBundleIDs.contains(app.id) },
            set: { model.selectApp(app.id, enabled: $0) })
        ) {
          HStack(spacing: 10) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) {
              Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(
                width: 25, height: 25)
            }
            VStack(alignment: .leading, spacing: 2) {
              Text(app.name).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
              if !app.running {
                Text(
                  model.selectedBundleIDs.contains(app.id)
                    ? "Not running · will reconnect" : "Not running"
                )
                .font(.system(size: 10)).foregroundStyle(.secondary)
              }
            }
          }
        }.toggleStyle(.checkbox).padding(.vertical, 4)
      }
      Text("Launch another app to add it here. Unselected apps play normally.")
        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
    }
  }

  private var soundControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle(isOn: Binding(get: { model.loudnessBoost }, set: model.setLoudnessBoost)) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Keep volume").font(.system(size: 12, weight: .semibold))
          Text("Fully compensates for EQ volume loss.")
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .toggleStyle(.switch).accessibilityLabel("Keep volume")
      .help(
        "Restores the full automatic EQ attenuation. Peak protection stays on; very strong bass can still cause compression."
      )
      HStack(spacing: 12) {
        Text("Output").font(.system(size: 12, weight: .medium)).frame(
          width: 44, alignment: .leading)
        Slider(
          value: Binding(
            get: { Double(model.outputGain) }, set: { model.setOutputGain(Float($0)) }),
          in: -12...12, step: 0.5
        )
        .accessibilityLabel("Output gain")
        .accessibilityValue(String(format: "%.1f decibels", model.outputGain))
        Button {
          model.setOutputGain(0)
        } label: {
          Text(String(format: "%+.1f dB", model.outputGain)).font(
            .system(size: 11, design: .monospaced)
          )
          .frame(width: 64, alignment: .trailing)
        }.buttonStyle(.plain).help("Reset output to 0 dB")
      }
      Text(
        model.limiting
          ? "Peak protection is controlling loud peaks. More gain may add compression."
          : "Raise output for more level. Peak protection is always on."
      )
      .font(.system(size: 10)).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var powerBar: some View {
    HStack {
      HStack(spacing: 7) {
        Circle().fill(model.enabled ? (model.waitingForApps ? Color.orange : accent) : Color.gray)
          .frame(width: 7, height: 7)
        Text(model.statusText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
          .help(model.statusText)
      }
      Spacer()
      Toggle(
        model.enabled || model.restarting ? "On" : "Off",
        isOn: Binding(get: { model.enabled || model.restarting }, set: model.setEnabled)
      )
      .toggleStyle(.switch).font(.system(size: 12, weight: .semibold))
      .accessibilityLabel("Enable equalizer")
    }
  }
}

struct VerticalFader: View {
  @Binding var value: Double
  let label: String
  var body: some View {
    GeometryReader { geometry in
      let height = geometry.size.height - 16
      let y = 8 + (12 - value) / 24 * height
      ZStack(alignment: .top) {
        Capsule().fill(Color.primary.opacity(0.09)).frame(width: 4, height: height).offset(y: 8)
        Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 12, height: 1).offset(
          y: geometry.size.height / 2)
        Capsule().fill(Color.mint.opacity(0.7)).frame(
          width: 4, height: max(1, abs(y - geometry.size.height / 2))
        )
        .offset(y: min(y, geometry.size.height / 2))
        RoundedRectangle(cornerRadius: 4).fill(Color.primary).frame(width: 20, height: 12).shadow(
          color: .black.opacity(0.15), radius: 2, y: 1
        ).offset(y: y - 6)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0).onChanged { event in
          let next = 12.0 - Double((event.location.y - 8) / height) * 24.0
          value = (min(12.0, max(-12.0, next)) * 2.0).rounded() / 2.0
        })
    }
    .accessibilityElement().accessibilityLabel(label).accessibilityValue(
      String(format: "%.1f decibels", value)
    )
    .accessibilityAdjustableAction { direction in
      if direction == .increment { value = min(12, value + 0.5) }
      if direction == .decrement { value = max(-12, value - 0.5) }
    }
    .simultaneousGesture(TapGesture(count: 2).onEnded { value = 0 })
    .accessibilityAction(named: Text("Reset to zero")) { value = 0 }
    .help("\(label): \(String(format: "%.1f", value)) dB")
  }
}
