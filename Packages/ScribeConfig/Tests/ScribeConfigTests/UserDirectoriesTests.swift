import Foundation
import ScribeConfig
import Testing

@Test func directoriesLiveUnderLibrary() {
    let directories = UserDirectories(home: URL(filePath: "/Users/test", directoryHint: .isDirectory))
    #expect(directories.scribe.path(percentEncoded: false) == "/Users/test/Library/Scribe/")
    #expect(directories.squirrel.path(percentEncoded: false) == "/Users/test/Library/Rime/")
}
