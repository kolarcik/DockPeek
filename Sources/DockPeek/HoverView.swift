import AppKit

/// Základ pro prvky panelu, které reagují na najetí myší a klik.
///
/// Sledování myši používá `.activeAlways` (DockPeek nikdy není aktivní aplikace)
/// a `acceptsFirstMouse` vrací true, aby první klik do neaktivního panelu nepropadl.
class HoverView: NSView {
    private(set) var isHovering = false
    private var trackingArea: NSTrackingArea?

    /// Volá se při změně `isHovering`.
    func hoverChanged() {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true; hoverChanged() }
    override func mouseExited(with event: NSEvent) { isHovering = false; hoverChanged() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
