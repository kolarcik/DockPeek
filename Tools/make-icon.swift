// Vygeneruje ikonu aplikace: Resources/AppIcon.icns (+ náhled Resources/AppIcon.png).
// Spuštění z kořene repa:  swift Tools/make-icon.swift
//
// Motiv: vyskakovací karta se dvěma náhledy oken nad zvýrazněnou ikonou v Docku.
import AppKit

let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func withShadow(blur: CGFloat, offsetY: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: offsetY)
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

/// Miniatura okna: titulek se semafory a pár „řádků“ obsahu.
func drawWindow(_ rect: NSRect, accent: NSColor) {
    let r: CGFloat = 18
    withShadow(blur: 18, offsetY: -6, alpha: 0.18) {
        color(0xFFFFFF).setFill()
        rounded(rect, r).fill()
    }
    NSGraphicsContext.saveGraphicsState()
    rounded(rect, r).addClip()
    // titulková lišta
    color(0xEEF1F7).setFill()
    NSRect(x: rect.minX, y: rect.maxY - 44, width: rect.width, height: 44).fill()
    for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        color(UInt32(c)).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 20 + CGFloat(i) * 26, y: rect.maxY - 31, width: 18, height: 18)).fill()
    }
    // obsah
    accent.setFill()
    rounded(NSRect(x: rect.minX + 20, y: rect.maxY - 110, width: rect.width * 0.55, height: 34), 10).fill()
    color(0xD9DEE8).setFill()
    for i in 0..<4 {
        let w = rect.width - 40 - CGFloat([0, 50, 20, 80][i])
        rounded(NSRect(x: rect.minX + 20, y: rect.maxY - 150 - CGFloat(i) * 32, width: w, height: 16), 8).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // Podklad – standardní mřížka macOS ikon (824 px čtverec se zaoblením)
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = rounded(tile, 185)
    withShadow(blur: 28, offsetY: -12, alpha: 0.3) {
        color(0x3B3FD8).setFill()
        tilePath.fill()
    }
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [color(0x6E9BFF), color(0x4B4FE6), color(0x3424B8)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: tile, angle: -90)
    // jemný lesk nahoře
    NSGradient(colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)

    // Dock
    let dock = NSRect(x: 170, y: 168, width: 684, height: 118)
    color(0xFFFFFF, 0.24).setFill()
    rounded(dock, 40).fill()
    color(0xFFFFFF, 0.35).setStroke()
    let dockStroke = rounded(dock.insetBy(dx: 1.5, dy: 1.5), 38.5)
    dockStroke.lineWidth = 3
    dockStroke.stroke()

    let iconSize: CGFloat = 82, gap: CGFloat = 26
    let iconColors: [UInt32] = [0xFFB547, 0x47D18C, 0xFFFFFF, 0xFF6B8B, 0x5FD3FF]
    let rowWidth = iconSize * 5 + gap * 4
    for (i, c) in iconColors.enumerated() {
        let x = 512 - rowWidth / 2 + CGFloat(i) * (iconSize + gap)
        let rect = NSRect(x: x, y: dock.midY - iconSize / 2, width: iconSize, height: iconSize)
        if i == 2 {
            withShadow(blur: 14, offsetY: -4, alpha: 0.25) {
                color(c).setFill(); rounded(rect, 22).fill()
            }
            color(0x4B4FE6).setFill()
            rounded(rect.insetBy(dx: 20, dy: 20), 8).fill()
            // tečka „běží“
            color(0xFFFFFF).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 6, y: dock.minY + 8, width: 12, height: 12)).fill()
        } else {
            color(c, 0.9).setFill()
            rounded(rect, 22).fill()
        }
    }

    // Vyskakovací karta s náhledy
    let card = NSRect(x: 196, y: 352, width: 632, height: 440)
    let cardPath = rounded(card, 46)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 472, y: card.minY + 2))
    arrow.line(to: NSPoint(x: 512, y: card.minY - 40))
    arrow.line(to: NSPoint(x: 552, y: card.minY + 2))
    arrow.close()
    cardPath.append(arrow)
    withShadow(blur: 40, offsetY: -16, alpha: 0.35) {
        color(0xF7F8FC, 0.97).setFill()
        cardPath.fill()
    }

    let wy = card.minY + 34, wh = card.height - 68
    let ww = (card.width - 34 * 3) / 2
    drawWindow(NSRect(x: card.minX + 34, y: wy, width: ww, height: wh), accent: color(0x6E9BFF))
    // druhé okno = „vybrané“ – zvýrazněný rámeček
    let second = NSRect(x: card.minX + 34 * 2 + ww, y: wy, width: ww, height: wh)
    color(0x4B4FE6).setStroke()
    let highlight = rounded(second.insetBy(dx: -9, dy: -9), 26)
    highlight.lineWidth = 7
    highlight.stroke()
    drawWindow(second, accent: color(0xFFB547))

    NSGraphicsContext.restoreGraphicsState()
    return true
}

// --- uložení PNG + iconset → icns ---
func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(image, pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(image, pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try! png(image, pixels: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Hotovo: Resources/AppIcon.icns" : "iconutil selhal")
