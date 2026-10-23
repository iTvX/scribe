import AppKit
import Metal
import ObjectiveC
import QuartzCore

// squirrel-oracle <cases.json> <output directory> [case name ...]
//
// Shows each case in Squirrel's own SquirrelPanel, then composites the
// window's layers with CARenderer into <output>/<suite>/<name>.png: the
// panel's area only, at 2x, in sRGB. Also writes <output>/screen.json, the
// screen Squirrel laid the text out for.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail("usage: squirrel-oracle <cases.json> <output directory> [case name ...]") }
let casesURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let only = Set(arguments.dropFirst(3))

let cases: Cases
do {
    cases = try JSONDecoder().decode(Cases.self, from: Data(contentsOf: casesURL))
} catch {
    fail("cannot read \(casesURL.path): \(error)")
}

// Lay out and draw as on a Retina screen, whatever screen this Mac has:
// TextKit snaps its line layers to the window's backing grid, so the scale
// must be right before layout, not only when drawing.
for (cls, selector) in [(NSWindow.self, #selector(getter: NSWindow.backingScaleFactor)), (NSScreen.self, #selector(getter: NSScreen.backingScaleFactor))] {
    if let method = class_getInstanceMethod(cls, selector) {
        let retina: @convention(block) (AnyObject) -> CGFloat = { _ in 2 }
        method_setImplementation(method, imp_implementationWithBlock(retina))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.main else { fail("no screen") }
guard let device = MTLCreateSystemDefaultDevice() else { fail("no Metal device") }
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

/// Shows `content` in a new panel and returns it once its layers are drawn,
/// along with the alpha Squirrel gave the window.
@MainActor
func show(_ content: Cases.Content, config: SquirrelConfig, dark: Bool) -> (SquirrelPanel, CGFloat) {
    app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    // Upper middle of the screen, with room on every side.
    let caret = NSRect(x: screen.frame.midX, y: screen.frame.midY + 100, width: 1, height: 18)
    let panel = SquirrelPanel(position: caret)
    panel.load(config: config, forDarkMode: false)
    panel.load(config: config, forDarkMode: true)
    let controller = SquirrelInputController()
    if let accent = content.accent, !accent.isEmpty {
        controller.specialCommentIndices[.commentHighlight] = Set(accent)
    }
    if let warning = content.warning, !warning.isEmpty {
        controller.specialCommentIndices[.commentWarning] = Set(warning)
    }
    panel.inputController = controller

    if let status = content.status {
        panel.updateStatus(long: status, short: status)
        panel.update(preedit: "", selRange: .empty, caretPos: 0, candidates: [], comments: [], labels: [],
                     highlighted: 0, page: 0, lastPage: true, update: true)
    } else {
        // A case's preedit is what SquirrelInputController passes on: it
        // leaves the preedit out when it is inline for the app.
        let preedit = content.preedit
        let selection = preedit.map { NSRange(location: $0.selection[0], length: $0.selection[1] - $0.selection[0]) } ?? .empty
        let labels = content.labels ?? content.candidates.indices.map { "\($0 + 1)" }
        panel.update(
            preedit: preedit?.text ?? "",
            selRange: selection,
            caretPos: preedit?.caret ?? 0,
            candidates: content.candidates.map(\.text),
            comments: content.candidates.map { $0.comment ?? "" },
            labels: labels,
            highlighted: content.highlighted ?? 0,
            page: content.page ?? 0,
            lastPage: content.lastPage ?? true,
            update: true
        )
    }
    // Keep the window off the screen while it draws; the alpha is applied
    // when compositing instead. The translucent backdrop shows what is
    // behind the window, so it is left out, as in Scribe's renders.
    let alpha = panel.alphaValue
    panel.alphaValue = 0
    panel.contentView?.subviews.first?.isHidden = true
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    return (panel, alpha)
}

/// The window's layers composited, cut to the panel's area.
@MainActor
func render(_ panel: SquirrelPanel, alpha: CGFloat) -> CGImage {
    guard let contentView = panel.contentView, let root = contentView.superview?.layer,
          let view = contentView.subviews.first(where: { $0 is SquirrelView }) else { fail("panel has no layers") }
    // AppKit rounds the window and its content view to whole points, which
    // can leave the panel view at a fraction of a point. The corner the
    // panel draws from (top left, or top right when turned for vertical
    // text) goes on a pixel corner, as in Scribe's renders, so no layer is
    // resampled.
    // Turning leaves rounding errors such as 59.00000000000002 points.
    func snapped(_ value: CGFloat) -> CGFloat {
        (value * 1_000_000).rounded() / 1_000_000
    }
    let converted = view.convert(view.bounds, to: nil)
    let area = CGRect(x: snapped(converted.minX), y: snapped(converted.minY), width: snapped(converted.width), height: snapped(converted.height))
    let origin = view.convert(NSPoint.zero, to: nil)
    let scale: CGFloat = 2
    let width = Int((area.width * scale).rounded(.up))
    let height = Int((area.height * scale).rounded(.up))
    let (widthPoints, heightPoints) = (CGFloat(width) / scale, CGFloat(height) / scale)
    let shift = CGPoint(
        x: abs(origin.x - area.minX) < abs(origin.x - area.maxX) ? -area.minX : widthPoints - area.maxX,
        y: abs(origin.y - area.maxY) < abs(origin.y - area.minY) ? heightPoints - area.maxY : -area.minY
    )
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: descriptor) else { fail("cannot make a texture") }
    let renderer = CARenderer(mtlTexture: texture, options: [kCARendererColorSpace: colorSpace])
    let holder = CALayer()
    holder.anchorPoint = .zero
    holder.bounds = CGRect(x: 0, y: 0, width: width, height: height)
    holder.sublayerTransform = CATransform3DMakeScale(scale, scale, 1)
    root.removeFromSuperlayer()
    root.anchorPoint = .zero
    root.position = shift
    root.opacity = Float(alpha)
    holder.addSublayer(root)
    renderer.layer = holder
    renderer.bounds = holder.bounds
    CATransaction.flush()
    renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
    renderer.addUpdate(renderer.bounds)
    renderer.render()
    renderer.endFrame()
    // CARenderer has no completion handler; give the GPU a moment.
    usleep(200_000)

    // Texture rows run bottom up.
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    var rows = [UInt8](repeating: 0, count: pixels.count)
    for row in 0..<height {
        let source = (height - 1 - row) * width * 4
        rows[(row * width * 4)..<((row + 1) * width * 4)] = pixels[source..<(source + width * 4)]
    }
    guard let provider = CGDataProvider(data: Data(rows) as CFData),
          let image = CGImage(
              width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
              bytesPerRow: width * 4, space: colorSpace,
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
          ) else { fail("cannot make an image") }
    return image
}

func write(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

MainActor.assumeIsolated {
    var rendered = 0
    for (suite, suiteCases) in cases.suites.sorted(by: { $0.key < $1.key }) {
        for testCase in suiteCases where only.isEmpty || only.contains(testCase.name) {
            let config: [String: String]
            do {
                config = try cases.config(for: testCase, configs: casesURL.deletingLastPathComponent().appending(path: "configs"))
            } catch {
                fail("cannot read the config of \(testCase.name): \(error)")
            }
            let (panel, alpha) = show(cases.content(for: testCase), config: SquirrelConfig(config), dark: testCase.dark ?? false)
            let image = render(panel, alpha: alpha)
            panel.orderOut(nil)
            write(image, to: outputURL.appending(path: "\(suite)/\(testCase.name).png"))
            print("\(suite)/\(testCase.name)")
            rendered += 1
        }
    }
    let size = screen.frame.size
    let screenJSON = "{\n  \"width\": \(Int(size.width)),\n  \"height\": \(Int(size.height))\n}\n"
    try? Data(screenJSON.utf8).write(to: outputURL.appending(path: "screen.json"))
    print("Rendered \(rendered) cases for a \(Int(size.width))×\(Int(size.height)) screen")
}
