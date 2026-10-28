import Foundation
@testable import ScribeConfig
import Testing

struct ImportLinkIsolationTests {
    @Test func externalDirectoriesAreIndependentAndCyclesAreReported() throws {
        let fake = try FakeRimeDirectory()
        defer { fake.remove() }
        let fm = FileManager.default
        let external = fake.root.appending(path: "shared")
        try fm.createDirectory(at: external, withIntermediateDirectories: true)
        let content = external.appending(path: "options.yaml")
        try "value: original\n".write(to: content, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: external.appending(path: "cycle"), withDestinationURL: external)
        try fm.createSymbolicLink(at: fake.url("nested"), withDestinationURL: external)
        try fm.createSymbolicLink(at: fake.url("back-to-root"), withDestinationURL: fake.source)
        let report = try RimeDirectoryImporter(source: fake.source, destination: fake.destination).run()
        let copied = fake.destination.appending(path: "nested/options.yaml")
        try "value: edited\n".write(to: copied, atomically: true, encoding: .utf8)
        #expect(try String(contentsOf: content, encoding: .utf8) == "value: original\n")
        #expect(!itemExists(fake.destination.appending(path: "nested/cycle")))
        #expect(!itemExists(fake.destination.appending(path: "back-to-root")))
        for path in ["nested/cycle", "back-to-root"] {
            #expect(report.skipped.contains(SkippedItem(path: path, reason: .unavailableLink)))
        }
        #expect(report.notices.contains(.copiedSymbolicLink(path: "nested", target: external.path)))
    }
}
