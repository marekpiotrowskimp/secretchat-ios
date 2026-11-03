#!/usr/bin/env swift
// Renders the 1024×1024 SecretChat icon: night gradient, glowing emerald chat bubble with a padlock.
// Usage: swift scripts/make_icon.swift SecretChat/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//        swift scripts/make_icon.swift --launch <pixels> LaunchLogo.png   (just the logo, transparent)
import AppKit

var args = Array(CommandLine.arguments.dropFirst())
let launch = args.first == "--launch"
if launch { args.removeFirst() }
let size = launch ? Int(args.removeFirst())! : 1024
let output = args.first ?? "AppIcon.png"
let emerald = NSColor(red: 0.169, green: 0.851, blue: 0.627, alpha: 1)

// Icon: opaque RGB (no alpha channel — required for App Store icons). Launch logo: transparent, so it
// sits on the launch screen's background colour. Drawing is in 1024-unit coordinates, scaled to `size`.
let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: (launch ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
let rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)

// Night background with a faint emerald glow in the middle.
if !launch {
    NSGradient(colors: [
        NSColor(red: 0.055, green: 0.090, blue: 0.149, alpha: 1),
        NSColor(red: 0.027, green: 0.043, blue: 0.071, alpha: 1),
    ])!.draw(in: rect, angle: -90)
}
NSGradient(colors: [emerald.withAlphaComponent(0.28), emerald.withAlphaComponent(0)])!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: 112, y: 132, width: 800, height: 800)), relativeCenterPosition: .zero)

// Chat bubble with the tail as one continuous outline.
let (x0, y0, x1, y1, r): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (200, 300, 824, 750, 140)
let bubble = NSBezierPath()
bubble.move(to: NSPoint(x: 340, y: y0))                 // tail base, left
bubble.line(to: NSPoint(x: 250, y: 185))                // tail tip
bubble.line(to: NSPoint(x: 470, y: y0))                 // tail base, right
bubble.line(to: NSPoint(x: x1 - r, y: y0))
bubble.appendArc(withCenter: NSPoint(x: x1 - r, y: y0 + r), radius: r, startAngle: 270, endAngle: 360)
bubble.line(to: NSPoint(x: x1, y: y1 - r))
bubble.appendArc(withCenter: NSPoint(x: x1 - r, y: y1 - r), radius: r, startAngle: 0, endAngle: 90)
bubble.line(to: NSPoint(x: x0 + r, y: y1))
bubble.appendArc(withCenter: NSPoint(x: x0 + r, y: y1 - r), radius: r, startAngle: 90, endAngle: 180)
bubble.line(to: NSPoint(x: x0, y: y0 + r))
bubble.appendArc(withCenter: NSPoint(x: x0 + r, y: y0 + r), radius: r, startAngle: 180, endAngle: 270)
bubble.close()
bubble.lineJoinStyle = .round

NSColor(red: 0.071, green: 0.102, blue: 0.165, alpha: 1).setFill()
bubble.fill()
let glow = NSShadow()
glow.shadowColor = emerald.withAlphaComponent(0.8)
glow.shadowBlurRadius = 40
glow.set()
emerald.setStroke()
bubble.lineWidth = 26
bubble.stroke()
NSShadow().set()

// Padlock.
let config = NSImage.SymbolConfiguration(pointSize: 280, weight: .bold).applying(.init(paletteColors: [emerald]))
if let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = lock.size
    lock.draw(in: NSRect(x: 512 - s.width / 2, y: 528 - s.height / 2, width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, cg.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
print("wrote \(output)")
