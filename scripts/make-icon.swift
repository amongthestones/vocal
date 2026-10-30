// Draws Resources/AppIcon.png: a graphite tile with a white waveform, built
// like Faro's icon (1024 canvas, 824 rounded tile, soft shadow).
// Run: swift scripts/make-icon.swift
import AppKit

func hex(_ v: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}

let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
let top = hex(0x2A2D33), bottom = hex(0x41464F)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.set()
bottom.setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: bottom, ending: top)!.draw(in: tile, angle: 90)

let config = NSImage.SymbolConfiguration(pointSize: 500, weight: .bold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let glyph = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let g = glyph.size
glyph.draw(in: NSRect(x: (size - g.width) / 2, y: (size - g.height) / 2, width: g.width, height: g.height))
NSGraphicsContext.restoreGraphicsState()

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
