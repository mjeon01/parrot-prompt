// Builds the app icons from the parrot logo in assets/image.png.
// Usage: swift scripts/make-icon.swift Resources  (writes AppIcon.icns/.png, MenuIcon*.png, Mascot.png)
// The menu bar needs a one-color template, so it uses the simplified parrot drawn below.
import AppKit

let terracotta = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)  // #D97757
let deep = NSColor(srgbRed: 0.769, green: 0.384, blue: 0.263, alpha: 1)        // #C46243
let peach = NSColor(srgbRed: 0.965, green: 0.851, blue: 0.796, alpha: 1)       // #F6D9CB
let paper = NSColor(srgbRed: 1.000, green: 0.996, blue: 0.988, alpha: 1)       // #FFFEFC
let paperShade = NSColor(srgbRed: 0.945, green: 0.933, blue: 0.914, alpha: 1)  // #F1EEE9
let ink = NSColor(srgbRed: 0.169, green: 0.161, blue: 0.153, alpha: 1)         // #2B2927
let blush = NSColor(srgbRed: 0.957, green: 0.659, blue: 0.592, alpha: 1)       // #F4A897

// All coordinates are in a 1024 canvas, y-up. `mono` draws a one-color silhouette.
func drawParrot(scale s: CGFloat, mono: NSColor? = nil) {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: CGRect(x: (cx - w / 2) * s, y: (cy - h / 2) * s, width: w * s, height: h * s))
    }
    func fill(_ path: NSBezierPath, _ color: NSColor) { (mono ?? color).setFill(); path.fill() }

    // Crest: three soft feathers leaning back.
    for (x, y, w, h, angle) in [(452.0, 690.0, 66.0, 118.0, 30.0), (498, 712, 70, 136, 8), (546, 700, 62, 112, -16)] {
        let path = oval(0, 0, w, h)
        let t = AffineTransform(translationByX: x * s, byY: y * s)
        var r = AffineTransform(rotationByDegrees: angle); r.append(t)
        path.transform(using: r)
        fill(path, deep)
    }
    // Feet.
    for x in [440.0, 566.0] {
        fill(NSBezierPath(roundedRect: CGRect(x: (x - 26) * s, y: 214 * s, width: 52 * s, height: 44 * s), xRadius: 18 * s, yRadius: 18 * s), ink)
    }
    // Beak: drawn before the body so its base tucks into the head.
    let upper = NSBezierPath()
    upper.move(to: p(680, 604))
    upper.curve(to: p(800, 480), controlPoint1: p(772, 614), controlPoint2: p(810, 548))
    upper.curve(to: p(690, 514), controlPoint1: p(780, 506), controlPoint2: p(742, 514))
    upper.close()
    fill(upper, ink)
    let lower = NSBezierPath()
    lower.move(to: p(692, 520))
    lower.curve(to: p(768, 498), controlPoint1: p(732, 522), controlPoint2: p(760, 510))
    lower.curve(to: p(694, 476), controlPoint1: p(756, 478), controlPoint2: p(724, 472))
    lower.close()
    fill(lower, ink.blended(withFraction: 0.18, of: .white)!)
    // Body and belly.
    fill(oval(500, 455, 470, 440), terracotta)
    if mono == nil { fill(oval(492, 382, 300, 230), peach) }
    // Wing.
    let wing = oval(0, 0, 100, 176)
    var w = AffineTransform(rotationByDegrees: 14); w.append(AffineTransform(translationByX: 342 * s, byY: 446 * s))
    wing.transform(using: w)
    if mono == nil { fill(wing, deep) }
    // Face.
    if let mono {
        NSGraphicsContext.current?.compositingOperation = .clear
        oval(600, 548, 80, 80).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        _ = mono
    } else {
        fill(oval(600, 548, 86, 96), ink)
        fill(oval(616, 568, 28, 28), .white)
        fill(oval(626, 486, 64, 38), blush.withAlphaComponent(0.85))
    }
}

