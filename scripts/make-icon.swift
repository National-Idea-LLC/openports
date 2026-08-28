// Renders Squatter's app icon into Squatter/Resources/Assets.xcassets/AppIcon.appiconset.
// Run: swift scripts/make-icon.swift
import AppKit

let sizes: [(px: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

/// Dark panel with a row of LED sockets, one lit green — the app's signature, scaled down.
func draw(size: CGFloat, into context: CGContext) {
    let inset = size * 0.06
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let corner = rect.width * 0.225

    // Panel with a subtle vertical gradient so it doesn't read as a flat block.
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    context.saveGState()
    context.addPath(path)
    context.clip()
    let colors = [
        CGColor(red: 0.16, green: 0.18, blue: 0.21, alpha: 1),
        CGColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    }
    context.restoreGState()

    // Hairline edge for definition on light backgrounds.
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    context.setLineWidth(max(size * 0.005, 0.5))
    context.addPath(path)
    context.strokePath()

    // Four sockets; the second is lit. Big enough to survive 16 pt.
    let count = 4
    let diameter = rect.width * 0.155
    let gap = (rect.width - diameter * CGFloat(count)) / CGFloat(count + 1)
    let y = rect.midY - diameter / 2
    for index in 0..<count {
        let x = rect.minX + gap * CGFloat(index + 1) + diameter * CGFloat(index)
        let socket = CGRect(x: x, y: y, width: diameter, height: diameter)
        if index == 1 {
            context.setFillColor(CGColor(red: 0.22, green: 0.83, blue: 0.36, alpha: 1))
            context.setShadow(offset: .zero, blur: diameter * 0.7, color: CGColor(red: 0.22, green: 0.83, blue: 0.36, alpha: 0.9))
            context.fillEllipse(in: socket)
            context.setShadow(offset: .zero, blur: 0, color: nil)
        } else {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.13))
            context.fillEllipse(in: socket)
        }
    }
}

let outputDirectory = URL(filePath: "Squatter/Resources/Assets.xcassets/AppIcon.appiconset")
var entries: [[String: String]] = []
for (pixels, name) in sizes {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(size: CGFloat(pixels), into: context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: outputDirectory.appending(path: "\(name).png"))
}

// Contents.json in the order Xcode expects.
let manifest: [(size: String, scale: String, file: String)] = [
    ("16x16", "1x", "icon_16x16"), ("16x16", "2x", "icon_16x16@2x"),
    ("32x32", "1x", "icon_32x32"), ("32x32", "2x", "icon_32x32@2x"),
    ("128x128", "1x", "icon_128x128"), ("128x128", "2x", "icon_128x128@2x"),
    ("256x256", "1x", "icon_256x256"), ("256x256", "2x", "icon_256x256@2x"),
    ("512x512", "1x", "icon_512x512"), ("512x512", "2x", "icon_512x512@2x"),
]
entries = manifest.map { ["idiom": "mac", "size": $0.size, "scale": $0.scale, "filename": "\($0.file).png"] }
let json: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
try data.write(to: outputDirectory.appending(path: "Contents.json"))
print("wrote \(sizes.count) icon files")
