import Foundation
import ReleaseKit

// scribe-release: release tooling for Scripts/make-appcast.sh and release.yml.
// Bad arguments print the usage and exit 2; a failed check exits 1.

let usage = """
    usage: scribe-release <command>

      tag <tag>                  check a release tag; prints version=, prerelease= and channel=
      notes <version> <file>     print the CHANGELOG section for a version
      key new                    print a new private key (base64 Ed25519 seed)
      key public                 read a private key from standard input; print its public key
      appcast --output F [--existing F] --title T --short-version V --build B [--channel C]
              --minimum-system M --notes F --url U --package F --signature S
              [--feed-title T] [--feed-link L]
                                 write the feed with this release first
      verify --feed F --package F --url U --public-key K --build B --short-version V [--channel C]
                                 check a signed feed and its package
    """

struct UsageError: Error {
    var message: String
}

struct Options {
    private var values: [String: String] = [:]

    init(_ arguments: ArraySlice<String>, allowed: Set<String>) throws {
        var arguments = arguments
        while let name = arguments.popFirst() {
            guard name.hasPrefix("--"), allowed.contains(String(name.dropFirst(2))) else {
                throw UsageError(message: "unknown option \(name)")
            }
            guard let value = arguments.popFirst() else { throw UsageError(message: "\(name) needs a value") }
            values[String(name.dropFirst(2))] = value
        }
    }

    func required(_ name: String) throws -> String {
        guard let value = values[name], !value.isEmpty else { throw UsageError(message: "missing --\(name)") }
        return value
    }

    func optional(_ name: String) -> String? {
        values[name].flatMap { $0.isEmpty ? nil : $0 }
    }
}

func read(_ path: String) throws -> Data {
    try Data(contentsOf: URL(filePath: path))
}

func run(_ arguments: [String]) throws {
    guard let command = arguments.first else { throw UsageError(message: "missing command") }
    let rest = arguments.dropFirst()
    switch command {
    case "tag":
        guard rest.count == 1, let tag = ReleaseTag(rest[rest.startIndex]) else {
            throw UsageError(message: "expected a tag such as v1.2.3 or v1.2.3-beta.1")
        }
        print("version=\(tag.version)")
        print("prerelease=\(tag.isPrerelease)")
        print("channel=\(tag.channel ?? "")")

    case "notes":
        guard rest.count == 2 else { throw UsageError(message: "expected a version and a changelog") }
        let version = rest[rest.startIndex]
        let changelog = String(decoding: try read(rest[rest.startIndex + 1]), as: UTF8.self)
        guard let section = ReleaseNotes.section(for: version, in: changelog) else {
            throw Failure("the changelog has no \"## \(version)\" section, or it is empty")
        }
        print(section)

    case "key":
        switch Array(rest) {
        case ["new"]:
            print(EdDSA.newPrivateKey())
        case ["public"]:
            guard let line = readLine(strippingNewline: true) else { throw Failure("no private key on standard input") }
            print(try EdDSA.publicKey(forPrivateKey: line))
        default:
            throw UsageError(message: "expected key new or key public")
        }

    case "appcast":
        let options = try Options(rest, allowed: [
            "output", "existing", "title", "short-version", "build", "channel", "minimum-system", "notes", "url",
            "package", "signature", "feed-title", "feed-link",
        ])
        let output = try options.required("output")
        let attributes = try FileManager.default.attributesOfItem(atPath: try options.required("package"))
        let item = AppcastItem(
            title: try options.required("title"),
            shortVersion: try options.required("short-version"),
            build: try options.required("build"),
            channel: options.optional("channel"),
            minimumSystemVersion: try options.required("minimum-system"),
            publicationDate: Date(),
            notes: String(decoding: try read(try options.required("notes")), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            url: try options.required("url"),
            length: (attributes[.size] as? NSNumber)?.intValue ?? 0,
            edSignature: try options.required("signature")
        )
        let feed = try Appcast.make(
            item: item,
            existing: try options.optional("existing").map(read),
            feedTitle: options.optional("feed-title") ?? "中书 Scribe",
            feedLink: options.optional("feed-link") ?? "https://github.com/iTvX/scribe"
        )
        try feed.write(to: URL(filePath: output), options: .atomic)

    case "verify":
        let options = try Options(rest, allowed: [
            "feed", "package", "url", "public-key", "build", "short-version", "channel",
        ])
        try UpdateVerification.verify(
            feed: try read(try options.required("feed")),
            package: try read(try options.required("package")),
            url: try options.required("url"),
            publicKey: try options.required("public-key"),
            build: try options.required("build"),
            shortVersion: try options.required("short-version"),
            channel: options.optional("channel")
        )
        print("The feed and the package verify with this public key")

    default:
        throw UsageError(message: "unknown command \(command)")
    }
}

struct Failure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch let error as UsageError {
    FileHandle.standardError.write(Data("error: \(error.message)\n\n\(usage)\n".utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
