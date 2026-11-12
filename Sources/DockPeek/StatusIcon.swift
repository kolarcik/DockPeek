import AppKit

/// Ikona do stavového řádku: vyskakovací karta se dvěma okny nad lištou Docku.
/// Kreslí se jako template, takže se sama přizpůsobí světlému/tmavému menu baru.
enum StatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()

            // Lišta Docku
            NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 16, height: 3), xRadius: 1.5, yRadius: 1.5).fill()

            // Karta s náhledy + šipka k ikoně
            let card = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 6.75, width: 14.5, height: 10.5), xRadius: 2.5, yRadius: 2.5)
            card.lineWidth = 1.5
            card.stroke()
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 7, y: 6.75))
            arrow.line(to: NSPoint(x: 9, y: 4.9))
            arrow.line(to: NSPoint(x: 11, y: 6.75))
            arrow.close()
            arrow.fill()

            // Dvě miniatury oken
            NSBezierPath(roundedRect: NSRect(x: 3.75, y: 9, width: 4.5, height: 6), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: NSRect(x: 9.75, y: 9, width: 4.5, height: 6), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "DockPeek"
        return image
    }
}
