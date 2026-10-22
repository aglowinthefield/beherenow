import AppKit

/// A template yin-yang for the menu bar, rotated counterclockwise by `degrees`.
/// SF Symbols has no yin-yang, so it is drawn by hand.
func yinYangImage(rotatedBy degrees: Double) -> NSImage {
    let side: CGFloat = 18
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
        let lineWidth: CGFloat = 1.2
        let r = side / 2 - lineWidth
        let transform = NSAffineTransform()
        transform.translateX(by: side / 2, yBy: side / 2)
        transform.rotate(byDegrees: degrees)
        transform.concat()
        NSColor.black.set()

        let outline = NSBezierPath(ovalIn: NSRect(x: -r, y: -r, width: 2 * r, height: 2 * r))
        outline.lineWidth = lineWidth
        outline.stroke()

        // Dark half: left semicircle, bulging into the bottom right, indented at the top left.
        let dark = NSBezierPath()
        dark.move(to: NSPoint(x: 0, y: r))
        dark.appendArc(withCenter: .zero, radius: r, startAngle: 90, endAngle: 270, clockwise: false)
        dark.appendArc(withCenter: NSPoint(x: 0, y: -r / 2), radius: r / 2, startAngle: 270, endAngle: 90, clockwise: false)
        dark.appendArc(withCenter: NSPoint(x: 0, y: r / 2), radius: r / 2, startAngle: 270, endAngle: 90, clockwise: true)
        dark.close()
        let dot = r / 6
        dark.appendOval(in: NSRect(x: -dot, y: -r / 2 - dot, width: 2 * dot, height: 2 * dot))
        dark.windingRule = .evenOdd
        dark.fill()

        NSBezierPath(ovalIn: NSRect(x: -dot, y: r / 2 - dot, width: 2 * dot, height: 2 * dot)).fill()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Be Here Now"
    return image
}
