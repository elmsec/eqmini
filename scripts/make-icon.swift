import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = base * scale
    let side = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let inset = side * 0.05
    NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.095, alpha: 1).setFill()
    NSBezierPath(
      roundedRect: NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset),
      xRadius: side * 0.2, yRadius: side * 0.2
    ).fill()
    for (index, knob) in [0.4, 0.65, 0.5].enumerated() {
      let x = side * (0.29 + CGFloat(index) * 0.21)
      NSColor.white.withAlphaComponent(0.2).setFill()
      NSBezierPath(
        roundedRect: NSRect(
          x: x - side * 0.025, y: side * 0.25, width: side * 0.05, height: side * 0.5),
        xRadius: side * 0.025, yRadius: side * 0.025
      ).fill()
      NSColor(calibratedRed: 0.32, green: 0.88, blue: 0.72, alpha: 1).setFill()
      NSBezierPath(
        roundedRect: NSRect(
          x: x - side * 0.07, y: side * knob - side * 0.055, width: side * 0.14, height: side * 0.11
        ), xRadius: side * 0.04, yRadius: side * 0.04
      ).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: destination.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
  }
}
