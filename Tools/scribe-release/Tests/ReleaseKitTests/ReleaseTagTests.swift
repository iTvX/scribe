import ReleaseKit
import Testing

@Test(arguments: [
    ("v0.1.0", "0.1.0", false),
    ("v1.2.3", "1.2.3", false),
    ("v10.20.300", "10.20.300", false),
    ("v1.0.0-alpha.1", "1.0.0-alpha.1", true),
    ("v1.0.0-beta.0", "1.0.0-beta.0", true),
    ("v2.3.4-rc.12", "2.3.4-rc.12", true),
])
func acceptedTags(tag: String, version: String, isPrerelease: Bool) throws {
    let parsed = try #require(ReleaseTag(tag))
    #expect(parsed.version == version)
    #expect(parsed.isPrerelease == isPrerelease)
    #expect(parsed.channel == (isPrerelease ? "beta" : nil))
}

@Test(arguments: [
    "", "v", "0.1.0", "v1.0", "v1", "v1.0.0.0", "V1.0.0", " v1.0.0", "v1.0.0 ", "v1.0.0\n",
    "v01.0.0", "v1.00.0", "v1.0.01", "v-1.0.0", "v1.0.0-beta", "v1.0.0-beta1", "v1.0.0-beta.01",
    "v1.0.0-BETA.1", "v1.0.0-gamma.1", "v1.0.0-beta.1.2", "v1.0.0-beta.x", "v1.0.0+1", "v1.0.0-beta.1+1",
    "v１.0.0", "appcast", "main",
])
func rejectedTags(tag: String) {
    #expect(ReleaseTag(tag) == nil)
}
