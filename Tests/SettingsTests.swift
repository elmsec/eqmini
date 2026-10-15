import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
enum SettingsTests {
  @MainActor static func main() {
    if CommandLine.arguments.contains("--startup-self-test") {
      final class FakeLoginItem: LoginItemManaging {
        var status: SMAppService.Status = .notRegistered
        var fail = false
        func register() throws {
          if fail { throw NSError(domain: "eqmini.test", code: 1) }
          status = .enabled
        }
        func unregister() throws {
          if fail { throw NSError(domain: "eqmini.test", code: 2) }
          status = .notRegistered
        }
      }
      let fake = FakeLoginItem()
      let startup = StartupSettings(service: FakeLoginItem())
      precondition(!startup.registered)
      let settings = StartupSettings(service: fake)
      settings.setLaunchAtLogin(true)
      precondition(settings.registered && settings.status == .enabled && settings.error == nil)
      fake.status = .requiresApproval
      settings.refresh()
      precondition(settings.registered && settings.status == .requiresApproval)
      settings.setLaunchAtLogin(false)
      precondition(!settings.registered)
      fake.fail = true
      settings.setLaunchAtLogin(true)
      precondition(!settings.registered && settings.error != nil)
      fake.fail = false
      settings.setLaunchAtLogin(true)
      fake.fail = true
      settings.setLaunchAtLogin(false)
      precondition(settings.registered && settings.error != nil)
      fake.status = .notRegistered
      settings.refresh()
      precondition(!settings.registered)  // A change made outside the app is reflected.
      let domain = "local.eqmini.startup-test." + UUID().uuidString
      let preferences = UserDefaults(suiteName: domain)!
      defer { preferences.removePersistentDomain(forName: domain) }
      let initial = EqualizerModel(preferences: preferences, monitoring: false)
      precondition(!initial.restoreOnLaunch && !initial.shouldRestoreOnLaunch)
      initial.setRestoreOnLaunch(true)
      precondition(!initial.shouldRestoreOnLaunch)
      preferences.set(true, forKey: "lastRequestedEnabled")
      let restored = EqualizerModel(preferences: preferences, monitoring: false)
      precondition(restored.restoreOnLaunch && restored.shouldRestoreOnLaunch)
      restored.shutdown()  // Normal shutdown must retain the previous enabled state.
      precondition(restored.shouldRestoreOnLaunch)
      restored.setEnabled(false)
      precondition(!restored.shouldRestoreOnLaunch)
      restored.setRestoreOnLaunch(false)
      preferences.set(true, forKey: "lastRequestedEnabled")
      let disabled = EqualizerModel(preferences: preferences, monitoring: false)
      precondition(!disabled.restoreOnLaunch && !disabled.shouldRestoreOnLaunch)
      print(
        "PASS: login-item registration/approval/external changes/errors; opt-in restore, bypass persistence, shutdown preservation; system login items untouched"
      )
      return
    }
    if CommandLine.arguments.contains("--settings-self-test") {
      let domain = "local.eqmini.settings-test." + UUID().uuidString
      let preferences = UserDefaults(suiteName: domain)!
      defer { preferences.removePersistentDomain(forName: domain) }
      preferences.set([Float](repeating: 2, count: 10), forKey: "gains")
      preferences.set("Custom", forKey: "preset")
      preferences.set(true, forKey: "selectedOnly")
      preferences.set(["com.spotify.client"], forKey: "selectedBundleIDs")
      preferences.set(Float(3), forKey: "outputGain")
      let model = EqualizerModel(preferences: preferences, monitoring: false)
      model.setEnabled(true)
      precondition(model.needsAudioExplanation && !model.enabled && !model.restarting)
      model.resolveAudioExplanation(proceed: false)
      precondition(!model.needsAudioExplanation && !model.enabled)
      precondition(!preferences.bool(forKey: "audioExplanationAccepted"))
      model.setEnabled(true)
      model.resolveAudioExplanation(proceed: true)
      // An empty process inventory and selected-only routing reach the waiting
      // state without creating a capture route in this isolated model.
      precondition(model.enabled && model.waitingForApps && !model.restarting)
      precondition(preferences.bool(forKey: "audioExplanationAccepted"))
      model.setEnabled(false)
      AppPreferences.migrateLegacy(
        to: preferences, legacy: ["preset": "Flat", "unrelated": "ignore"])
      precondition(preferences.string(forKey: "preset") == "Custom")
      precondition(preferences.object(forKey: "unrelated") == nil)
      let beforeInvalid = model.gains
      model.setBand(-1, 5)
      model.setBand(10, 5)
      model.setBand(0, .nan)
      model.setOutputGain(.infinity)
      precondition(model.gains == beforeInvalid && model.outputGain == 3)
      let initialBass = model.simpleTones[0]
      model.setSimpleTone(0, 4)
      precondition(abs(model.gains[2] - (2 + 4 - initialBass)) < 0.001 && model.gains[9] == 2)
      let adjusted = model.gains
      model.setSimpleMode(false)
      model.setSimpleMode(true)
      precondition(model.gains == adjusted)
      let reloaded = EqualizerModel(preferences: preferences, monitoring: false)
      precondition(reloaded.gains == adjusted && reloaded.simpleTones[0] == 4)
      reloaded.apply(.bass)
      precondition(reloaded.speakerBass && reloaded.simpleTones[0] > 6)
      let bassCurve = reloaded.gains
      let bassTones = reloaded.simpleTones
      reloaded.setSimpleMode(false)
      reloaded.setSimpleMode(true)
      precondition(reloaded.gains == bassCurve && reloaded.simpleTones == bassTones)
      reloaded.restoreCustom()
      precondition(reloaded.gains == adjusted)
      reloaded.resetEqualizer()
      precondition(reloaded.gains.allSatisfy { $0 == 0 })
      precondition(reloaded.simpleTones == [0, 0, 0] && !reloaded.speakerBass)
      precondition(
        reloaded.outputGain == 3 && reloaded.selectedOnly
          && reloaded.selectedBundleIDs == ["com.spotify.client"])
      reloaded.restoreCustom()
      precondition(reloaded.gains.allSatisfy { $0 == 0 })
      let resetReloaded = EqualizerModel(preferences: preferences, monitoring: false)
      precondition(
        resetReloaded.gains.allSatisfy { $0 == 0 }
          && resetReloaded.customGains!.allSatisfy { $0 == 0 })
      // Migrate the old relative-control representation without changing sound.
      preferences.set(Preset.bass.gains, forKey: "gains")
      preferences.set(Preset.bass.rawValue, forKey: "preset")
      preferences.set(Preset.bass.gains, forKey: "simpleBase")
      preferences.set([Float](repeating: 0, count: 3), forKey: "simpleTones")
      preferences.removeObject(forKey: "simpleMappingVersion")
      let migrated = EqualizerModel(preferences: preferences, monitoring: false)
      precondition(migrated.gains == Preset.bass.gains && migrated.simpleTones[0] > 6)
      migrated.setBand(2, 10)
      precondition(migrated.simpleTones[0] > 7 && migrated.gains[2] == 10)
      migrated.apply(.warm)
      precondition(migrated.simpleTones[0] > 1)
      migrated.apply(.flat)
      precondition(migrated.simpleTones == [0, 0, 0])
      print(
        "PASS: preset-aware Simple values, exact mode-switch equivalence, legacy migration, advanced edits, persistence, Custom reset, routing/output preserved"
      )
      return
    }
    fatalError("Choose --settings-self-test or --startup-self-test")
  }
}
