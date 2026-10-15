import AppKit
import Combine
import ServiceManagement
import SwiftUI

enum AppPreferences {
  static func migrateLegacy(to preferences: UserDefaults, legacy: [String: Any]?) {
    guard !preferences.bool(forKey: "legacyPreferencesMigrated") else { return }
    let keys = [
      "gains", "preset", "customGains", "loudnessBoost", "outputGain", "selectedOnly",
      "selectedBundleIDs", "selectedAppNames", "simpleMode", "speakerBass", "simpleBase",
      "simpleTones", "simpleMappingVersion", "restoreOnLaunch", "lastRequestedEnabled",
    ]
    for key in keys where preferences.object(forKey: key) == nil {
      if let value = legacy?[key] { preferences.set(value, forKey: key) }
    }
    preferences.set(true, forKey: "legacyPreferencesMigrated")
  }
}

struct AudioProcess: Decodable {
  let id: UInt32
  let bundleID: String
  let name: String
  let runningOutput: Bool?
}
struct AudioInventory: Decodable {
  let processes: [AudioProcess]
  let status: Int32
}
struct AppChoice: Identifiable, Equatable {
  let id: String
  let name: String
  let running: Bool
}

enum Preset: String, CaseIterable {
  case flat = "Flat"
  case bass = "Bass Boost"
  case warm = "MacBook Warm"
  var gains: [Float] {
    switch self {
    case .flat: return Array(repeating: 0, count: 10)
    case .bass: return [0, 3, 8, 5, 0, -1, 0, 1, 0, 0]
    case .warm: return [-3, 0, 3, 2, -1, -1, 0, 1, 0, 0]
    }
  }
}

enum SimpleEQ {
  static let weights: [[Float]] = [
    [0, 0.4, 1, 0.6, 0.1, 0, 0, 0, 0, 0],
    [0, 0, -0.1, -0.15, 0.3, 0.7, 1, 0.35, 0, 0],
    [0, 0, 0, 0, -0.1, 0, 0.15, 0.65, 1, 0.5],
  ]
  static func curve(base: [Float], tones: [Float]) -> [Float] {
    (0..<10).map { b in
      min(12, max(-12, base[b] + (0..<3).reduce(Float(0)) { $0 + tones[$1] * weights[$1][b] }))
    }
  }
  static func tones(for gains: [Float]) -> [Float] {
    // Fit three broad tone controls to the existing curve. Preserve the
    // remaining fine-band shape separately, so changing views is lossless.
    var rows = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 3)
    for i in 0..<3 {
      for b in 0..<10 {
        rows[i][3] += weights[i][b] * gains[b]
        for j in 0..<3 { rows[i][j] += weights[i][b] * weights[j][b] }
      }
    }
    for i in 0..<3 {
      let divisor = rows[i][i]
      for j in i..<4 { rows[i][j] /= divisor }
      for k in 0..<3 where k != i {
        let factor = rows[k][i]
        for j in i..<4 { rows[k][j] -= factor * rows[i][j] }
      }
    }
    return rows.map { min(12, max(-12, ($0[3] * 2).rounded() / 2)) }
  }
  static func residual(gains: [Float], tones: [Float]) -> [Float] {
    (0..<10).map { b in gains[b] - (0..<3).reduce(Float(0)) { $0 + tones[$1] * weights[$1][b] } }
  }
}

// A tap may stop receiving callbacks while its source is paused. Only treat a
// sustained stall during confirmed playback as a route failure.
struct PlaybackWatchdog {
  private var stalledSince: TimeInterval?
  mutating func shouldRecover(callbacksHealthy: Bool, sourcePlaying: Bool?, now: TimeInterval)
    -> Bool
  {
    guard sourcePlaying == true, !callbacksHealthy else {
      stalledSince = nil
      return false
    }
    guard let stalledSince else {
      self.stalledSince = now
      return false
    }
    return now - stalledSince >= 5
  }
}

