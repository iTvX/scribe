import Foundation

/// One release in the appcast. The enclosure is a bare .pkg, which Sparkle
/// installs as a guided package: it asks for an administrator, runs the
/// installer and relaunches the app.
public struct AppcastItem: Equatable, Sendable {
    public var title: String
    public var shortVersion: String
    /// sparkle:version, compared with CFBundleVersion: a UTC timestamp such
    /// as 20261023120000, so later builds are always greater.
    public var build: String
    /// nil for the default channel.
    public var channel: String?
    public var minimumSystemVersion: String
    public var publicationDate: Date
    /// Markdown.
    public var notes: String
    public var url: String
    public var length: Int
    public var edSignature: String
    public var installationType: String

    public init(
        title: String, shortVersion: String, build: String, channel: String?, minimumSystemVersion: String,
        publicationDate: Date, notes: String, url: String, length: Int, edSignature: String,
        installationType: String = "package"
    ) {
        self.title = title
        self.shortVersion = shortVersion
        self.build = build
        self.channel = channel
        self.minimumSystemVersion = minimumSystemVersion
        self.publicationDate = publicationDate
        self.notes = notes
        self.url = url
        self.length = length
        self.edSignature = edSignature
        self.installationType = installationType
    }
}

/// The Sparkle feed that installed copies of Scribe check for updates.
public enum Appcast {
    public static let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case notAFeed(String)
        case buildNotNumeric(String)
        case existingBuildNotNumeric(String)
        case notNewer(existing: String, new: String)
        case malformedItem(String)

