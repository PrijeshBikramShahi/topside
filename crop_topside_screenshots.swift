import AppKit
import Foundation

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let inputDir = root.appendingPathComponent("assets/screenshots")
let outputDir = inputDir.appendingPathComponent("closeups")
try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

let names = ["idle", "clock_hover", "clock_focused", "battery_hover", "battery_focused", "spotify_hover", "spotify_focused"]

for name in names {
    let input = inputDir.appendingPathComponent("\(name).png")
    guard fm.fileExists(atPath: input.path) else {
        fputs("Missing \(input.path)\n", stderr)
        continue
    }
    guard let image = NSImage(contentsOf: input),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fputs("Could not read \(input.path)\n", stderr)
        continue
    }
    // Crop around the screen's top-center island, retaining a little desktop context.
    let width = min(900, cgImage.width)
    let height = min(240, cgImage.height)
    let rect = CGRect(x: (cgImage.width - width) / 2, y: 0, width: width, height: height)
    guard let cropped = cgImage.cropping(to: rect),
          let png = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) else {
        fputs("Could not crop \(name)\n", stderr)
        continue
    }
    let output = outputDir.appendingPathComponent("\(name).png")
    try png.write(to: output)
    print("Created \(output.path) (\(width)×\(height))")
}
