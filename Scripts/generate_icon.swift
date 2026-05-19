#!/usr/bin/env swift

// Generates the Ink and Echo macOS app icon at all 10 required sizes.
// Design (Claude Design "Monogram" direction — the one you locked after
// iterating on placement): a single sharp uppercase serif "P" in solid ink,
// vertically centered, with a saddle-brown horizontal rule beneath it
// nudged a few pixels left of the P's optical center. Parchment ground
// with a soft cream highlight upper-left and a faint shadow lower-right.
//
// Renders into NSBitmapImageRep at exact pixel dimensions to avoid Retina
// backing-scale doubling that NSImage.lockFocus() would introduce.
//
// Usage:
//   swift Scripts/generate_icon.swift App/Assets.xcassets/AppIcon.appiconset

import AppKit
import Foundation

let canvasSize: CGFloat = 1024

// Palette pulled from Theme.swift. Same tokens the live app uses.
let parchment    = NSColor(srgbRed: 244/255, green: 239/255, blue: 230/255, alpha: 1)
let inkSolid     = NSColor(srgbRed:  31/255, green:  26/255, blue:  20/255, alpha: 1)
let saddleAccent = NSColor(srgbRed: 139/255, green:  90/255, blue:  43/255, alpha: 1)

func makeBitmapRep(pixelSize: CGFloat) -> NSBitmapImageRep {
    let s = Int(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: s,
        pixelsHigh: s,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create bitmap rep at \(s)x\(s)")
    }
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    return rep
}

func renderMaster() -> NSBitmapImageRep {
    let rep = makeBitmapRep(pixelSize: canvasSize)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("Could not obtain CGContext")
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // 1. Flat parchment ground.
    context.setFillColor(parchment.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

    // 2. Paper grain — soft cream highlight in the upper-left, faint shadow
    // in the lower-right. Adds texture without committing to a real photo
    // grain.
    let highlight = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(srgbRed: 1.0, green: 0.97, blue: 0.90, alpha: 0.55).cgColor,
            NSColor(srgbRed: 1.0, green: 0.97, blue: 0.90, alpha: 0.00).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        highlight,
        startCenter: CGPoint(x: canvasSize * 0.30, y: canvasSize * 0.80),
        startRadius: 0,
        endCenter: CGPoint(x: canvasSize * 0.30, y: canvasSize * 0.80),
        endRadius: canvasSize * 0.55,
        options: []
    )
    let shadow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(srgbRed: 31/255, green: 26/255, blue: 20/255, alpha: 0.10).cgColor,
            NSColor(srgbRed: 31/255, green: 26/255, blue: 20/255, alpha: 0.00).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        shadow,
        startCenter: CGPoint(x: canvasSize * 0.80, y: canvasSize * 0.10),
        startRadius: 0,
        endCenter: CGPoint(x: canvasSize * 0.80, y: canvasSize * 0.10),
        endRadius: canvasSize * 0.60,
        options: []
    )

    // 3. The "P" — single sharp serif glyph, vertically centered. Compute
    // its baseline so the rule below can sit at the exact distance the
    // CSS mock locked in (lineHeight 0.78 → ≈29pt gap at 4× scale).
    let pFontSize: CGFloat = 752
    let baselineY = drawSerifLetter(
        "P",
        fontSize: pFontSize,
        weight: .semibold,
        color: inkSolid,
        offset: .zero,
        rotationDegrees: 0
    )

    // 4. Saddle-brown rule under the P. Sits ~30pt below the baseline
    // (the chat's nudge-down past the strict CSS spec), shifted 16pt
    // left of optical center to match the locked monogram.
    let ruleWidth: CGFloat = 440
    let ruleHeight: CGFloat = 12
    let ruleLeftShift: CGFloat = 16
    let ruleGapBelowBaseline: CGFloat = 30
    let ruleTopCG = baselineY - ruleGapBelowBaseline
    let ruleBottomCG = ruleTopCG - ruleHeight
    context.setFillColor(saddleAccent.cgColor)
    let ruleRect = CGRect(
        x: (canvasSize - ruleWidth) / 2 - ruleLeftShift,
        y: ruleBottomCG,
        width: ruleWidth,
        height: ruleHeight
    )
    let rulePath = CGPath(
        roundedRect: ruleRect,
        cornerWidth: ruleHeight / 2,
        cornerHeight: ruleHeight / 2,
        transform: nil
    )
    context.addPath(rulePath)
    context.fillPath()

    return rep
}

/// Draws the letter and returns the baseline y in CG (y-up) coords, so
/// the caller can place sibling marks (rules, dots, etc.) relative to it.
@discardableResult
func drawSerifLetter(
    _ string: String,
    fontSize: CGFloat,
    weight: NSFont.Weight,
    color: NSColor,
    offset: CGPoint,
    rotationDegrees: CGFloat
) -> CGFloat {
    guard let context = NSGraphicsContext.current?.cgContext else { return 0 }

    let baseFont = NSFont.systemFont(ofSize: fontSize, weight: weight)
    let serifDescriptor = baseFont.fontDescriptor.withDesign(.serif) ?? baseFont.fontDescriptor
    let font = NSFont(descriptor: serifDescriptor, size: fontSize) ?? baseFont

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let attributedString = NSAttributedString(string: string, attributes: attributes)
    let stringSize = attributedString.size()

    let drawX = (canvasSize - stringSize.width) / 2 + offset.x
    let drawY = (canvasSize - stringSize.height) / 2 + offset.y - fontSize * 0.04

    context.saveGState()
    if rotationDegrees != 0 {
        context.translateBy(x: canvasSize / 2, y: canvasSize / 2)
        context.rotate(by: rotationDegrees * .pi / 180)
        context.translateBy(x: -canvasSize / 2, y: -canvasSize / 2)
    }
    attributedString.draw(at: NSPoint(x: drawX, y: drawY))
    context.restoreGState()

    // Layout box bottom-left is (drawX, drawY) in CG y-up. The baseline
    // sits |descender| above the layout bottom (descender is negative
    // for fonts that draw below the baseline).
    return drawY + abs(font.descender)
}

func savePNG(_ master: NSBitmapImageRep, to url: URL, atSize size: CGFloat) throws {
    let outputRep = makeBitmapRep(pixelSize: size)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outputRep)
    NSGraphicsContext.current?.imageInterpolation = .high

    master.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: master.size),
        operation: .copy,
        fraction: 1.0,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high.rawValue]
    )

    guard let png = outputRep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try png.write(to: url)
}

// MARK: - Entry

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("Usage: generate_icon.swift <output_directory>\n".utf8))
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let master = renderMaster()

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixelSize) in sizes {
    let url = outputDir.appendingPathComponent(name)
    try savePNG(master, to: url, atSize: pixelSize)
    print("✓ \(name) (\(Int(pixelSize))px)")
}

print("Done. \(sizes.count) icon variants written to \(outputDir.path)")
