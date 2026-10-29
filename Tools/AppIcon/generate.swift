// Original, dependency-free rendering of assets/AppIcon.svg for macOS icon sizes.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "assets")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let iconset = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])!
}
func render(_ size: Int) throws -> Data {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = CGPath(
        roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896), cornerWidth: 202, cornerHeight: 202, transform: nil)
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let background = CGGradient(
        colorsSpace: space, colors: [color(40, 49, 40), color(16, 22, 16)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 64, y: 960), end: CGPoint(x: 960, y: 64), options: [])
    let glow = CGGradient(
        colorsSpace: space, colors: [color(170, 201, 95, 0.13), color(170, 201, 95, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(
        glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 512), endRadius: 390, options: [])
    context.restoreGState()
    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 66, y: 66, width: 892, height: 892), cornerWidth: 200, cornerHeight: 200,
            transform: nil))
    context.setStrokeColor(color(255, 255, 255, 0.08))
    context.setLineWidth(2)
    context.strokePath()
    let letters = CGMutablePath()
    for x: CGFloat in [248, 512, 776] {
        let g = CGMutablePath()
        g.addArc(center: CGPoint(x: x, y: 512), radius: 98, startAngle: .pi / 4, endAngle: 2 * .pi, clockwise: false)
        g.addLine(to: CGPoint(x: x + 8, y: 512))
        letters.addPath(g)
    }
    context.addPath(letters)
    context.setLineWidth(52)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    let lime = CGGradient(
        colorsSpace: space, colors: [color(214, 237, 153), color(166, 198, 94)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
        lime, start: CGPoint(x: 512, y: 636), end: CGPoint(x: 512, y: 388),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}
for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try render(1024).write(to: output.appendingPathComponent("AppIcon.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil could not create AppIcon.icns. Check the system image-conversion permissions.\n", stderr)
    exit(1)
}
print("Generated three-G app icon in \(output.path)")
