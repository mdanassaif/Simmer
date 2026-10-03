import AppKit

/// The menu-bar cup. Off: a plain template cup (white on a dark menu bar).
/// On: a warm gradient cup with colourful steam that drifts upward as `phase` advances.
enum CupIcon {
    static let size = NSSize(width: 20, height: 18)

    static func off() -> NSImage? {
        let image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "Awake off")
        image?.isTemplate = true
        return image
    }

    /// How many frames one loop of the steam has.
    static let frameCount = 24

    /// Frame `index` of the steam loop, drawn once and kept.
    @MainActor static func on(frame index: Int) -> NSImage {
        if frames.isEmpty {
            frames = (0..<frameCount).map { render(phase: CGFloat($0) / CGFloat(frameCount)) }
        }
        return frames[index % frameCount]
    }

    @MainActor private static var frames: [NSImage] = []

    private static func render(phase: CGFloat) -> NSImage {
        let scale = 2
        let image = NSImage(size: size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return image }
        // Set the point size before making the context, or it draws at half scale in a corner.
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        drawSteam(phase: phase)
        drawCup()
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        image.isTemplate = false
        image.accessibilityDescription = "Awake on"
        return image
    }

    private static let warm = NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.80, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.50, blue: 0.15, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.25, blue: 0.45, alpha: 1),
    ])
    private static let steamColors = [
        NSColor(srgbRed: 0.35, green: 0.85, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.85, blue: 0.25, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.45, blue: 0.70, alpha: 1),
    ]

    private static func drawCup() {
        // The cup is laid out on a smaller grid; scale it up to match the off symbol.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let fit = NSAffineTransform()
        fit.translateX(by: -0.2, yBy: 0)
        fit.scale(by: 1.2)
        fit.concat()

        let handle = NSBezierPath()
        handle.appendArc(withCenter: NSPoint(x: 12.4, y: 6.6), radius: 2.1, startAngle: -80, endAngle: 80)
        handle.lineWidth = 1.5
        handle.lineCapStyle = .round
        NSColor(srgbRed: 1.00, green: 0.38, blue: 0.35, alpha: 1).setStroke()
        handle.stroke()

        let body = NSBezierPath()
        body.move(to: NSPoint(x: 3.2, y: 9.8))
        body.line(to: NSPoint(x: 12.6, y: 9.8))
        body.line(to: NSPoint(x: 12.6, y: 6.6))
        body.curve(to: NSPoint(x: 9.4, y: 3.4), controlPoint1: NSPoint(x: 12.6, y: 4.8), controlPoint2: NSPoint(x: 11.2, y: 3.4))
        body.line(to: NSPoint(x: 6.4, y: 3.4))
        body.curve(to: NSPoint(x: 3.2, y: 6.6), controlPoint1: NSPoint(x: 4.6, y: 3.4), controlPoint2: NSPoint(x: 3.2, y: 4.8))
        body.close()
        warm?.draw(in: body, angle: -90)

        let saucer = NSBezierPath(roundedRect: NSRect(x: 1.8, y: 1.2, width: 12.2, height: 1.4), xRadius: 0.7, yRadius: 0.7)
        warm?.draw(in: saucer, angle: 0)
    }

    private static func drawSteam(phase: CGFloat) {
        let bottom: CGFloat = 12.6, height: CGFloat = 4.8, steps = 12
        for (index, color) in steamColors.enumerated() {
            let x0 = 6.3 + CGFloat(index) * 3.0
            let offset = CGFloat(index) / 3
            func point(_ t: CGFloat) -> NSPoint {
                let sway = sin((t * 1.6 - phase + offset) * 2 * .pi) * 0.7 * (0.4 + t)
                return NSPoint(x: x0 + sway, y: bottom + t * height)
            }
            for step in 0..<steps {
                let t0 = CGFloat(step) / CGFloat(steps), t1 = CGFloat(step + 1) / CGFloat(steps)
                // A bright puff travels up each strand and fades toward the top.
                let puff = 0.5 + 0.5 * sin((t0 - phase * 2 + offset) * 2 * .pi)
                let alpha = (1 - t0 * t0 * 0.85) * (0.35 + 0.65 * puff)
                let segment = NSBezierPath()
                segment.move(to: point(t0))
                segment.line(to: point(t1))
                segment.lineWidth = 1.3
                segment.lineCapStyle = .round
                color.withAlphaComponent(alpha).setStroke()
                segment.stroke()
            }
        }
    }
}
