import AppKit
import SwiftUI

@main
struct InteractionTests {
  @MainActor static func main() {
    _ = NSApplication.shared
    let domain = "dev.elma.eqmini.interactions." + UUID().uuidString
    let preferences = UserDefaults(suiteName: domain)!
    defer { preferences.removePersistentDomain(forName: domain) }
    preferences.set(true, forKey: "audioExplanationAccepted")  // An older build's acknowledgement.
    preferences.set(true, forKey: "selectedOnly")
    let model = EqualizerModel(preferences: preferences, monitoring: false)
    let delegate = AppDelegate()
    delegate.model = model
    let menu = delegate.makeStatusMenu()
    precondition(menu.items.compactMap(\.title).contains("Open Equalizer"))
    precondition(menu.items.compactMap(\.title).contains("Settings…"))
    precondition(menu.items.compactMap(\.title).contains("Quit eqMini"))
    let enable = menu.items.first { $0.title == "Enable Equalizer" }!
    precondition(NSApp.sendAction(enable.action!, to: enable.target, from: enable))
    precondition(model.needsAudioExplanation && !model.enabled && !model.restarting)
    model.resolveAudioExplanation(proceed: false)
    precondition(!model.hasAcceptedAudioExplanation && !model.enabled)
    // The window's Equalizer menu uses the same selector as the status menu.
    precondition(NSApp.sendAction(#selector(AppDelegate.toggleEqualizer), to: delegate, from: nil))
    precondition(model.needsAudioExplanation && !model.enabled)
    model.resolveAudioExplanation(proceed: true)
    precondition(model.hasAcceptedAudioExplanation && model.enabled && model.waitingForApps)
    let disable = delegate.makeStatusMenu().items.first { $0.title == "Disable Equalizer" }!
    precondition(disable.state == .on)
    precondition(NSApp.sendAction(disable.action!, to: disable.target, from: disable))
    precondition(!model.enabled && !model.restarting)
    let reopened = EqualizerModel(preferences: preferences, monitoring: false)
    precondition(reopened.hasAcceptedAudioExplanation)
    reopened.setEnabled(true)
    precondition(!reopened.needsAudioExplanation && reopened.waitingForApps)
    reopened.setEnabled(false)
    model.shutdown()
    reopened.shutdown()
    print(
      "PASS: status/window menu enable requires current explanation; cancel bypasses; accept persists; menu bypass works without capture"
    )
  }
}
