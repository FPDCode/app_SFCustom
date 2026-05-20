#!/usr/bin/env swift
// Render a macOS .icns from an Icon Composer .icon bundle.
//
// Usage:  swift render_icon.swift <path-to-.icon> <output-dir>
//
// Reads icon.json + the layered SVGs, composites them onto a 1024×1024
// canvas at the specified scales and translations, generates the
// standard iconset sizes (16…1024 @1x/@2x), and runs iconutil to
// produce AppIcon.icns.
//
// This won't reproduce Icon Composer's glass / specular / shadow
// rendering — those need Apple's private compositing pipeline — but it
// gives a clean, recognizable bitmap icon suitable for the .app bundle
// outside of Xcode's Asset Catalog flow.

import Foundation
import AppKit

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: render_icon.swift <icon-bundle> <output-dir>\n".utf8))
    exit(64)
}

let iconBundle = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDir  = URL(fileURLWithPath: CommandLine.arguments[2])
let assetsDir  = iconBundle.appendingPathComponent("Assets", isDirectory: true)
let jsonURL    = iconBundle.appendingPathComponent("icon.json")

// MARK: - Load icon.json
guard let jsonData = try? Data(contentsOf: jsonURL),
      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
      let groups = json["groups"] as? [[String: Any]]
else {
    FileHandle.standardError.write(Data("can't parse \(jsonURL.path)\n".utf8))
    exit(1)
}

struct Layer {
    var imageName: String
    var scale: CGFloat
    var translation: CGPoint
}

var layers: [Layer] = []
for group in groups {
    guard let groupLayers = group["layers"] as? [[String: Any]] else { continue }
    for layer in groupLayers {
        guard let imageName = layer["image-name"] as? String,
              let position = layer["position"] as? [String: Any]
        else { continue }
        let scale = (position["scale"] as? NSNumber)?.doubleValue ?? 1.0
        let translation = (position["translation-in-points"] as? [NSNumber])?.map(\.doubleValue) ?? [0, 0]
        let tx = translation.count > 0 ? translation[0] : 0
        let ty = translation.count > 1 ? translation[1] : 0
        layers.append(Layer(
            imageName: imageName,
            scale: CGFloat(scale),
            translation: CGPoint(x: tx, y: ty)
        ))
    }
}

guard !layers.isEmpty else {
    FileHandle.standardError.write(Data("no drawable layers in icon.json\n".utf8))
    exit(1)
}

// MARK: - Compose to a 1024×1024 PNG

let canvasSize: CGFloat = 1024
let designSize: CGFloat = 1024     // icon.json point space — Icon Composer's canonical canvas

func render() -> Data {
    let image = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
    image.lockFocus()

    // Subtle macOS-style rounded-square light background. The .icon file's
    // "fill: system-dark" implies a dark fill base, but for a generic look
    // we use a soft white-to-light-gray gradient that reads well on any
    // dock background.
    let bgRect = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    let radius: CGFloat = canvasSize * 0.2237  // Apple's macOS icon corner radius ratio
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.current?.saveGraphicsState()
    bg.addClip()

    let gradient = NSGradient(colors: [
        NSColor(red: 0.98, green: 0.99, blue: 1.00, alpha: 1.0),
        NSColor(red: 0.88, green: 0.93, blue: 0.98, alpha: 1.0),
    ])
    gradient?.draw(in: bgRect, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Center origin and y-up coordinate (NSImage already uses y-up).
    let center = CGPoint(x: canvasSize / 2, y: canvasSize / 2)

    for layer in layers {
        let url = assetsDir.appendingPathComponent(layer.imageName)
        guard let svg = NSImage(contentsOf: url) else {
            FileHandle.standardError.write(Data("warning: couldn't load \(layer.imageName)\n".utf8))
            continue
        }

        let sized = NSSize(
            width:  svg.size.width  * layer.scale,
            height: svg.size.height * layer.scale
        )
        // icon.json y is positive going down (graphics convention).
        // NSImage's coordinate system is y-up, so flip.
        let origin = CGPoint(
            x: center.x + layer.translation.x - sized.width  / 2,
            y: center.y - layer.translation.y - sized.height / 2
        )
        svg.draw(in: NSRect(origin: origin, size: sized),
                 from: .zero,
                 operation: .sourceOver,
                 fraction: 1.0)
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("couldn't encode PNG\n".utf8))
        exit(1)
    }
    return png
}

let masterPNG = render()

// MARK: - Generate iconset

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let iconset = outputDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let masterURL = iconset.appendingPathComponent("master.png")
try masterPNG.write(to: masterURL)

// Apple's required iconset sizes.
let entries: [(size: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in entries {
    let out = iconset.appendingPathComponent(name)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", "\(size)", "\(size)", masterURL.path, "--out", out.path]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus != 0 {
        FileHandle.standardError.write(Data("sips failed for \(name)\n".utf8))
        exit(1)
    }
}

// Remove the master before iconutil (it'll complain about the extra file).
try? FileManager.default.removeItem(at: masterURL)

// MARK: - Make .icns

let icnsURL = outputDir.appendingPathComponent("AppIcon.icns")
let icnsTask = Process()
icnsTask.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
icnsTask.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try icnsTask.run()
icnsTask.waitUntilExit()
if icnsTask.terminationStatus != 0 {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

print("✓ \(icnsURL.path)")
