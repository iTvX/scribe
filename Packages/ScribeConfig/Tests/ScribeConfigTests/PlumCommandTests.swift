import Foundation
import ScribeConfig
import Testing

@Suite struct PlumCommandTests {
    /// A Scribe.app with rime-install next to the executable, in a directory
    /// whose name needs quoting, like /Library/Input Methods.
    func makeApp() throws -> (root: URL, shared: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "plum test \(UUID().uuidString)", directoryHint: .isDirectory)
        let contents = root.appending(path: "Input Methods/Scribe.app/Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appending(path: "SharedSupport"), withIntermediateDirectories: true)
        try "#!/usr/bin/env bash\n".write(to: contents.appending(path: "MacOS/rime-install"), atomically: true, encoding: .utf8)
        return (root, contents.appending(path: "SharedSupport", directoryHint: .isDirectory))
    }

    @Test func findsTheToolNextToScribe() throws {
        let (root, shared) = try makeApp()
        defer { try? FileManager.default.removeItem(at: root) }
        let plum = try #require(PlumCommand(sharedDirectory: shared, userDirectory: URL(filePath: "/Users/test/Library/Scribe", directoryHint: .isDirectory)))
        #expect(plum.tool.path(percentEncoded: false).hasSuffix("/Input Methods/Scribe.app/Contents/MacOS/rime-install"))
    }

    @Test func noToolNoCommand() {
        let shared = URL(filePath: "/nonexistent/Scribe.app/Contents/SharedSupport", directoryHint: .isDirectory)
        #expect(PlumCommand(sharedDirectory: shared, userDirectory: URL(filePath: "/tmp")) == nil)
    }

    @Test func theCommandInstallsIntoScribesDirectory() {
        let plum = PlumCommand(tool: URL(filePath: "/Library/Input Methods/Scribe.app/Contents/MacOS/rime-install"),
                               userDirectory: URL(filePath: "/Users/test/Library/Scribe", directoryHint: .isDirectory))
        #expect(plum.command(recipe: "iDvel/rime-ice:others/recipes/full")
            == "rime_dir='/Users/test/Library/Scribe' bash '/Library/Input Methods/Scribe.app/Contents/MacOS/rime-install' iDvel/rime-ice:others/recipes/full")
    }

    @Test func quotesWhatTheShellWouldSplit() {
        let plum = PlumCommand(tool: URL(filePath: "/Users/o'neil/Scribe.app/Contents/MacOS/rime-install"),
                               userDirectory: URL(filePath: "/Users/o'neil/Library/Scribe"))
        #expect(plum.command(recipe: "a recipe; rm -rf ~")
            == "rime_dir='/Users/o'\\''neil/Library/Scribe' bash '/Users/o'\\''neil/Scribe.app/Contents/MacOS/rime-install' 'a recipe; rm -rf ~'")
    }

    @Test func withoutARecipeTheCommandShowsWhereItGoes() {
        let plum = PlumCommand(tool: URL(filePath: "/x/rime-install"), userDirectory: URL(filePath: "/u"))
        #expect(plum.command(recipe: "  ") == "rime_dir='/u' bash '/x/rime-install' <配方>")
    }
}
