import librime
import RimeKit
import Testing

@Test func cAPIReportsBundledVersion() throws {
    let api = try #require(rime_get_api_stdbool())
    let getVersion = try #require(api.pointee.get_version)
    let version = try #require(getVersion())
    #expect(String(cString: version) == "1.17.0")
}

@Test func versionMatchesCAPI() {
    #expect(Librime.version == "1.17.0")
}
