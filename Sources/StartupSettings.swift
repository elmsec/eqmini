import AppKit
import Combine
import ServiceManagement
import SwiftUI

protocol LoginItemManaging {
  var status: SMAppService.Status { get }
  func register() throws
  func unregister() throws
}

struct SystemLoginItem: LoginItemManaging {
  var status: SMAppService.Status { SMAppService.mainApp.status }
  func register() throws { try SMAppService.mainApp.register() }
  func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor final class StartupSettings: ObservableObject {
  @Published private(set) var status: SMAppService.Status = .notRegistered
  @Published private(set) var error: String?
  private let service: LoginItemManaging
  init(service: LoginItemManaging = SystemLoginItem()) {
    self.service = service
    refresh()
  }
  var registered: Bool { status == .enabled || status == .requiresApproval }
  func refresh() { status = service.status }
  func setLaunchAtLogin(_ enabled: Bool) {
    error = nil
    do {
      if enabled { try service.register() } else { try service.unregister() }
    } catch {
      self.error = "Couldn’t change launch at login. \(error.localizedDescription)"
    }
    refresh()
    if enabled && status == .notFound && error == nil {
      error = "macOS couldn’t register this copy of eqmini. Move it to Applications and try again."
    }
  }
}
