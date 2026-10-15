import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
enum MacEqualizerApp {
  @MainActor static func main() {
    if CommandLine.arguments.contains("--list-audio-apps") {
      print(String(cString: EQAudioProcessesJSON()))
      return
    }
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(
      CommandLine.arguments.contains("--window") ? .regular : .accessory)
    application.run()
    withExtendedLifetime(delegate) {}
    exit(delegate.exitCode)
  }
}
