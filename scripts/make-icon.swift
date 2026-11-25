// Erzeugt das App-Icon-Set (Asset Catalog) fuer Hixup.
// Aufruf: swift scripts/make-icon.swift [Ausgabeordner]
//   Standard: Apps/Shared/Assets.xcassets

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let catalogPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Apps/Shared/Assets.xcassets"
let iconSetURL = URL(fileURLWithPath: catalogPath).appendingPathComponent("AppIcon.appiconset")

/// macOS-Raster: Der Icon-Koerper fuellt 80,5 % der Flaeche, der Rest ist Rand fuer den Schatten.
let bodyRatio = 0.805
let cornerRatio = 0.2237

/// EKG-Kurve in Koordinaten des Icon-Koerpers (0...1, y nach oben). Der grosse Ausschlag ist der "Hick-up".
let waveform: [(x: Double, y: Double)] = [
    (0.13, 0.50), (0.25, 0.50), (0.30, 0.58), (0.35, 0.50), (0.46, 0.50),
    (0.54, 0.80), (0.62, 0.22), (0.67, 0.50), (0.87, 0.50)
]

func render(pixels: Int) -> CGImage {
    let size = Double(pixels)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high

    let body = size * bodyRatio
    let origin = (size - body) / 2
    let bodyRect = CGRect(x: origin, y: origin, width: body, height: body)
    let path = CGPath(
        roundedRect: bodyRect, cornerWidth: body * cornerRatio, cornerHeight: body * cornerRatio, transform: nil
    )

    // Schatten
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.025,
                      color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(path)
    context.setFillColor(CGColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Farbverlauf (Blaugruen links oben nach Blau rechts unten)
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 0.18, green: 0.83, blue: 0.75, alpha: 1),
            CGColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
        end: CGPoint(x: bodyRect.maxX, y: bodyRect.minY),
        options: []
    )
    context.restoreGState()

    // EKG-Kurve
    let points = waveform.map { CGPoint(x: bodyRect.minX + $0.x * body, y: bodyRect.minY + $0.y * body) }
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.015,
                      color: CGColor(gray: 0, alpha: 0.25))
    context.setStrokeColor(CGColor(gray: 1, alpha: 1))
    context.setLineWidth(body * 0.07)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addLines(between: points)
    context.strokePath()
    context.restoreGState()

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("PNG konnte nicht geschrieben werden: \(url.path)")
    }
}

// (Punktgroesse, Faktor) laut macOS-AppIcon-Vorgabe
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)

var entries: [[String: String]] = []
for variant in variants {
    let suffix = variant.scale == 1 ? "" : "@\(variant.scale)x"
    let filename = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    writePNG(render(pixels: variant.points * variant.scale), to: iconSetURL.appendingPathComponent(filename))
    entries.append([
        "filename": filename, "idiom": "mac",
        "scale": "\(variant.scale)x", "size": "\(variant.points)x\(variant.points)"
    ])
}

let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
let contentsData = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try contentsData.write(to: iconSetURL.appendingPathComponent("Contents.json"))

let catalogContents: [String: Any] = ["info": ["author": "xcode", "version": 1]]
let catalogData = try JSONSerialization.data(withJSONObject: catalogContents, options: [.prettyPrinted, .sortedKeys])
try catalogData.write(to: URL(fileURLWithPath: catalogPath).appendingPathComponent("Contents.json"))

print("Icon-Set geschrieben nach \(iconSetURL.path)")
