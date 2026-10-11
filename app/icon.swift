// Renders the app icon (pixel chicken over lava) to the PNG path given as the first argument.
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bg = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.16, green: 0.05, blue: 0.3, alpha: 1),
                    NSColor(red: 0.45, green: 0.1, blue: 0.55, alpha: 1)])!.draw(in: bg, angle: 90)
bg.addClip()
NSGradient(colors: [NSColor(red: 1, green: 0.27, blue: 0, alpha: 1),
                    NSColor(red: 1, green: 0.75, blue: 0, alpha: 1)])!.draw(in: NSRect(x: 100, y: 100, width: 824, height: 190), angle: 90)

let rows = [
    "......WWWW....",
    "......WWKW....",
    "......WWWWOO..",
    "......WWWWRR..",
    ".WW...WWWW....",
    "WWWWWWWWWW....",
    "WWwwwWWWWW....",
    "WWwwwWWWWW....",
    "WWWwwWWWWW....",
    ".WWWWWWWWW....",
    "..WWWWWWW.....",
    "....Y..Y......",
    "...YY.YY......",
]
let colors: [Character: NSColor] = [
    "W": .white, "w": NSColor(white: 0.8, alpha: 1), "K": .black,
    "O": NSColor(red: 1, green: 0.62, blue: 0, alpha: 1), "R": NSColor(red: 0.88, green: 0.1, blue: 0.1, alpha: 1),
    "Y": NSColor(red: 0.96, green: 0.77, blue: 0, alpha: 1),
]
let px: CGFloat = 46
let ox: CGFloat = (1024 - 12 * px) / 2, top: CGFloat = 860
for (y, row) in rows.enumerated() {
    for (x, c) in row.enumerated() {
        guard let col = colors[c] else { continue }
        col.setFill()
        NSRect(x: ox + CGFloat(x) * px, y: top - CGFloat(y + 1) * px, width: px + 0.5, height: px + 0.5).fill()
    }
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