func render(size: Int, draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(size) / 1024)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// The logo has an opaque white background. Clear the white connected to the edges
// (the eye stays white because the outline encloses it) and feather the fringe.
func transparentLogo(_ url: URL) -> CGImage {
    let source = NSImage(contentsOf: url)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let w = source.width, h = source.height
    let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = context.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    func lightness(_ i: Int) -> Int { min(Int(px[i * 4]), Int(px[i * 4 + 1]), Int(px[i * 4 + 2])) }
    var background = [Bool](repeating: false, count: w * h)
    var stack = (0..<w).flatMap { [$0, (h - 1) * w + $0] } + (0..<h).flatMap { [$0 * w, $0 * w + w - 1] }
    while let i = stack.popLast() {
        guard !background[i], lightness(i) >= 236 else { continue }
        background[i] = true
        let x = i % w, y = i / w
        if x > 0 { stack.append(i - 1) }; if x < w - 1 { stack.append(i + 1) }
        if y > 0 { stack.append(i - w) }; if y < h - 1 { stack.append(i + w) }
    }
    for i in 0..<(w * h) {
        var alpha = 1.0
        if background[i] {
            alpha = 0
        } else {
            let x = i % w, y = i / w
            let edge = (x > 0 && background[i - 1]) || (x < w - 1 && background[i + 1])
                || (y > 0 && background[i - w]) || (y < h - 1 && background[i + w])
            if edge { alpha = min(1, Double(255 - lightness(i)) / 80) }
        }
        for c in 0..<4 { px[i * 4 + c] = UInt8(Double(px[i * 4 + c]) * alpha) }
    }
    return context.makeImage()!
}

let logo = transparentLogo(URL(fileURLWithPath: "assets/image.png"))
// Content bounds of the logo inside the 728 x 625 source (parrot and sound waves).
let logoBounds = CGRect(x: 46, y: 625 - 599, width: 642, height: 578)

// Draws the logo so its content fills `box`, keeping its aspect ratio.
func drawLogo(in box: CGRect) {
    let scale = min(box.width / logoBounds.width, box.height / logoBounds.height)
    let size = CGSize(width: CGFloat(logo.width) * scale, height: CGFloat(logo.height) * scale)
    let origin = CGPoint(x: box.midX - (logoBounds.midX * scale), y: box.midY - (logoBounds.midY * scale))
    let context = NSGraphicsContext.current!.cgContext
    context.interpolationQuality = .high
    context.draw(logo, in: CGRect(origin: origin, size: size))
}

func appIcon(_ s: CGFloat) {
    // Apple's macOS icon grid: 824/1024 body with a soft drop shadow.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s); shadow.shadowBlurRadius = 24 * s
    shadow.set()
    paper.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: paper, ending: paperShade)!.draw(in: shape, angle: -90)
    NSColor.black.withAlphaComponent(0.06).setStroke(); shape.lineWidth = 2 * s; shape.stroke()
    drawLogo(in: body.insetBy(dx: 70 * s, dy: 70 * s))
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base, draw: appIcon).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2, draw: appIcon).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try iconutil.run(); iconutil.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
try render(size: 1024, draw: appIcon).write(to: root.appendingPathComponent("AppIcon.png"))

// Logo alone on a clear background, for the greeting and the dictation bubble.
try render(size: 512, draw: { s in drawLogo(in: CGRect(x: 0, y: 0, width: 1024 * s, height: 1024 * s)) })
    .write(to: root.appendingPathComponent("Mascot.png"))

// Menu bar template: the parrot silhouette with the eye cut out.
func menuIcon(_ s: CGFloat) {
    let transform = NSAffineTransform()
    transform.translateX(by: 512 * s, yBy: 512 * s)
    transform.scale(by: 1.68)
    transform.translateX(by: -535 * s, yBy: -502 * s)
    transform.concat()
    drawParrot(scale: s, mono: .black)
}
try render(size: 18, draw: menuIcon).write(to: root.appendingPathComponent("MenuIcon.png"))
try render(size: 36, draw: menuIcon).write(to: root.appendingPathComponent("MenuIcon@2x.png"))

print("Wrote AppIcon.icns, AppIcon.png, MenuIcon.png, MenuIcon@2x.png, Mascot.png to \(root.path)")
