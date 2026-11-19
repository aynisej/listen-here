import AppKit
import Foundation

let sizes: [(Int, Int)] = [
    (16, 16), (32, 32), (128, 128), (256, 256), (512, 512), (1024, 1024)
]

func drawIcon(size: Int) -> NSImage {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let image = NSImage(size: rect.size)
    image.lockFocus()

    let radius: CGFloat = CGFloat(size) * 0.215
    let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 12, dy: 12), xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0),
        NSColor(calibratedRed: 0.20, green: 0.04, blue: 0.07, alpha: 1.0)
    ], atLocations: [0.0, 1.0], colorSpace: .deviceRGB)!
    gradient.draw(in: bgPath, angle: -90)

    NSColor.white.withAlphaComponent(0.08).setStroke()
    bgPath.lineWidth = 4
    bgPath.stroke()

    let letters = "l-h" as NSString
    let font = NSFont.systemFont(ofSize: CGFloat(size) * 0.42, weight: .black)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: -12
    ]
    let textSize = letters.size(withAttributes: attrs)
    let textOrigin = NSPoint(
        x: (CGFloat(size) - textSize.width) / 2,
        y: (CGFloat(size) - textSize.height) / 2 + CGFloat(size) * 0.04
    )
    letters.draw(at: textOrigin, withAttributes: attrs)

    let accent = NSColor(calibratedRed: 0.86, green: 0.13, blue: 0.20, alpha: 1.0)
    let dashWidth: CGFloat = CGFloat(size) * 0.33
    let dashX = (CGFloat(size) - dashWidth) / 2
    let dashRect = NSRect(x: dashX, y: CGFloat(size) * 0.24, width: dashWidth, height: CGFloat(size) * 0.025)
    accent.setFill()
    NSBezierPath(roundedRect: dashRect, xRadius: CGFloat(size) * 0.0125, yRadius: CGFloat(size) * 0.0125).fill()

    let barHeights: [CGFloat] = [
        CGFloat(size) * 0.04, CGFloat(size) * 0.075, CGFloat(size) * 0.115, CGFloat(size) * 0.075, CGFloat(size) * 0.04
    ]
    let barWidth: CGFloat = CGFloat(size) * 0.02
    let gap: CGFloat = CGFloat(size) * 0.015
    let totalWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * gap
    var barX = (CGFloat(size) - totalWidth) / 2
    for h in barHeights {
        let barRect = NSRect(x: barX, y: CGFloat(size) * 0.31, width: barWidth, height: h)
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        barX += barWidth + gap
    }

    image.unlockFocus()
    return image
}

for (w, h) in sizes {
    let image = drawIcon(size: w)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to render \(w)x\(h)")
        exit(1)
    }
    let out = "icon_\(w)x\(h).png"
    try png.write(to: URL(fileURLWithPath: out))
    print("Wrote \(out)")
}