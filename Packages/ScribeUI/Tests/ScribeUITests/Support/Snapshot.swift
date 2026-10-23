import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

/// Compares rendered images with the PNG baselines in
/// `Tests/Fixtures/snapshots/scribe/<suite>/<name>.png`.
///
/// Run with `SCRIBE_RECORD_SNAPSHOTS=1` to write baselines; recording fails
/// the test so it never passes silently. On a mismatch the expected, actual
/// and diff images go to `$SCRIBE_SNAPSHOT_ARTIFACTS` (by default
/// `build/snapshot-failures`), which CI uploads.
enum Snapshot {
    /// A pixel differs when any channel, alpha included, is further apart
    /// than this, out of 255. Two units absorb the rounding of semi-
    /// transparent pixels through PNG's straight alpha.
    static let channelTolerance = 4
    /// The share of differing pixels an image may have and still match:
    /// a few stray anti-aliased pixels, never a moved edge or a new colour.
    static let maxDifferingFraction = 0.0005

    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // ScribeUITests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // ScribeUI
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()

    static func baselineURL(suite: String, name: String) -> URL {
        repositoryRoot.appending(path: "Tests/Fixtures/snapshots/scribe/\(suite)/\(name).png")
    }

    static var artifactsDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["SCRIBE_SNAPSHOT_ARTIFACTS"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return repositoryRoot.appending(path: "build/snapshot-failures")
    }

    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["SCRIBE_RECORD_SNAPSHOTS"] == "1"
    }

    /// Checks `image` against its baseline, recording or reporting as
    /// described above.
    static func check(_ image: CGImage?, suite: String, name: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let image else {
            Issue.record("Nothing was rendered for \(suite)/\(name)", sourceLocation: sourceLocation)
            return
        }
        let baseline = baselineURL(suite: suite, name: name)
        if isRecording {
            do {
                try write(image, to: baseline)
                Issue.record("Recorded \(baseline.path); run again without SCRIBE_RECORD_SNAPSHOTS", sourceLocation: sourceLocation)
            } catch {
                Issue.record("Could not record \(baseline.path): \(error)", sourceLocation: sourceLocation)
            }
            return
        }
        let failures = artifactsDirectory.appending(path: suite)
        guard let expected = read(baseline) else {
            let actualURL = failures.appending(path: "\(name)-actual.png")
            try? write(image, to: actualURL)
            Issue.record(
                "No baseline at \(baseline.path); record it with SCRIBE_RECORD_SNAPSHOTS=1 (this render is in \(actualURL.path))",
                sourceLocation: sourceLocation
            )
            return
        }
        let comparison = Comparison(expected: expected, actual: image)
        guard !comparison.matches else { return }
        try? write(expected, to: failures.appending(path: "\(name)-expected.png"))
        try? write(image, to: failures.appending(path: "\(name)-actual.png"))
        if let diff = comparison.diffImage {
            try? write(diff, to: failures.appending(path: "\(name)-diff.png"))
        }
        Issue.record("\(suite)/\(name) does not match its baseline: \(comparison); images in \(failures.path)", sourceLocation: sourceLocation)
    }

    /// The outcome of comparing two images pixel by pixel.
    struct Comparison: CustomStringConvertible {
        var expectedSize: (width: Int, height: Int)
        var actualSize: (width: Int, height: Int)
        var differingPixels = 0
        var largestChannelDifference = 0
        var diffImage: CGImage?

        init(expected: CGImage, actual: CGImage) {
            expectedSize = (expected.width, expected.height)
            actualSize = (actual.width, actual.height)
            guard expectedSize == actualSize else { return }
            let expectedPixels = Snapshot.pixels(of: expected)
            let actualPixels = Snapshot.pixels(of: actual)
            var diff = [UInt8](repeating: 0, count: expectedPixels.count)
            for pixel in stride(from: 0, to: expectedPixels.count, by: 4) {
                var largest = 0
                for channel in 0..<4 {
                    largest = max(largest, abs(Int(expectedPixels[pixel + channel]) - Int(actualPixels[pixel + channel])))
                }
                largestChannelDifference = max(largestChannelDifference, largest)
                if largest > Snapshot.channelTolerance {
                    differingPixels += 1
                    diff[pixel] = 255
                    diff[pixel + 3] = 255
                } else {
                    // The expected image, faint, for orientation.
                    for channel in 0..<4 {
                        diff[pixel + channel] = expectedPixels[pixel + channel] / 4
                    }
                }
            }
            diffImage = Snapshot.image(from: diff, width: expected.width, height: expected.height)
        }

        var sizesMatch: Bool {
            expectedSize == actualSize
        }

        var differingFraction: Double {
            Double(differingPixels) / Double(max(1, expectedSize.width * expectedSize.height))
        }

        var matches: Bool {
            sizesMatch && differingFraction <= Snapshot.maxDifferingFraction
        }

        var description: String {
            if !sizesMatch {
                return "size \(actualSize.width)×\(actualSize.height) instead of \(expectedSize.width)×\(expectedSize.height) pixels"
            }
            let percent = (differingFraction * 100).formatted(.number.precision(.fractionLength(3)))
            return "\(differingPixels) pixels (\(percent)%) differ, by up to \(largestChannelDifference)/255"
        }
    }

    /// The pixels of `image` as premultiplied 8-bit sRGB RGBA, top row
    /// first.
    static func pixels(of image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.setBlendMode(.copy)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    /// The colour at a point, in points from the top left of a 2× image, as
    /// premultiplied 8-bit RGBA.
    static func pixel(of image: CGImage, x: CGFloat, y: CGFloat, scale: CGFloat = 2) -> [UInt8] {
        let pixels = pixels(of: image)
        let index = (Int(y * scale) * image.width + Int(x * scale)) * 4
        return Array(pixels[index..<(index + 4)])
    }

    static func image(from pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    static func read(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}
