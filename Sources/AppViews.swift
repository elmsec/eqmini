import AppKit
import Combine
import ServiceManagement
import SwiftUI

enum AppLinks {
  static let website = URL(string: "https://elma.dev")!
  static let privacy = URL(string: "https://elma.dev/eqmini/privacy")!
  static let terms = URL(string: "https://elma.dev/eqmini/terms")!
  static let support = URL(string: "https://www.buymeacoffee.com/canelma")!
  static let sponsors = URL(string: "https://github.com/sponsors/elmsec")!
}

struct EqualizerWindowContent: View {
  @ObservedObject var model: EqualizerModel
  var body: some View {
    GeometryReader { geometry in
      EqualizerPanel(model: model, panelHeight: geometry.size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .preferredColorScheme(.dark)
  }
}

struct AboutEqualizer: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
  }
  var body: some View {
    VStack(spacing: 18) {
      Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(
        width: 80, height: 80)
      VStack(spacing: 5) {
        Text("eqmini").font(.system(size: 28, weight: .bold, design: .rounded))
        Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
      }
      Text("Your sound, a little fuller.").font(.headline)
      Text("A simple equalizer for your Mac. Shape all audio or just the apps you choose.")
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.secondary)
      Link("Made by Can Elma ↗", destination: AppLinks.website)
      Menu("Support eqmini") {
        Link("GitHub Sponsors ↗", destination: AppLinks.sponsors)
        Link("Buy me a coffee ↗", destination: AppLinks.support)
      }.menuStyle(.borderlessButton).fixedSize().font(.callout)
      Divider()
      HStack(spacing: 24) {
        Link("Privacy Policy", destination: AppLinks.privacy)
        Link("Terms of Use", destination: AppLinks.terms)
      }.font(.callout)
      Text("© \(String(Calendar.current.component(.year, from: Date()))) Can Elma")
        .font(.caption).foregroundStyle(.secondary)
    }.padding(32).frame(width: 360).preferredColorScheme(.dark).tint(.mint)
  }
}
