import AppKit

@main
struct LaunchServicesTests {
  @MainActor static func main() {
    let arguments = CommandLine.arguments
    let domain = "dev.elma.eqmini.launch-tests." + UUID().uuidString
    let preferences = UserDefaults(suiteName: domain)!
    preferences.set(true, forKey: "legacyPreferencesMigrated")
    preferences.set(false, forKey: "restoreOnLaunch")
    if arguments.contains("--previously-opened") {
      preferences.set(true, forKey: "welcomeWindowShown")
    }
    let application = NSApplication.shared
    let delegate = AppDelegate(preferences: preferences)
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    var samples: [Bool] = []
    Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
      MainActor.assumeIsolated {
        samples.append(delegate.equalizerWindow?.isVisible == true)
        guard samples.count == 20 else { return }
        timer.invalidate()
        let expected =
          !arguments.contains("--login-launch") && !arguments.contains("--previously-opened")
        let passed =
          samples.suffix(8).allSatisfy { $0 == expected }
          && !delegate.popover.isShown && delegate.model?.enabled == false
        if let index = arguments.firstIndex(of: "--report"), index + 1 < arguments.count {
          let report: [String: Any] = [
            "passed": passed, "expectedWindow": expected, "visibleSamples": samples,
          ]
          if let data = try? JSONSerialization.data(withJSONObject: report) {
            try? data.write(to: URL(fileURLWithPath: arguments[index + 1]))
          }
        }
        UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain)
        delegate.exitCode = passed ? 0 : 1
        application.terminate(nil)
      }
    }
    application.run()
    withExtendedLifetime(delegate) {}
    exit(delegate.exitCode)
  }
}
