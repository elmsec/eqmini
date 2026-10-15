import AppKit

@main
struct MakeIcon {
  static func main() throws {
    let destination = URL(fileURLWithPath: CommandLine.arguments[1])
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
      for scale in [1, 2] {
        let pixels = base * scale
        let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
          bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        BrandIcon.image(size: CGFloat(pixels)).draw(
          in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
          to: destination.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
      }
    }
  }
}