@MainActor
final class EqualizerModel: ObservableObject {
  @Published var enabled = false
  @Published private(set) var needsAudioExplanation = false
  @Published var gains: [Float]
  @Published var preset: String
  @Published var customGains: [Float]?
  @Published var output = "System output"
  @Published var error: String?
  @Published private(set) var audioPermissionDenied = false
  @Published var headroom: Float = 0
  @Published var limiting = false
  @Published var restarting = false
  @Published var loudnessBoost = false
  @Published var outputGain: Float = 0
  @Published var limiterReduction: Float = 0
  @Published var appSearch = ""
  @Published var selectedOnly = false
  @Published var selectedBundleIDs = Set<String>()
  @Published var appChoices: [AppChoice] = []
  @Published var choosingApps = false
  @Published var waitingForApps = false
  @Published var simpleMode = true
  @Published var simpleTones: [Float] = [0, 0, 0]
  @Published var speakerBass = false
  @Published private(set) var restoreOnLaunch = false
  private var processes: [AudioProcess] = []
  private var inventoryStatus: Int32 = 0
  private var inventoryUpdatedAt: TimeInterval = 0
  private var activeProcessIDs: [UInt32] = []
  private let preferences: UserDefaults
  private var simpleBase: [Float] = []
  private var routeActive = false
  private var playbackWatchdog = PlaybackWatchdog()
  private let audioQueue = DispatchQueue(label: "eqmini.audio-control", qos: .userInitiated)
  private var audioGeneration = 0
  private var inventoryLoading = false
  private var requested = false
  private var sleeping = false
  private var device: UInt32 = 0
  private var timer: Timer?
  private var restartWork: DispatchWorkItem?
  private var observers: [NSObjectProtocol] = []

