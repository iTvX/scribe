import Foundation
import ScribeConfig

/// How Scribe names itself to librime. Schemas and Lua scripts may check the
/// code name; `compatibility/report_as_squirrel` in scribe.yaml makes Scribe
/// report Squirrel's.
///
/// librime takes the names when it starts, before scribe.yaml can be read, so
/// the names from the last deploy are kept in the user defaults.
struct DistributionIdentity: Equatable {
    var name: String
    var codeName: String

    static let scribe = DistributionIdentity(name: "Scribe", codeName: "Scribe")

    init(name: String, codeName: String) {
        self.name = name
        self.codeName = codeName
    }

    init(_ compatibility: ScribeCompatibility) {
        self.init(name: compatibility.distributionName, codeName: compatibility.distributionCodeName)
    }

    private static let nameKey = "distributionName"
    private static let codeNameKey = "distributionCodeName"

    /// The names stored last, or Scribe's.
    static func stored(in defaults: UserDefaults) -> DistributionIdentity {
        guard let name = defaults.string(forKey: nameKey), !name.isEmpty,
              let codeName = defaults.string(forKey: codeNameKey), !codeName.isEmpty
        else { return .scribe }
        return DistributionIdentity(name: name, codeName: codeName)
    }

    func store(in defaults: UserDefaults) {
        defaults.set(name, forKey: Self.nameKey)
        defaults.set(codeName, forKey: Self.codeNameKey)
    }
}
