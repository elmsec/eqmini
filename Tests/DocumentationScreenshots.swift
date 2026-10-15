import AppKit
import ServiceManagement
import SwiftUI

// Render the shipping views with isolated demo state; no screen capture or audio access.
@main
struct DocumentationScreenshots {
  @MainActor static func main() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    if let icon = NSImage(contentsOfFile: "build/eqMini.app/Contents/Resources/AppIcon.icns") {
      app.applicationIconImage = icon
    }
    let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let domain = "dev.elma.eqmini.screenshots." + UUID().uuidString
    let preferences = UserDefaults(suiteName: domain)!
    defer { preferences.removePersistentDomain(forName: domain) }
    let model = EqualizerModel(preferences: preferences, monitoring: false)
    try render(
      EqualizerPanel(model: model, panelHeight: 760), size: NSSize(width: 480, height: 760),
      to: destination.appendingPathComponent("initial.png"))
    model.apply(.bass)
    model.setLoudnessBoost(true)
    model.selectedOnly = true
    model.selectedBundleIDs = ["com.spotify.client", "com.apple.Music"]
    model.appChoices = [
      AppChoice(id: "com.spotify.client", name: "Spotify", running: false),
      AppChoice(id: "com.apple.Music", name: "Music", running: false),
    ]
    model.setSimpleMode(true)
    try render(
      EqualizerPanel(model: model, panelHeight: 760), size: NSSize(width: 480, height: 760),
      to: destination.appendingPathComponent("simple.png"))
    try render(
      EqualizerWindowContent(model: model), size: NSSize(width: 480, height: 820),
      to: destination.appendingPathComponent("window.png"))
    model.setSimpleMode(false)
    try render(
      EqualizerPanel(model: model, panelHeight: 760), size: NSSize(width: 480, height: 760),
      to: destination.appendingPathComponent("bands.png"))
    model.apply(.warm)
    try render(
      EqualizerPanel(model: model, panelHeight: 760), size: NSSize(width: 480, height: 760),
      to: destination.appendingPathComponent("warm.png"))
    model.setBand(2, 4)
    try render(
      EqualizerPanel(model: model, panelHeight: 760), size: NSSize(width: 480, height: 760),
      to: destination.appendingPathComponent("custom.png"))
    model.appChoices.append(AppChoice(id: "com.apple.Safari", name: "Safari", running: false))
    model.choosingApps = true
    try render(
      EqualizerPanel(model: model, panelHeight: 760), size: NSSize(width: 480, height: 760),
      to: destination.appendingPathComponent("apps.png"))
    model.appSearch = "Spotify"
    try render(
      EqualizerPanel(model: model, panelHeight: 760), size: NSSize(width: 480, height: 760),
      to: destination.appendingPathComponent("apps-search.png"))
    model.appSearch = ""
    model.choosingApps = false
    model.selectedBundleIDs = []
    model.apply(.flat)
    model.setSimpleMode(true)
    try render(
      EqualizerPanel(model: model, panelHeight: 760), size: NSSize(width: 480, height: 760),
      to: destination.appendingPathComponent("no-apps-selected.png"))
    struct DemoLoginItem: LoginItemManaging {
      var status: SMAppService.Status = .notRegistered
      func register() throws {}
      func unregister() throws {}
    }
    try render(
      EqualizerSettings(model: model, startup: StartupSettings(service: DemoLoginItem())),
      size: NSSize(width: 400, height: 430), to: destination.appendingPathComponent("settings.png"))
    model.setRestoreOnLaunch(true)
    try render(
      EqualizerSettings(
        model: model, startup: StartupSettings(service: DemoLoginItem(status: .enabled))),
      size: NSSize(width: 400, height: 430),
      to: destination.appendingPathComponent("settings-startup.png"))
    try render(
      AboutEqualizer(), size: NSSize(width: 424, height: 480),
      to: destination.appendingPathComponent("about.png"))
    let simple = NSImage(contentsOf: destination.appendingPathComponent("simple.png"))!
    let apps = NSImage(contentsOf: destination.appendingPathComponent("apps.png"))!
    let overview = HStack(spacing: 56) {
      ForEach(0..<2, id: \.self) { index in
        Image(nsImage: index == 0 ? simple : apps).resizable().interpolation(.high)
          .frame(width: 344, height: 344 * 760 / 480)
          .clipShape(RoundedRectangle(cornerRadius: 16))
          .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.16), lineWidth: 2)
          )
          .shadow(color: .black.opacity(0.4), radius: 24, y: 14)
      }
    }
    .frame(width: 960, height: 720)
    .background(
      LinearGradient(
        colors: [
          Color(red: 0.30, green: 0.15, blue: 0.40),
          Color(red: 0.10, green: 0.16, blue: 0.26),
          Color(red: 0.12, green: 0.30, blue: 0.28),
        ], startPoint: .topLeading, endPoint: .bottomTrailing))
    try render(
      overview, size: NSSize(width: 960, height: 720),
      to: destination.appendingPathComponent("overview.png"))
    print("Rendered isolated demo views to \(destination.path)")
  }
  @MainActor static func render<V: View>(_ root: V, size: NSSize, to url: URL) throws {
    let view = NSHostingView(
      rootView:
        root.frame(width: size.width, height: size.height)
        .environment(\.controlActiveState, .key)
        .background(Color(red: 0.075, green: 0.085, blue: 0.095)))
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered,
      defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = view
    window.setContentSize(size)
    view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      throw CocoaError(.fileWriteUnknown)
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
    window.orderOut(nil)
  }
}