  init(preferences: UserDefaults = .standard, monitoring: Bool = true) {
    self.preferences = preferences
    restoreOnLaunch = preferences.bool(forKey: "restoreOnLaunch")
    let saved = preferences.array(forKey: "gains") as? [Float]
    gains =
      saved?.count == 10 && saved!.allSatisfy({ $0.isFinite && abs($0) <= 12 })
      ? saved! : Preset.warm.gains
    preset = preferences.string(forKey: "preset") ?? Preset.warm.rawValue
    if let custom = preferences.array(forKey: "customGains") as? [Float],
      custom.count == 10, custom.allSatisfy({ $0.isFinite && abs($0) <= 12 })
    {
      customGains = custom
    } else if preset == "Custom" {
      customGains = gains
    }
    for i in 0..<10 { EQSetBand(Int32(i), gains[i]) }
    loudnessBoost = preferences.bool(forKey: "loudnessBoost")
    EQSetLoudnessBoost(loudnessBoost)
    let savedOutput = preferences.float(forKey: "outputGain")
    outputGain = savedOutput.isFinite ? min(12, max(-12, savedOutput)) : 0
    EQSetOutputGain(outputGain)
    selectedOnly = preferences.bool(forKey: "selectedOnly")
    selectedBundleIDs = Set(preferences.stringArray(forKey: "selectedBundleIDs") ?? [])
    simpleMode = preferences.object(forKey: "simpleMode") as? Bool ?? true
    speakerBass = preferences.bool(forKey: "speakerBass")
    EQSetSpeakerBass(speakerBass ? 0.85 : 0)
    if preferences.integer(forKey: "simpleMappingVersion") == 2,
      let base = preferences.array(forKey: "simpleBase") as? [Float],
      let tones = preferences.array(forKey: "simpleTones") as? [Float],
      base.count == 10, tones.count == 3,
      base.allSatisfy({ $0.isFinite && abs($0) <= 48 }),
      tones.allSatisfy({ $0.isFinite && abs($0) <= 12 }),
      zip(SimpleEQ.curve(base: base, tones: tones), gains).allSatisfy({ abs($0.0 - $0.1) < 0.01 })
    {
      simpleBase = base
      simpleTones = tones
    } else {
      syncSimpleFromGains()
    }
    guard monitoring else { return }
    refreshApps()
    // Launch restoration is requested by the app delegate after UI setup.
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.poll() }
    }
    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.sleeping = true
          self.restartWork?.cancel()
          self.stopAudio()
          self.enabled = false
        }
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          self?.sleeping = false
          if self?.requested == true { self?.scheduleRestart() }
        }
      })
  }
  // Reconfirm after an app update: earlier builds may have been run with a
  // different signing identity, for which macOS grants separate capture access.
  static var audioExplanationRevision: String {
    "2:" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development")
  }
  var hasAcceptedAudioExplanation: Bool {
    preferences.string(forKey: "audioExplanationRevision") == Self.audioExplanationRevision
  }
  var enabledOrConnecting: Bool { enabled || restarting }
  func setEnabled(_ value: Bool) {
    if value && !hasAcceptedAudioExplanation {
      needsAudioExplanation = true
      return
    }
    needsAudioExplanation = false
    requested = value
    preferences.set(value, forKey: "lastRequestedEnabled")
    restartWork?.cancel()
    restarting = false
    if value {
      start()
    } else {
      stopAudio()
      enabled = false
      waitingForApps = false
      error = nil
    }
  }
  func resolveAudioExplanation(proceed: Bool) {
    needsAudioExplanation = false
    guard proceed else {
      preferences.set(false, forKey: "lastRequestedEnabled")
      return
    }
    preferences.set(true, forKey: "audioExplanationAccepted")
    preferences.set(Self.audioExplanationRevision, forKey: "audioExplanationRevision")
    setEnabled(true)
  }
  var shouldRestoreOnLaunch: Bool {
    restoreOnLaunch && preferences.bool(forKey: "lastRequestedEnabled")
  }
  func setRestoreOnLaunch(_ value: Bool) {
    restoreOnLaunch = value
    preferences.set(value, forKey: "restoreOnLaunch")
    preferences.set(requested, forKey: "lastRequestedEnabled")
  }
  private func stopAudio() {
    audioGeneration += 1
    routeActive = false
    playbackWatchdog = PlaybackWatchdog()
    audioQueue.async { EQStop() }
  }
  private func start() {
    error = nil
    audioPermissionDenied = false
    playbackWatchdog = PlaybackWatchdog()
    refreshApps()
    if selectedOnly && inventoryStatus != 0 {
      stopAudio()
      enabled = false
      requested = false
      restarting = false
      preferences.set(false, forKey: "lastRequestedEnabled")
      error = "Could not read audio apps. Try enabling again."
      return
    }
    activeProcessIDs = matchingProcessIDs
    if selectedOnly && activeProcessIDs.isEmpty {
      stopAudio()
      waitingForApps = true
      enabled = true
      restarting = false
      return
    }
    waitingForApps = false
    audioGeneration += 1
    let generation = audioGeneration
    let ids = activeProcessIDs
    let onlySelected = selectedOnly
    routeActive = false
    restarting = true
    // HAL setup can synchronously call back into macOS. Keep it off AppKit's
    // event/accessibility stack and serialize starts/stops so routes never overlap.
    audioQueue.async { [weak self] in
      let started =
        onlySelected
        ? ids.withUnsafeBufferPointer { EQStartSelected($0.baseAddress, UInt32($0.count)) }
        : EQStart()
      let outputDevice = EQDefaultOutput()
      let outputName = String(cString: EQOutputName())
      let failure = String(cString: EQError())
      let permissionDenied = EQPermissionDenied()
      DispatchQueue.main.async {
        guard let self, self.audioGeneration == generation else { return }
        self.restarting = false
        if started {
          self.device = outputDevice
          self.output = outputName
          self.enabled = true
          self.routeActive = true
        } else {
          self.enabled = false
          self.routeActive = false
          self.requested = false
          self.error = failure
          self.audioPermissionDenied = permissionDenied
          self.preferences.set(false, forKey: "lastRequestedEnabled")
        }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
      guard let self, self.restarting, self.audioGeneration == generation else { return }
      self.stopAudio()
      self.enabled = false
      self.restarting = false
      self.requested = false
      self.preferences.set(false, forKey: "lastRequestedEnabled")
      self.error = "Audio setup timed out. Quit eqmini and reopen it, then try again."
    }
  }
  private func scheduleRestart() {
    restartWork?.cancel()
    stopAudio()
    enabled = false
    restarting = true
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.requested, !self.sleeping else { return }
      self.restarting = false
      self.start()
    }
    restartWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
  }
  private func poll() {
    refreshApps()
    if selectedOnly && requested && !sleeping && !restarting
      && (matchingProcessIDs != activeProcessIDs || inventoryStatus != 0)
    {
      start()
    }
    guard enabled else { return }
    guard routeActive else { return }
    headroom = EQHeadroom()
    limiterReduction = EQReduction()
    limiting = limiterReduction > 0.5
    if EQDefaultOutput() != device || EQOutputChanged() {
      scheduleRestart()
    } else if playbackWatchdog.shouldRecover(
      callbacksHealthy: EQHealthy(), sourcePlaying: sourcePlaying,
      now: ProcessInfo.processInfo.systemUptime)
    {
      stopAudio()
      enabled = false
      requested = false
      preferences.set(false, forKey: "lastRequestedEnabled")
      error = "Audio stopped responding. Normal playback has been restored. Try enabling again."
    }
  }
  private var sourcePlaying: Bool? {
    guard inventoryStatus == 0,
      ProcessInfo.processInfo.systemUptime - inventoryUpdatedAt < 2
    else { return nil }
    let sources =
      selectedOnly
      ? processes.filter { selectedBundleIDs.contains($0.bundleID) } : processes
    if sources.contains(where: { $0.runningOutput == true }) { return true }
    if sources.contains(where: { $0.runningOutput == nil }) { return nil }
    return false
  }
  private var matchingProcessIDs: [UInt32] {
    Array(Set(processes.filter { selectedBundleIDs.contains($0.bundleID) }.map(\.id))).sorted()
  }
  var scopeSummary: String {
    selectedBundleIDs.isEmpty
      ? "Choose apps to equalize"
      : appChoices.filter { selectedBundleIDs.contains($0.id) }.map(\.name).joined(separator: ", ")
  }
  var statusText: String {
    if restarting { return "Connecting audio…" }
    if waitingForApps {
      return selectedBundleIDs.isEmpty ? "No apps selected" : "Waiting for selected apps"
    }
    if !enabled { return "Bypassed" }
    return limiting ? String(format: "Peak protection · %.1f dB", limiterReduction) : "EQ active"
  }
  func setSelectedOnly(_ value: Bool) {
    selectedOnly = value
    preferences.set(value, forKey: "selectedOnly")
    reconfigureSelection()
  }
  func selectApp(_ id: String, enabled: Bool) {
    if enabled { selectedBundleIDs.insert(id) } else { selectedBundleIDs.remove(id) }
    preferences.set(selectedBundleIDs.sorted(), forKey: "selectedBundleIDs")
    var names = preferences.dictionary(forKey: "selectedAppNames") as? [String: String] ?? [:]
    for choice in appChoices where selectedBundleIDs.contains(choice.id) {
      names[choice.id] = choice.name
    }
    preferences.set(names, forKey: "selectedAppNames")
    refreshApps()
    reconfigureSelection()
  }
  private func reconfigureSelection() {
    guard requested && !sleeping else { return }
    restartWork?.cancel()
    restarting = false
    start()
  }
  private func refreshApps() {
    guard !inventoryLoading else { return }
    inventoryLoading = true
    audioQueue.async { [weak self] in
      let data = Data(String(cString: EQAudioProcessesJSON()).utf8)
      let inventory = try? JSONDecoder().decode(AudioInventory.self, from: data)
      DispatchQueue.main.async {
        guard let self else { return }
        self.inventoryLoading = false
        self.processes = inventory?.processes ?? []
        self.inventoryStatus = inventory?.status ?? -1
        self.inventoryUpdatedAt = ProcessInfo.processInfo.systemUptime
        self.updateAppChoices()
      }
    }
  }
  private func updateAppChoices() {
    var choices: [String: AppChoice] = [:]
    let savedNames = preferences.dictionary(forKey: "selectedAppNames") as? [String: String] ?? [:]
    for id in selectedBundleIDs.union(["com.spotify.client", "com.apple.Music"]) {
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
      if url != nil || selectedBundleIDs.contains(id) {
        let name = url?.deletingPathExtension().lastPathComponent ?? savedNames[id] ?? id
        choices[id] = AppChoice(id: id, name: name, running: false)
      }
    }
    for process in processes {
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: process.bundleID),
        url.pathExtension == "app", url.path.contains("/Applications/"),
        !url.path.contains("/Contents/")
      {
        choices[process.bundleID] = AppChoice(
          id: process.bundleID, name: process.name, running: true)
      }
    }
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
      guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
      choices[id] = AppChoice(id: id, name: app.localizedName ?? id, running: true)
    }
    let sorted = choices.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    if sorted != appChoices { appChoices = sorted }
  }
  func setBand(_ index: Int, _ value: Float) {
    guard gains.indices.contains(index), value.isFinite else { return }
    let gain = min(12, max(-12, value))
    gains[index] = gain
    EQSetBand(Int32(index), gain)
    preset = "Custom"
    save()
    customGains = gains
    preferences.set(gains, forKey: "customGains")
    syncSimpleFromGains()
  }
  func setLoudnessBoost(_ value: Bool) {
    loudnessBoost = value
    EQSetLoudnessBoost(value)
    preferences.set(value, forKey: "loudnessBoost")
  }
  func setOutputGain(_ value: Float) {
    guard value.isFinite else { return }
    outputGain = min(12, max(-12, value))
    EQSetOutputGain(outputGain)
    preferences.set(outputGain, forKey: "outputGain")
  }
  func setSimpleMode(_ value: Bool) {
    simpleMode = value
    preferences.set(value, forKey: "simpleMode")
  }
  func setSpeakerBass(_ value: Bool) {
    speakerBass = value
    EQSetSpeakerBass(value ? 0.85 : 0)
    preferences.set(value, forKey: "speakerBass")
  }
  func setSimpleTone(_ index: Int, _ value: Float) {
    guard (0..<3).contains(index), value.isFinite else { return }
    simpleTones[index] = min(12, max(-12, value))
    gains = SimpleEQ.curve(base: simpleBase, tones: simpleTones)
    preset = "Custom"
    customGains = gains
    for i in 0..<10 { EQSetBand(Int32(i), gains[i]) }
    preferences.set(gains, forKey: "customGains")
    preferences.set(simpleTones, forKey: "simpleTones")
    preferences.set(simpleBase, forKey: "simpleBase")
    preferences.set(2, forKey: "simpleMappingVersion")
    save()
  }
  private func syncSimpleFromGains() {
    simpleTones = SimpleEQ.tones(for: gains)
    simpleBase = SimpleEQ.residual(gains: gains, tones: simpleTones)
    preferences.set(simpleBase, forKey: "simpleBase")
    preferences.set(simpleTones, forKey: "simpleTones")
    preferences.set(2, forKey: "simpleMappingVersion")
  }
  func resetEqualizer() {
    gains = Array(repeating: 0, count: 10)
    customGains = gains
    preset = Preset.flat.rawValue
    syncSimpleFromGains()
    setSpeakerBass(false)
    for i in 0..<10 { EQSetBand(Int32(i), 0) }
    preferences.set(gains, forKey: "customGains")
    save()
  }
  func apply(_ selected: Preset) {
    if preset == "Custom" {
      customGains = gains
      preferences.set(gains, forKey: "customGains")
    }
    gains = selected.gains
    preset = selected.rawValue
    syncSimpleFromGains()
    setSpeakerBass(selected == .bass)
    for i in 0..<10 { EQSetBand(Int32(i), gains[i]) }
    save()
  }
  func restoreCustom() {
    guard let customGains else { return }
    gains = customGains
    preset = "Custom"
    syncSimpleFromGains()
    for i in 0..<10 { EQSetBand(Int32(i), gains[i]) }
    save()
  }
  private func save() {
    preferences.set(gains, forKey: "gains")
    preferences.set(preset, forKey: "preset")
  }
  func shutdown(completion: (() -> Void)? = nil) {
    requested = false
    restartWork?.cancel()
    timer?.invalidate()
    stopAudio()
    if let completion { audioQueue.async { DispatchQueue.main.async(execute: completion) } }
  }
}
