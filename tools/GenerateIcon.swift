import AppKit
import Foundation

let size = 1024
let rect = NSRect(x: 0, y: 0, width: size, height: size)

let image = NSImage(size: rect.size)
image.lockFocus()

// Rounded squircle background
let radius: CGFloat = 220
let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 32, dy: 32), xRadius: radius, yRadius: radius)

// Dark charcoal -> deep red gradient
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1.0),
    NSColor(calibratedRed: 0.20, green: 0.04, blue: 0.07, alpha: 1.0)
], atLocations: [0.0, 1.0], colorSpace: .deviceRGB)!
gradient.draw(in: bgPath, angle: -90)

// Subtle inner highlight stroke
NSColor.white.withAlphaComponent(0.08).setStroke()
bgPath.lineWidth = 6
bgPath.stroke()

// Letters "l-h"
let letters = "l-h" as NSString
let font = NSFont.systemFont(ofSize: 430, weight: .black)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .kern: -12
]
let textSize = letters.size(withAttributes: attrs)
let textOrigin = NSPoint(
    x: (CGFloat(size) - textSize.width) / 2,
    y: (CGFloat(size) - textSize.height) / 2 + 40
)
letters.draw(at: textOrigin, withAttributes: attrs)

// Accent dash (red) under letters
let accent = NSColor(calibratedRed: 0.86, green: 0.13, blue: 0.20, alpha: 1.0)
let dashWidth: CGFloat = 340
let dashX = (CGFloat(size) - dashWidth) / 2
let dashRect = NSRect(x: dashX, y: 250, width: dashWidth, height: 26)
accent.setFill()
NSBezierPath(roundedRect: dashRect, xRadius: 13, yRadius: 13).fill()

// Waveform bars above dash
let barHeights: [CGFloat] = [40, 78, 120, 78, 40]
let barWidth: CGFloat = 22
let gap: CGFloat = 16
let totalBarsWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * gap
var barX = (CGFloat(size) - totalBarsWidth) / 2
for h in barHeights {
    let barRect = NSRect(x: barX, y: 320, width: barWidth, height: h)
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    barX += barWidth + gap
}

image.unlockFocus()

// Save PNG
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to render icon")
    exit(1)
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try png.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
