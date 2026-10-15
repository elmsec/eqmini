import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  var model: EqualizerModel?
  var item: NSStatusItem?
  let popover = NSPopover()
  var equalizerWindow: NSWindow?
  var aboutWindow: NSWindow?
  var settingsWindow: NSWindow?
  let startupSettings = StartupSettings()
  private var quietLaunch = false
  private var audioExplanationObserver: AnyCancellable?
  private var panelController: NSHostingController<EqualizerPanel>?
  private var panelHeight: CGFloat {
    let screen = item?.button?.window?.screen ?? NSScreen.main
    return min(760, max(360, (screen?.visibleFrame.height ?? 800) - 24))
  }
  var exitCode: Int32 = 0
  func applicationDidFinishLaunching(_ notification: Notification) {
    if CommandLine.arguments.contains("--audio-self-test") {
      runAudioSelfTest(cycle: 0)
      return
    }
    if CommandLine.arguments.contains("--control-self-test") {
      runControlSelfTest()
      return
    }
    AppPreferences.migrateLegacy(
      to: .standard,
      legacy: UserDefaults.standard.persistentDomain(forName: "local.mac-equalizer.app"))
    let model = EqualizerModel()
    self.model = model
    audioExplanationObserver = model.$needsAudioExplanation
      .receive(on: DispatchQueue.main)
      .sink { [weak self] needed in
        if needed { self?.explainAudioAccess() }
      }
    let launchEvent = NSAppleEventManager.shared().currentAppleEvent
    quietLaunch =
      launchEvent?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
      == OSType(keyAELaunchedAsLogInItem)
      || CommandLine.arguments.contains("--login-launch")
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    self.item = item
    item.button?.image = Self.menuBarIcon()
    item.button?.toolTip = "eqmini — Equalizer"
    item.button?.target = self
    item.button?.action = #selector(statusItemClicked(_:))
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    let controller = NSHostingController(
      rootView: EqualizerPanel(model: model, panelHeight: panelHeight))
    panelController = controller
    // Keep AppKit and SwiftUI in agreement before the popover is positioned.
    // Automatic intrinsic resizing can otherwise push its header above the screen.
    controller.sizingOptions = []
    controller.preferredContentSize = NSSize(width: 480, height: panelHeight)
    popover.contentViewController = controller
    popover.contentSize = NSSize(width: 480, height: panelHeight)
    popover.behavior = .transient
    installMainMenu()
    if !quietLaunch || CommandLine.arguments.contains("--window") {
      DispatchQueue.main.async { [self] in
        showEqualizerWindow()
        if model.shouldRestoreOnLaunch { model.setEnabled(true) }
      }
    } else if model.shouldRestoreOnLaunch && model.hasAcceptedAudioExplanation {
      model.setEnabled(true)
    }
  }
  private func explainAudioAccess() {
    guard let model, model.needsAudioExplanation else { return }
    popover.performClose(nil)
    let alert = NSAlert()
    alert.messageText = "Allow sound processing"
    alert.informativeText = """
      eqmini needs macOS System Audio Recording access to apply the equalizer to your sound.

      Audio is processed live on your Mac. eqmini does not save recordings, capture your screen, or make network requests. Nothing is uploaded.

      After Continue, macOS may ask for permission. You can revoke access later in System Settings → Privacy & Security.
      """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Not Now")
    NSApp.activate(ignoringOtherApps: true)
    model.resolveAudioExplanation(proceed: alert.runModal() == .alertFirstButtonReturn)
  }
  @objc func showSettings() {
    guard let model else { return }
    popover.performClose(nil)
    startupSettings.refresh()
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = "eqmini Settings"
      window.contentViewController = NSHostingController(
        rootView: EqualizerSettings(model: model, startup: startupSettings))
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.center()
      settingsWindow = window
    }
    NSApp.setActivationPolicy(.regular)
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  private static func menuBarIcon() -> NSImage {
    // Three shaped faders stay legible at menu-bar size and in either appearance.
    let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
      NSColor.black.setStroke()
      NSColor.black.setFill()
      for (x, knob) in [
        (CGFloat(4), CGFloat(11)), (CGFloat(10), CGFloat(6)), (CGFloat(16), CGFloat(10)),
      ] {
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: x, y: 2))
        path.line(to: NSPoint(x: x, y: 16))
        path.stroke()
        NSBezierPath(
          roundedRect: NSRect(x: x - 2.4, y: knob - 1.7, width: 4.8, height: 3.4), xRadius: 1.3,
          yRadius: 1.3
        ).fill()
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "eqmini"
    return image
  }
  @objc func showEqualizerWindow() {
    guard let model else { return }
    popover.performClose(nil)
    if equalizerWindow == nil {
      let height = min(780, (NSScreen.main?.visibleFrame.height ?? 840) - 48)
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: height),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
        defer: false)
      window.title = "eqmini"
      window.contentViewController = NSHostingController(
        rootView: EqualizerWindowContent(model: model))
      window.minSize = NSSize(width: 480, height: 560)
      window.maxSize = NSSize(width: 480, height: 1200)
      window.setFrameAutosaveName("EqualizerWindow")
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.setContentSize(NSSize(width: 480, height: height))
      window.center()
      equalizerWindow = window
    }
    NSApp.setActivationPolicy(.regular)
    equalizerWindow?.deminiaturize(nil)
    equalizerWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc func showAbout() {
    popover.performClose(nil)
    if aboutWindow == nil {
      let window = NSWindow(
        contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = "About eqmini"
      window.contentViewController = NSHostingController(rootView: AboutEqualizer())
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.center()
      aboutWindow = window
    }
    NSApp.setActivationPolicy(.regular)
    aboutWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  func windowWillClose(_ notification: Notification) {
    let closing = notification.object as? NSWindow
    let otherVisible = [equalizerWindow, aboutWindow, settingsWindow].compactMap { $0 }.contains {
      $0 !== closing && $0.isVisible
    }
    if !otherVisible { NSApp.setActivationPolicy(.accessory) }
  }
  @objc func toggleEqualizer() {
    if let model { model.setEnabled(!model.enabledOrConnecting) }
  }
  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
      popover.performClose(nil)
      item?.menu = makeStatusMenu()
      sender.performClick(nil)
      item?.menu = nil
    } else {
      togglePanel()
    }
  }
  func makeStatusMenu() -> NSMenu {
    let menu = NSMenu()
    @discardableResult
    func add(_ title: String, _ action: Selector) -> NSMenuItem {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
      return item
    }
    add("Open Equalizer", #selector(showEqualizerWindow)).keyEquivalent = "o"
    menu.addItem(.separator())
    let active = model?.enabledOrConnecting == true
    add(active ? "Bypass Equalizer" : "Enable Equalizer", #selector(toggleEqualizer))
      .state = active ? .on : .off
    menu.addItem(.separator())
    add("Settings…", #selector(showSettings)).keyEquivalent = ","
    add("About eqmini", #selector(showAbout))
    menu.addItem(.separator())
    let quit = add("Quit eqmini", #selector(NSApplication.terminate(_:)))
    quit.target = NSApp
    quit.keyEquivalent = "q"
    return menu
  }
  @objc private func resetEqualizer() { model?.resetEqualizer() }
  @objc private func useSimple() { model?.setSimpleMode(true) }
  @objc private func useBands() { model?.setSimpleMode(false) }
  @objc private func openWebsite() { NSWorkspace.shared.open(AppLinks.website) }
  @objc private func openPrivacy() { NSWorkspace.shared.open(AppLinks.privacy) }
  @objc private func openTerms() { NSWorkspace.shared.open(AppLinks.terms) }
  private func installMainMenu() {
    let main = NSMenu()
    func submenu(_ title: String) -> NSMenu {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      let menu = NSMenu(title: title)
      item.submenu = menu
      main.addItem(item)
      return menu
    }
    func add(
      _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
      target: AnyObject? = nil
    ) {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.target = target ?? self
      menu.addItem(item)
    }
    let app = submenu("eqmini")
    add(app, "About eqmini", #selector(showAbout))
    app.addItem(.separator())
    add(app, "Settings…", #selector(showSettings), ",")
    app.addItem(.separator())
    add(app, "Hide eqmini", #selector(NSApplication.hide(_:)), "h", target: NSApp)
    app.addItem(.separator())
    add(app, "Quit eqmini", #selector(NSApplication.terminate(_:)), "q", target: NSApp)
    let eq = submenu("Equalizer")
    add(eq, "Enable / Bypass", #selector(toggleEqualizer), "e")
    add(eq, "Reset Equalizer", #selector(resetEqualizer))
    let edit = submenu("Edit")
    for (title, action, key) in [
      ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
      ("Select All", "selectAll:", "a"),
    ] {
      edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
    }
    let view = submenu("View")
    add(view, "Simple Controls", #selector(useSimple), "1")
    add(view, "10 Bands", #selector(useBands), "2")
    let window = submenu("Window")
    add(window, "Open Equalizer", #selector(showEqualizerWindow), "o")
    add(window, "Close", #selector(NSWindow.performClose(_:)), "w", target: nil)
    window.items.last?.target = nil
    let minimize = NSMenuItem(
      title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    window.addItem(minimize)
    NSApp.windowsMenu = window
    let help = submenu("Help")
    add(help, "eqmini Website", #selector(openWebsite))
    add(help, "Privacy Policy", #selector(openPrivacy))
    add(help, "Terms of Use", #selector(openTerms))
    NSApp.helpMenu = help
    NSApp.mainMenu = main
  }
  @objc func togglePanel() {
    guard let button = item?.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      if let model {
        panelController?.rootView = EqualizerPanel(model: model, panelHeight: panelHeight)
        panelController?.preferredContentSize = NSSize(width: 480, height: panelHeight)
        popover.contentSize = NSSize(width: 480, height: panelHeight)
      }
      NSApp.activate(ignoringOtherApps: true)
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let model else { return .terminateNow }
    model.shutdown { sender.reply(toApplicationShouldTerminate: true) }
    return .terminateLater
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    quietLaunch = false
    showEqualizerWindow()
    return true
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
