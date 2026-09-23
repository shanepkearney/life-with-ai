// Builds the 1200x630 link-preview image (Open Graph / Twitter card) from the
// README hero screenshot: the star Claude designed, enlarged, beside the name
// and tagline in the app's neon style. Uses AppKit for real font rendering, so
// it runs on macOS only:
//
//   swiftc -O tool/social_card.swift -o /tmp/social_card && /tmp/social_card
//
// Output: web/social-preview.jpg (published at the site root by the Pages build).
import AppKit

let W = 1200.0, H = 630.0
let bg = NSColor(srgbRed: 0.020, green: 0.024, blue: 0.039, alpha: 1)
let cyan = NSColor(srgbRed: 0.0, green: 0.898, blue: 1.0, alpha: 1)
let magenta = NSColor(srgbRed: 1.0, green: 0.169, blue: 0.839, alpha: 1)
let text = NSColor(srgbRed: 0.902, green: 0.945, blue: 1.0, alpha: 1)
let muted = NSColor(srgbRed: 0.49, green: 0.545, blue: 0.651, alpha: 1)

guard let hero = NSImage(contentsOfFile: "readme/hero-four-point-star.png"),
      let heroRep = hero.representations.first else { fatalError("run from the repo root") }
// Work in the screenshot's pixel space, not its point size.
let heroPx = NSSize(width: heroRep.pixelsWide, height: heroRep.pixelsHigh)
hero.size = heroPx

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

bg.setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// Left: the star, cropped square from the screenshot (top-left pixel coordinates)
// and enlarged. AppKit's origin is bottom-left, so flip the crop's y.
let crop = (x: 293.0, y: 330.0, size: 490.0)
let src = NSRect(x: crop.x, y: heroPx.height - crop.y - crop.size, width: crop.size, height: crop.size)
hero.draw(in: NSRect(x: 20, y: 20, width: 590, height: 590), from: src, operation: .sourceOver, fraction: 1)

// Right: name, tagline, URL.
func draw(_ s: String, _ font: NSFont, _ color: NSColor, at p: NSPoint, glow: NSColor? = nil, kern: Double = 0, width: Double? = nil) -> NSSize {
  let para = NSMutableParagraphStyle()
  para.lineSpacing = 6
  var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: para]
  if let glow {
    let shadow = NSShadow()
    shadow.shadowColor = glow.withAlphaComponent(0.85)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = .zero
    attrs[.shadow] = shadow
  }
  let str = NSAttributedString(string: s, attributes: attrs)
  let bounds = str.boundingRect(with: NSSize(width: width ?? 10_000, height: 10_000), options: [.usesLineFragmentOrigin])
  str.draw(with: NSRect(x: p.x, y: p.y - bounds.height, width: width ?? bounds.width + 4, height: bounds.height),
           options: [.usesLineFragmentOrigin])
  return bounds.size
}

let x = 650.0
let title = NSFont(name: "Menlo-Bold", size: 64) ?? .monospacedSystemFont(ofSize: 64, weight: .bold)
let life = draw("LIFE", title, cyan, at: NSPoint(x: x, y: 470), glow: cyan, kern: 14)
_ = draw("with AI", title, magenta, at: NSPoint(x: x + life.width + 18, y: 470), glow: magenta)

_ = draw("Conway's Game of Life with GPU shader glow, and an AI that designs, tests and replays seeds for you.",
         NSFont(name: "Menlo", size: 25) ?? .monospacedSystemFont(ofSize: 25, weight: .regular), text,
         at: NSPoint(x: x, y: 370), width: 520)

_ = draw("Flutter · GLSL · Claude", NSFont(name: "Menlo", size: 20) ?? .monospacedSystemFont(ofSize: 20, weight: .regular),
         magenta, at: NSPoint(x: x, y: 170))
_ = draw("shanepkearney.github.io/life-with-ai", NSFont(name: "Menlo", size: 20) ?? .monospacedSystemFont(ofSize: 20, weight: .regular),
         muted, at: NSPoint(x: x, y: 130))

NSGraphicsContext.restoreGraphicsState()
let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
try! jpg.write(to: URL(fileURLWithPath: "web/social-preview.jpg"))
print("wrote web/social-preview.jpg (\(jpg.count / 1024) KB)")
