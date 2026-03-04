import AppKit

enum AppIconFactory {
    static func makeAppIcon(size: CGFloat = 512) -> NSImage {
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize)

        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(origin: .zero, size: imageSize)
        let cornerRadius = size * 0.22
        let backgroundPath = NSBezierPath(
            roundedRect: bounds.insetBy(dx: size * 0.02, dy: size * 0.02),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )

        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.16, green: 0.26, blue: 0.84, alpha: 1.0),
            NSColor(srgbRed: 0.28, green: 0.48, blue: 0.96, alpha: 1.0),
        ])
        gradient?.draw(in: backgroundPath, angle: 90)

        let notebookRect = NSRect(
            x: size * 0.18,
            y: size * 0.20,
            width: size * 0.64,
            height: size * 0.60
        )
        let notebook = NSBezierPath(
            roundedRect: notebookRect,
            xRadius: size * 0.08,
            yRadius: size * 0.08
        )
        NSColor.white.withAlphaComponent(0.95).setFill()
        notebook.fill()

        let spine = NSBezierPath(
            roundedRect: NSRect(
                x: notebookRect.minX,
                y: notebookRect.minY,
                width: size * 0.07,
                height: notebookRect.height
            ),
            xRadius: size * 0.03,
            yRadius: size * 0.03
        )
        NSColor(srgbRed: 0.84, green: 0.90, blue: 1.0, alpha: 1.0).setFill()
        spine.fill()

        let lineColor = NSColor(srgbRed: 0.66, green: 0.74, blue: 0.94, alpha: 1.0)
        for index in 0..<4 {
            let y = notebookRect.maxY - size * (0.14 + CGFloat(index) * 0.10)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: notebookRect.minX + size * 0.12, y: y))
            line.line(to: NSPoint(x: notebookRect.maxX - size * 0.08, y: y))
            line.lineWidth = size * 0.015
            lineColor.setStroke()
            line.stroke()
        }

        let lockBodyRect = NSRect(
            x: size * 0.54,
            y: size * 0.14,
            width: size * 0.22,
            height: size * 0.19
        )
        let lockBody = NSBezierPath(
            roundedRect: lockBodyRect,
            xRadius: size * 0.04,
            yRadius: size * 0.04
        )
        NSColor(srgbRed: 0.99, green: 0.73, blue: 0.22, alpha: 1.0).setFill()
        lockBody.fill()

        let shackle = NSBezierPath()
        let shackleCenterX = lockBodyRect.midX
        let shackleBottomY = lockBodyRect.maxY - size * 0.01
        shackle.move(to: NSPoint(x: shackleCenterX - size * 0.07, y: shackleBottomY))
        shackle.curve(
            to: NSPoint(x: shackleCenterX + size * 0.07, y: shackleBottomY),
            controlPoint1: NSPoint(
                x: shackleCenterX - size * 0.07, y: shackleBottomY + size * 0.14),
            controlPoint2: NSPoint(x: shackleCenterX + size * 0.07, y: shackleBottomY + size * 0.14)
        )
        shackle.lineWidth = size * 0.03
        NSColor(srgbRed: 0.95, green: 0.58, blue: 0.10, alpha: 1.0).setStroke()
        shackle.stroke()

        return image
    }
}
