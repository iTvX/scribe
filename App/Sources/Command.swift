import ScribeCore

/// What the process was asked to do on the command line. The options follow
/// Squirrel's.
///
/// With no arguments, as InputMethodKit launches it, Scribe runs as the
/// input method server. Anything it does not recognize is an error, so a
/// mistyped option never starts a second server. Arguments Cocoa itself adds
/// at launch (`-psn_…`, `-NS…`, `-Apple…` defaults) are ignored.
enum Command: Equatable {
    case runServer
    case install
    /// No modes means the defaults described in the usage.
    case enableInputSource([InputMode])
    case disableInputSource([InputMode])
    case selectInputSource(InputMode?)
    case quit
    case reload
    case sync
    case build
    /// Turns ASCII mode on or off in the running input method.
    case ascii(Bool)
    case getASCII
    case selfTest
    /// Plays a replay file against a copy of the user's configuration.
    case replay(file: String)
    case help
    /// Unrecognized arguments, joined by spaces.
    case invalid(String)

    init(arguments: [String]) {
        let arguments = Self.removingLaunchArguments(Array(arguments.dropFirst()))
        guard let option = arguments.first else {
            self = .runServer
            return
        }
        let rest = Array(arguments.dropFirst())
        let modes = rest.map { InputMode(inputSourceID: $0, bundleIdentifier: InputSourceInstaller.bundleIdentifier) }
        let invalid = Command.invalid(arguments.joined(separator: " "))
        switch option {
        case "--enable-input-source", "--disable-input-source":
            guard !modes.contains(nil) else {
                self = invalid
                return
            }
            let modes = modes.compactMap(\.self)
            self = option == "--enable-input-source" ? .enableInputSource(modes) : .disableInputSource(modes)
            return
        case "--select-input-source":
            switch modes.count {
            case 0: self = .selectInputSource(nil)
            case 1: self = modes[0].map { .selectInputSource($0) } ?? invalid
            default: self = invalid
            }
            return
        case "--replay":
            self = rest.count == 1 ? .replay(file: rest[0]) : invalid
            return
        default:
            break
        }
        guard rest.isEmpty else {
            self = invalid
            return
        }
        switch option {
        case "--install", "--register-input-source": self = .install
        case "--quit": self = .quit
        case "--reload": self = .reload
        case "--sync": self = .sync
        case "--build": self = .build
        case "--ascii": self = .ascii(true)
        case "--nascii": self = .ascii(false)
        case "--getascii": self = .getASCII
        case "--self-test": self = .selfTest
        case "--help": self = .help
        default: self = invalid
        }
    }

    static let usage = """
        Usage: Scribe [option]

        With no option, Scribe runs as the input method server.

        Install:
          --install, --register-input-source
                      register Scribe's input sources (does not enable them)
          --enable-input-source [ID...]
                      enable these input sources; with none, enable the
                      primary one unless one is enabled already
          --disable-input-source [ID...]
                      disable these input sources, or all of them
          --select-input-source [ID]
                      select this input source, enabling it first; with
                      none, select the primary one if it is enabled
          (IDs: io.github.itvx.inputmethod.Scribe.Hans, .Hant)

        Control the running Scribe:
          --quit      quit every running Scribe process
          --reload    redeploy the configuration
          --sync      sync user data
          --ascii     turn ASCII mode on
          --nascii    turn ASCII mode off
          --getascii  print "ascii" or "nascii"

        Other:
          --build     build the schemas in the current directory
          --self-test check that librime and its plugins load from this app
          --replay FILE
                      play a replay file against a copy of ~/Library/Scribe
          --help      show this help
        """

    /// Drops the process serial number and user-defaults arguments that
    /// LaunchServices or Xcode may pass, such as "-NSFoo YES".
    private static func removingLaunchArguments(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if argument.hasPrefix("-psn_") {
                index += 1
            } else if argument.hasPrefix("-NS") || argument.hasPrefix("-Apple") {
                index += 2
            } else {
                result.append(argument)
                index += 1
            }
        }
        return result
    }
}
