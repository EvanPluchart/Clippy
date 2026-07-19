#!/usr/bin/env swift

import AppKit
import Foundation

private let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: render_dmg_background.swift <source.png> <output-directory>\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to load \(sourceURL.path)\n", stderr)
    exit(66)
}

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

func renderBackground(size: NSSize) throws -> Data {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        throw NSError(
            domain: "ClippyDMG",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create a graphics context."]
        )
    }

    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    context.imageInterpolation = .high

    let sourceSize = sourceImage.size
    let scale = max(size.width / sourceSize.width, size.height / sourceSize.height)
    let destinationSize = NSSize(
        width: sourceSize.width * scale,
        height: sourceSize.height * scale
    )
    let destinationRect = NSRect(
        x: (size.width - destinationSize.width) / 2,
        y: (size.height - destinationSize.height) / 2,
        width: destinationSize.width,
        height: destinationSize.height
    )

    sourceImage.draw(
        in: destinationRect,
        from: .zero,
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    let ratio = size.width / 720
    let arrow = NSBezierPath()
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 323 * ratio, y: 205 * ratio))
    arrow.line(to: NSPoint(x: 397 * ratio, y: 205 * ratio))
    arrow.move(to: NSPoint(x: 376 * ratio, y: 184 * ratio))
    arrow.line(to: NSPoint(x: 397 * ratio, y: 205 * ratio))
    arrow.line(to: NSPoint(x: 376 * ratio, y: 226 * ratio))

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 9 * ratio
    shadow.shadowOffset = NSSize(width: 0, height: -2 * ratio)
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.16)
    shadow.set()
    NSColor(calibratedWhite: 1, alpha: 0.92).setStroke()
    arrow.lineWidth = 13 * ratio
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(
        calibratedRed: 0.13,
        green: 0.31,
        blue: 0.96,
        alpha: 0.96
    ).setStroke()
    arrow.lineWidth = 6 * ratio
    arrow.stroke()

    guard
        let pngData = bitmap.representation(
            using: .png,
            properties: [.compressionFactor: 0.92]
        )
    else {
        throw NSError(
            domain: "ClippyDMG",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to encode the rendered background."]
        )
    }

    return pngData
}

let outputs: [(name: String, size: NSSize)] = [
    ("background.png", NSSize(width: 720, height: 450)),
    ("background@2x.png", NSSize(width: 1_440, height: 900)),
]

for output in outputs {
    let data = try renderBackground(size: output.size)
    try data.write(
        to: outputDirectory.appendingPathComponent(output.name),
        options: .atomic
    )
}
