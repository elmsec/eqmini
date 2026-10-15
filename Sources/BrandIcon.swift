import AppKit

// One fader mark for the app icon, in-app branding, and menu-bar template.
enum BrandIcon {
  static func image(size: CGFloat, template: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
      let side = rect.width
      if !template {
        NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.095, alpha: 1).setFill()
        NSBezierPath(
          roundedRect: rect.insetBy(dx: side * 0.05, dy: side * 0.05),
          xRadius: side * 0.2, yRadius: side * 0.2
        ).fill()
      }
      for (index, knob) in [0.4, 0.65, 0.5].enumerated() {
        let x = side * (template ? 0.2 + CGFloat(index) * 0.3 : 0.29 + CGFloat(index) * 0.21)
        let track = side * (template ? 0.075 : 0.05)
        (template ? NSColor.black : NSColor.white.withAlphaComponent(0.2)).setFill()
        NSBezierPath(
          roundedRect: NSRect(x: x - track / 2, y: side * 0.2, width: track, height: side * 0.6),
          xRadius: track / 2, yRadius: track / 2
        ).fill()
        (template ? NSColor.black : NSColor(calibratedRed: 0.32, green: 0.88, blue: 0.72, alpha: 1))
          .setFill()
        let width = side * (template ? 0.23 : 0.14)
        let height = side * (template ? 0.16 : 0.11)
        NSBezierPath(
          roundedRect: NSRect(
            x: x - width / 2, y: side * knob - height / 2, width: width, height: height),
          xRadius: height * 0.36, yRadius: height * 0.36
        ).fill()
      }
      return true
    }
    image.isTemplate = template
    image.accessibilityDescription = "eqMini"
    return image
  }
}
