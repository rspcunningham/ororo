// Draws the app icon and Top Shelf images into the asset catalog.
//
//     swift scripts/make-app-icon.swift
//
// The icon is a two-layer image stack (background gradient, "ORORO" wordmark)
// so tvOS can give it the parallax effect when it is focused.

import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()
let brand = root.appendingPathComponent("OroroTV/Assets.xcassets/App Icon & Top Shelf Image.brandassets")

let top = CGColor(srgbRed: 0x2a / 255, green: 0x17 / 255, blue: 0x40 / 255, alpha: 1)
let bottom = CGColor(srgbRed: 0x0d / 255, green: 0x0a / 255, blue: 0x14 / 255, alpha: 1)

enum Layer { case back, front, flat }

/// Renders one layer at a pixel size. `wordmarkWidth` is the wordmark's width
/// as a fraction of the image width.
func png(_ layer: Layer, width: Int, height: Int, wordmarkWidth: CGFloat) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let w = CGFloat(width), h = CGFloat(height)

    if layer != .front {
        let gradient = CGGradient(colorsSpace: nil, colors: [top, bottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
    }

    if layer != .back {
        // Size the wordmark by measuring it at 100pt, then scaling to the target width.
        func line(size: CGFloat) -> CTLine {
            let font = NSFont.systemFont(ofSize: size, weight: .heavy)
            let text = NSAttributedString(string: "ORORO", attributes: [
                .font: font, .foregroundColor: NSColor.white, .kern: size * 0.02,
            ])
            return CTLineCreateWithAttributedString(text)
        }
        let size = 100 * (w * wordmarkWidth) / CTLineGetImageBounds(line(size: 100), nil).width
        let wordmark = line(size: size)
        let bounds = CTLineGetImageBounds(wordmark, ctx)
        ctx.textPosition = CGPoint(x: (w - bounds.width) / 2 - bounds.minX,
                                   y: (h - bounds.height) / 2 - bounds.minY)
        CTLineDraw(wordmark, ctx)
    }

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func write(_ json: String, to dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

let info = #""info" : { "author" : "xcode", "version" : 1 }"#

/// Writes an imageset holding one image per scale.
func imageset(_ dir: URL, name: String, scales: [Int], width: Int, height: Int,
              layer: Layer, wordmarkWidth: CGFloat) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var images: [String] = []
    for scale in scales {
        let file = "\(name)@\(scale)x.png"
        try png(layer, width: width * scale, height: height * scale, wordmarkWidth: wordmarkWidth)
            .write(to: dir.appendingPathComponent(file))
        images.append(#"{ "filename" : "\#(file)", "idiom" : "tv", "scale" : "\#(scale)x" }"#)
    }
    try write("{ \"images\" : [ \(images.joined(separator: ", ")) ], \(info) }\n", to: dir)
}

/// Writes an image stack with a background and a wordmark layer.
func imagestack(_ name: String, scales: [Int], width: Int, height: Int) throws {
    let stack = brand.appendingPathComponent("\(name).imagestack")
    for (layerName, layer) in [("Front", Layer.front), ("Back", Layer.back)] {
        let dir = stack.appendingPathComponent("\(layerName).imagestacklayer")
        try imageset(dir.appendingPathComponent("Content.imageset"), name: layerName.lowercased(),
                     scales: scales, width: width, height: height, layer: layer, wordmarkWidth: 0.66)
        try write("{ \(info) }\n", to: dir)
    }
    try write(#"{ "layers" : [ { "filename" : "Front.imagestacklayer" }, { "filename" : "Back.imagestacklayer" } ], \#(info) }"# + "\n", to: stack)
}

try? FileManager.default.removeItem(at: brand)
try imagestack("App Icon", scales: [1, 2], width: 400, height: 240)
try imagestack("App Icon - App Store", scales: [1], width: 1280, height: 768)
try imageset(brand.appendingPathComponent("Top Shelf Image.imageset"), name: "top-shelf",
             scales: [1, 2], width: 1920, height: 720, layer: .flat, wordmarkWidth: 0.3)
try imageset(brand.appendingPathComponent("Top Shelf Image Wide.imageset"), name: "top-shelf-wide",
             scales: [1, 2], width: 2320, height: 720, layer: .flat, wordmarkWidth: 0.25)
try write("""
{
  "assets" : [
    { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
    { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
    { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" },
    { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" }
  ],
  \(info)
}

""", to: brand)
print("Wrote \(brand.path)")