        public var description: String {
            switch self {
            case .notAFeed(let reason): "the existing feed is not an RSS feed: \(reason)"
            case .buildNotNumeric(let build): "build \"\(build)\" is not all digits"
            case .existingBuildNotNumeric(let build): "the existing feed has an item whose sparkle:version \"\(build)\" is not all digits"
            case .notNewer(let existing, let new):
                "the existing feed has build \(existing), which is not older than build \(new); Sparkle never offers a lower build"
            case .malformedItem(let reason): "malformed appcast item: \(reason)"
            }
        }
    }

    /// A feed with `item` first. With an existing feed, its signature and
    /// comments are dropped, and so are items `item` replaces: those with the
    /// same download URL, or the same build in the same channel. Every
    /// remaining item must have an older build.
    public static func make(item: AppcastItem, existing: Data?, feedTitle: String, feedLink: String) throws -> Data {
        guard isDigits(item.build) else { throw Error.buildNotNumeric(item.build) }

        let document: XMLDocument
        let channel: XMLElement
        if let existing {
            document = try parse(existing)
            guard let root = document.rootElement(), root.name == "rss" else {
                throw Error.notAFeed("no rss element")
            }
            guard let found = root.elements(forName: "channel").first else {
                throw Error.notAFeed("no channel element")
            }
            channel = found
            for old in channel.elements(forName: "item") {
                let enclosure = old.elements(forName: "enclosure").first
                let replaced = enclosure?.attribute(forName: "url")?.stringValue == item.url
                    || (build(of: old) == item.build && sparkleValue("channel", in: old) == item.channel)
                if replaced {
                    old.detach()
                }
            }
            for old in channel.elements(forName: "item") {
                guard let build = build(of: old), isDigits(build) else {
                    throw Error.existingBuildNotNumeric(build(of: old) ?? "")
                }
                guard isLess(build, than: item.build) else {
                    throw Error.notNewer(existing: build, new: item.build)
                }
            }
        } else {
            let root = XMLElement(name: "rss")
            root.addAttribute(attribute("version", "2.0"))
            if let namespace = XMLNode.namespace(withName: "sparkle", stringValue: sparkleNamespace) as? XMLNode {
                root.addNamespace(namespace)
            }
            channel = XMLElement(name: "channel")
            channel.addChild(XMLElement(name: "title", stringValue: feedTitle))
            channel.addChild(XMLElement(name: "link", stringValue: feedLink))
            channel.addChild(XMLElement(name: "description", stringValue: "\(feedTitle) 的更新"))
            channel.addChild(XMLElement(name: "language", stringValue: "zh"))
            root.addChild(channel)
            document = XMLDocument(rootElement: root)
        }

        let element = makeElement(item)
        if let first = channel.elements(forName: "item").first {
            channel.insertChild(element, at: first.index)
        } else {
            channel.addChild(element)
        }
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        var data = document.xmlData(options: [.nodePrettyPrint, .nodeCompactEmptyElement, .nodePreserveCDATA])
        data.append(Data("\n".utf8))
        return data
    }

    /// The feed's items, in order. A signature block is ignored.
    public static func items(in data: Data) throws -> [AppcastItem] {
        let document = try parse(data)
        guard let channel = document.rootElement()?.elements(forName: "channel").first else {
            throw Error.notAFeed("no channel element")
        }
        return try channel.elements(forName: "item").map(parseItem)
    }

    // MARK: - Reading

    private static func parse(_ data: Data) throws -> XMLDocument {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: SignedFeed.split(data).content, options: [.nodeLoadExternalEntitiesNever, .nodePreserveCDATA])
        } catch {
            throw Error.notAFeed(error.localizedDescription)
        }
        removeComments(in: document)
        return document
    }

    /// Including sign_update's warning at the top.
    private static func removeComments(in node: XMLNode) {
        for child in node.children ?? [] {
            if child.kind == .comment {
                child.detach()
            } else {
                removeComments(in: child)
            }
        }
    }

    private static func sparkleValue(_ name: String, in item: XMLElement) -> String? {
        item.elements(forLocalName: name, uri: sparkleNamespace).first?.stringValue
    }

    /// The sparkle:version element, or the enclosure attribute older feeds use.
    private static func build(of item: XMLElement) -> String? {
        sparkleValue("version", in: item)
            ?? item.elements(forName: "enclosure").first?.attribute(forLocalName: "version", uri: sparkleNamespace)?.stringValue
    }

    private static func parseItem(_ item: XMLElement) throws -> AppcastItem {
        func required(_ value: String?, _ name: String) throws -> String {
            guard let value, !value.isEmpty else { throw Error.malformedItem("an item has no \(name)") }
            return value
        }
        let enclosure = try item.elements(forName: "enclosure").first ?? { throw Error.malformedItem("an item has no enclosure") }()
        let date = try required(item.elements(forName: "pubDate").first?.stringValue, "pubDate")
        guard let publicationDate = dateFormatter().date(from: date) else {
            throw Error.malformedItem("pubDate \"\(date)\" is not an RFC 822 date")
        }
        let length = try required(enclosure.attribute(forName: "length")?.stringValue, "enclosure length")
        guard let bytes = Int(length), bytes >= 0 else {
            throw Error.malformedItem("enclosure length \"\(length)\" is not a number")
        }
        return AppcastItem(
            title: try required(item.elements(forName: "title").first?.stringValue, "title"),
            shortVersion: try required(sparkleValue("shortVersionString", in: item), "sparkle:shortVersionString"),
            build: try required(build(of: item), "sparkle:version"),
            channel: sparkleValue("channel", in: item),
            minimumSystemVersion: try required(sparkleValue("minimumSystemVersion", in: item), "sparkle:minimumSystemVersion"),
            publicationDate: publicationDate,
            notes: item.elements(forName: "description").first?.stringValue ?? "",
            url: try required(enclosure.attribute(forName: "url")?.stringValue, "enclosure url"),
            length: bytes,
            edSignature: try required(enclosure.attribute(forLocalName: "edSignature", uri: sparkleNamespace)?.stringValue, "sparkle:edSignature"),
            installationType: try required(enclosure.attribute(forLocalName: "installationType", uri: sparkleNamespace)?.stringValue, "sparkle:installationType")
        )
    }

    // MARK: - Writing

    private static func makeElement(_ item: AppcastItem) -> XMLElement {
        let element = XMLElement(name: "item")
        element.addChild(XMLElement(name: "title", stringValue: item.title))
        element.addChild(XMLElement(name: "pubDate", stringValue: dateFormatter().string(from: item.publicationDate)))
        element.addChild(sparkleElement("version", item.build))
        element.addChild(sparkleElement("shortVersionString", item.shortVersion))
        if let channel = item.channel {
            element.addChild(sparkleElement("channel", channel))
        }
        element.addChild(sparkleElement("minimumSystemVersion", item.minimumSystemVersion))

        let description = XMLElement(name: "description")
        description.addAttribute(sparkleAttribute("format", "markdown"))
        // CDATA cannot hold its own terminator; such notes are escaped instead.
        let notes = XMLNode(kind: .text, options: item.notes.contains("]]>") ? [] : .nodeIsCDATA)
        notes.stringValue = item.notes
        description.addChild(notes)
        element.addChild(description)

        let enclosure = XMLElement(name: "enclosure")
        enclosure.addAttribute(attribute("url", item.url))
        enclosure.addAttribute(attribute("length", String(item.length)))
        enclosure.addAttribute(attribute("type", "application/octet-stream"))
        enclosure.addAttribute(sparkleAttribute("edSignature", item.edSignature))
        enclosure.addAttribute(sparkleAttribute("installationType", item.installationType))
        element.addChild(enclosure)
        return element
    }

    private static func sparkleElement(_ name: String, _ value: String) -> XMLElement {
        let element = XMLElement(name: "sparkle:\(name)", uri: sparkleNamespace)
        element.stringValue = value
        return element
    }

    private static func attribute(_ name: String, _ value: String) -> XMLNode {
        let node = XMLNode(kind: .attribute)
        node.name = name
        node.stringValue = value
        return node
    }

    private static func sparkleAttribute(_ name: String, _ value: String) -> XMLNode {
        let node = XMLNode(kind: .attribute)
        node.name = "sparkle:\(name)"
        node.uri = sparkleNamespace
        node.stringValue = value
        return node
    }

    /// RFC 822, as RSS expects.
    static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }

    static func isDigits(_ string: String) -> Bool {
        !string.isEmpty && string.allSatisfy(\.isASCIIDigit)
    }

    /// Compares strings of digits as numbers, however long.
    static func isLess(_ lhs: String, than rhs: String) -> Bool {
        let lhs = lhs.drop(while: { $0 == "0" })
        let rhs = rhs.drop(while: { $0 == "0" })
        return lhs.count != rhs.count ? lhs.count < rhs.count : lhs < rhs
    }
}
