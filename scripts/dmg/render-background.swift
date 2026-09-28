// Renders the disk image window background: scripts/dmg/background.tiff, one file holding
// the 1x and 2x images, which is what Finder wants for a Retina window.
//
//   swift scripts/dmg/render-background.swift scripts/dmg
//
// The output is committed, so releases do not need to run this. Re-run it after changing
// the drawing. Coordinates are points in a 640x420 window, origin top-left, and must
// agree with the icon positions in scripts/dmg/settings.py.

import AppKit

let size = CGSize(width: 640, height: 420)
let appIcon = CGPoint(x: 170, y: 200)
let applicationsIcon = CGPoint(x: 470, y: 200)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func drawCentered(_ text: String, at point: CGPoint, font: NSFont, color: NSColor) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let bounds = string.size()
    string.draw(at: CGPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2))
}

func draw() {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    // Sky: one solid colour per pixel row. NSGradient dithers, and that invisible noise
    // made the image several hundred KB; a flat colour per row compresses to almost
    // nothing. The step between rows is about 1/255, too fine to band.
    let stops: [(CGFloat, UInt32)] = [(0, 0x07071A), (0.5, 0x1B1446), (1, 0x3A2878)]
    func channel(_ hex: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((hex >> shift) & 0xFF) }
    let rowHeight = 0.5  // one row per pixel at 2x
    var y: CGFloat = 0
    while y < size.height {
        let t = y / size.height
        let upper = stops.firstIndex { $0.0 >= t } ?? stops.count - 1
        let lower = max(upper - 1, 0)
        let span = stops[upper].0 - stops[lower].0
        let f = span > 0 ? (t - stops[lower].0) / span : 0
        func mix(_ shift: UInt32) -> CGFloat {
            let a = channel(stops[lower].1, shift), b = channel(stops[upper].1, shift)
            return (a + (b - a) * f).rounded() / 255
        }
        NSColor(srgbRed: mix(16), green: mix(8), blue: mix(0), alpha: 1).setFill()
        CGRect(x: 0, y: y, width: size.width, height: rowHeight).fill()
        y += rowHeight
    }

    // Stars. A fixed-seed generator, so re-rendering gives the same sky.
    var seed: UInt64 = 0x4E6F7463
    func next() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
    }
    for _ in 0..<90 {
        let point = CGPoint(x: next() * size.width, y: 40 + next() * 250)
        let radius = 0.4 + next() * 1.1
        color(0xFFFFFF, 0.25 + next() * 0.6).setFill()
        NSBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    // The notch, flush with the top edge, with the app's face on its right.
    let notch = CGRect(x: size.width / 2 - 100, y: -20, width: 200, height: 54)
    color(0x000000).setFill()
    NSBezierPath(roundedRect: notch, xRadius: 16, yRadius: 16).fill()
    let face = CGPoint(x: notch.maxX - 26, y: 17)
    color(0xFFFFFF).setFill()
    for dx: CGFloat in [-5, 5] {
        // Eyes glance right and down, towards the Applications folder.
        NSBezierPath(ovalIn: CGRect(x: face.x + dx - 1.6 + 1, y: face.y - 5.5 + 0.6, width: 3.2, height: 3.2)).fill()
    }
    let smile = NSBezierPath()
    smile.appendArc(withCenter: CGPoint(x: face.x + 0.5, y: face.y + 1), radius: 6,
                    startAngle: 20, endAngle: 160, clockwise: false)
    smile.lineWidth = 1.8
    smile.lineCapStyle = .round
    color(0xFFFFFF).setStroke()
    smile.stroke()

    // The arrow: a dashed arc from the app to Applications, like a drag in progress.
    let start = CGPoint(x: appIcon.x + 78, y: appIcon.y - 14)
    let end = CGPoint(x: applicationsIcon.x - 80, y: applicationsIcon.y - 14)
    let arc = NSBezierPath()
    arc.move(to: start)
    arc.curve(to: end,
              controlPoint1: CGPoint(x: start.x + 40, y: start.y - 58),
              controlPoint2: CGPoint(x: end.x - 40, y: end.y - 58))
    arc.lineWidth = 3
    arc.lineCapStyle = .round
    arc.setLineDash([2, 9], count: 2, phase: 0)
    color(0xFFFFFF, 0.85).setStroke()
    arc.stroke()

    // Arrowhead, along the curve's final tangent (end - controlPoint2).
    let angle = atan2(58.0, 40.0)
    let head = NSBezierPath()
    for side: CGFloat in [-1, 1] {
        let a = angle + .pi + side * 0.55
        head.move(to: end)
        head.line(to: CGPoint(x: end.x + cos(a) * 13, y: end.y + sin(a) * 13))
    }
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.stroke()

    drawCentered("Drop me in", at: CGPoint(x: size.width / 2, y: 118),
                 font: rounded(22, .bold), color: color(0xFFFFFF))

    // Plates behind Finder's own icon labels. Finder draws them black in light mode and
    // white in dark mode and cannot be told otherwise; a mid-tone plate (relative
    // luminance ~0.18) gives both about 4.3:1 contrast.
    for center in [appIcon, applicationsIcon] {
        let plate = CGRect(x: center.x - 62, y: center.y + 70, width: 124, height: 24)
        color(0x7A70AE).setFill()
        NSBezierPath(roundedRect: plate, xRadius: 12, yRadius: 12).fill()
    }

    // Kept clear of the bottom ~30pt: Finder draws a path or status bar there when the
    // user has it switched on globally, whatever the image's own window settings say.
    drawCentered("First launch: System Settings  ›  Privacy & Security  ›  Open Anyway",
                 at: CGPoint(x: size.width / 2, y: 342), font: rounded(12, .medium),
                 color: color(0xFFFFFF, 0.72))
    drawCentered("Or skip that: install in one line from the README",
                 at: CGPoint(x: size.width / 2, y: 364), font: rounded(11, .regular),
                 color: color(0xFFFFFF, 0.5))

    _ = ctx
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    // Flip to a top-left origin so the coordinates above read like the window. The
    // context already maps points to pixels, because rep.size is set in points.
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
// Lossless LZW. The image is kept deliberately low in detail so this stays small: a
// vertical gradient is one colour per row, which compresses to almost nothing, whereas an
// earlier soft radial glow made nearly every pixel unique and cost ~500KB - a seventh of
// the whole download. (JPEG-in-TIFF would hide that, but macOS no longer writes it.)
let reps = [render(scale: 1), render(scale: 2)]
let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: reps, using: .lzw, factor: 0)!
try! tiff.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("background.tiff"))
print("rendered \(outDir)/background.tiff (\(tiff.count) bytes)")
