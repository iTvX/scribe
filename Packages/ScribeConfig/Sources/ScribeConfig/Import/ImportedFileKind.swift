/// What a copied file is, judged by its path.
public enum ImportedFileKind: String, Sendable, CaseIterable {
    /// `*.schema.yaml`
    case schema
    /// `*.dict.yaml` at any depth, such as `cn_dicts/8105.dict.yaml`
    case dictionary
    /// `*.custom.yaml`, except the frontend ones below
    case customPatch
    /// `squirrel.yaml` and `squirrel.custom.yaml`
    case squirrelConfig
    /// Weasel, Hamster, ibus-rime and Trime configuration, including `*.trime.yaml`
    case otherFrontendConfig
    /// Any other `*.yaml`, such as `default.yaml`, `symbols.yaml` or `user.yaml`
    case sharedConfig
    /// `installation.yaml`, which the import writes anew
    case installation
    /// `rime.lua` and everything under `lua/`
    case lua
    /// Everything under `opencc/`
    case opencc
    /// `custom_phrase*.txt`
    case customPhrase
    /// `*.gram`
    case languageModel
    /// `.git`, as one item for the whole repository
    case gitRepository
    /// Anything else, such as a README or LICENSE
    case other

    /// How Scribe uses files of this kind.
    public var effect: ImportEffect {
        switch self {
        case .schema, .dictionary, .customPatch, .sharedConfig, .lua, .opencc, .customPhrase, .languageModel:
            .asIs
        case .squirrelConfig:
            .squirrelCompatibility
        case .installation:
            .regenerated
        case .otherFrontendConfig, .gitRepository, .other:
            .notRead
        }
    }

    private static let squirrelConfigNames: Set = ["squirrel.yaml", "squirrel.custom.yaml"]
    private static let otherFrontendConfigNames: Set = [
        "weasel.yaml", "weasel.custom.yaml",
        "hamster.yaml", "hamster.custom.yaml",
        "ibus_rime.yaml", "ibus_rime.custom.yaml",
        "trime.yaml", "trime.custom.yaml",
    ]

    /// Classifies a path relative to the Rime user directory, "/" separated.
    init(path: String) {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        if path == ".git" {
            self = .gitRepository
        } else if path == "installation.yaml" {
            self = .installation
        } else if path == "rime.lua" || path.hasPrefix("lua/") {
            self = .lua
        } else if path.hasPrefix("opencc/") {
            self = .opencc
        } else if name.hasSuffix(".schema.yaml") {
            self = .schema
        } else if name.hasSuffix(".dict.yaml") {
            self = .dictionary
        } else if Self.squirrelConfigNames.contains(name) {
            self = .squirrelConfig
        } else if Self.otherFrontendConfigNames.contains(name)
                    || name.hasSuffix(".trime.yaml") || name.hasSuffix(".trime.custom.yaml") {
            self = .otherFrontendConfig
        } else if name.hasSuffix(".custom.yaml") {
            self = .customPatch
        } else if name.hasSuffix(".yaml") {
            self = .sharedConfig
        } else if name.hasPrefix("custom_phrase") && name.hasSuffix(".txt") {
            self = .customPhrase
        } else if name.hasSuffix(".gram") {
            self = .languageModel
        } else {
            self = .other
        }
    }
}

/// How Scribe uses an imported file.
public enum ImportEffect: Sendable {
    /// librime reads it exactly as Squirrel's librime did.
    case asIs
    /// Scribe reads it through its `squirrel.yaml` compatibility layer.
    case squirrelCompatibility
    /// Written anew by the import (`installation.yaml`).
    case regenerated
    /// Copied for the user's benefit; Scribe never reads it.
    case notRead
}
