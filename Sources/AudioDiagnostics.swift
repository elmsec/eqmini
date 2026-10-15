import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor extension AppDelegate {
  func runControlSelfTest() {
    guard UserDefaults.standard.bool(forKey: "audioExplanationAccepted") else {
      print(
        "Read and accept the audio explanation by enabling EQ in the app before this live test.")
      exitCode = 1
      NSApp.terminate(nil)
      return
    }
    let model = EqualizerModel()
    self.model = model
    var ticks = 0
    var activeTicks = 0
    model.setEnabled(true)
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [self] timer in
      MainActor.assumeIsolated {
        ticks += 1
        if model.enabled && !model.restarting && !model.waitingForApps { activeTicks += 1 }
        if activeTicks >= 10 {
          let frames = EQRenderedFrames()
          print(
            "Main run loop responsive: \(ticks) ticks; rendered \(frames) frames; input peak \(EQInputPeak())"
          )
          timer.invalidate()
          if frames == 0 { self.exitCode = 1 }
          model.shutdown {
            if EQSampleRate() != 0 { self.exitCode = 1 }
            print(
              self.exitCode == 0
                ? "PASS: saved routing, async enable, responsive UI loop, serialized cleanup"
                : "FAIL: async control lifecycle")
            NSApp.terminate(nil)
          }
        } else if ticks >= 75 || model.error != nil {
          timer.invalidate()
          self.exitCode = 1
          print("FAIL: \(model.error ?? "audio did not become active")")
          model.shutdown()
          NSApp.terminate(nil)
        }
      }
    }
  }
  func runAudioSelfTest(cycle: Int) {
    guard cycle < 3 else {
      print("PASS: three start/stop cycles; default output unchanged")
      NSApp.terminate(nil)
      return
    }
    let device = EQDefaultOutput()
    let args = CommandLine.arguments
    var selectedIDs: [UInt32]?
    if let index = args.firstIndex(of: "--select-bundle"), index + 1 < args.count {
      let bundles = Set(args[index + 1].split(separator: ",").map(String.init))
      let data = Data(String(cString: EQAudioProcessesJSON()).utf8)
      let inventory = try? JSONDecoder().decode(AudioInventory.self, from: data)
      selectedIDs =
        inventory?.processes.filter { bundles.contains($0.bundleID) }.map(\.id).sorted() ?? []
      guard let ids = selectedIDs, !ids.isEmpty else {
        print("FAIL: selected bundle has no audio process")
        exitCode = 1
        NSApp.terminate(nil)
        return
      }
      if cycle == 0 {
        guard !EQStartSelected(nil, 0) else {
          EQStop()
          print("FAIL: empty selection unexpectedly started")
          exitCode = 1
          NSApp.terminate(nil)
          return
        }
        print("PASS: empty selection does not fall back to all apps")
      }
    }
    let started =
      selectedIDs.map { ids in
        ids.withUnsafeBufferPointer { EQStartSelected($0.baseAddress, UInt32($0.count)) }
      } ?? EQStart()
    guard started else {
      print("FAIL: \(String(cString: EQError()))")
      exitCode = 1
      NSApp.terminate(nil)
      return
    }
    if let ids = selectedIDs {
      guard ids.withUnsafeBufferPointer({ EQTapMatchesSelected($0.baseAddress, UInt32($0.count)) })
      else {
        EQStop()
        print("FAIL: tap does not exactly match the selected process list")
        exitCode = 1
        NSApp.terminate(nil)
        return
      }
      print("PASS: inclusive tap contains exactly \(ids.count) selected process(es)")
    }
    print("Cycle \(cycle + 1): \(String(cString: EQOutputName())) at \(EQSampleRate()) Hz")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
      let healthy = EQHealthy()
      let frames = EQRenderedFrames()
      let peak = EQInputPeak()
      print("Rendered \(frames) frames; input peak \(peak)")
      EQStop()
      guard healthy, frames > 0, device == EQDefaultOutput() else {
        print("FAIL: no audio frames, callback stalled, or default output changed")
        exitCode = 1
        NSApp.terminate(nil)
        return
      }
      runAudioSelfTest(cycle: cycle + 1)
    }
  }
}
