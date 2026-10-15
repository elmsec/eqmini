import AppKit
import Combine
import ServiceManagement
import SwiftUI

struct EqualizerSettings: View {
  @ObservedObject var model: EqualizerModel
  @ObservedObject var startup: StartupSettings
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Make yourself at home.").font(.title2.bold())
        Text("Choose how eqmini starts.").foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 10) {
        Toggle(
          "Launch at login",
          isOn: Binding(get: { startup.registered }, set: startup.setLaunchAtLogin)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        Text("Start quietly in the menu bar when you sign in to your Mac.")
          .font(.callout).foregroundStyle(.secondary)
        if startup.status == .requiresApproval {
          Label("Approval needed in System Settings", systemImage: "exclamationmark.circle")
            .foregroundStyle(.orange)
          Button("Open System Settings…") { SMAppService.openSystemSettingsLoginItems() }
        }
        if !Bundle.main.bundlePath.hasPrefix("/Applications/")
          && !Bundle.main.bundlePath.hasPrefix(NSHomeDirectory() + "/Applications/")
        {
          Text("Keep eqmini in Applications before enabling launch at login.")
            .font(.caption).foregroundStyle(.secondary)
        }
        if let error = startup.error { Text(error).font(.callout).foregroundStyle(.orange) }
      }
      Divider()
      VStack(alignment: .leading, spacing: 10) {
        Toggle(
          "Restore EQ on launch",
          isOn: Binding(get: { model.restoreOnLaunch }, set: model.setRestoreOnLaunch))
        Text(
          "Turn EQ back on at launch if you left it enabled. Your sound settings are always saved."
        )
        .font(.callout).foregroundStyle(.secondary)
      }
      Divider()
      Label {
        Text("Closing the window keeps eqmini running in the menu bar. Choose Quit to stop it.")
      } icon: {
        Image(systemName: "menubar.rectangle")
      }
      .font(.callout).foregroundStyle(.secondary)
    }
    .toggleStyle(.switch).padding(28).frame(width: 400)
    .fixedSize(horizontal: false, vertical: true)
    .preferredColorScheme(.dark).tint(.mint)
    .onAppear { startup.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in startup.refresh() }
  }
}
