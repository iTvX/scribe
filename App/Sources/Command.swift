/// What the process was asked to do on the command line.
///
/// With no arguments, as InputMethodKit launches it, Scribe runs as the
/// input method server. Anything it does not recognize is an error, so a
/// mistyped option never starts a second server. Arguments Cocoa itself adds
/// at launch (`-psn_…`, `-NS…`, `-Apple…` defaults) are ignored.
enum Command: Equatable {
    case runServer
    case install
    case quit
    case reload
    case sync
    case selfTest
    case help
    /// Unrecognized arguments, joined by spaces.
    case invalid(String)

    init(arguments: [String]) {
        let arguments = Self.removingLaunchArguments(Array(arguments.dropFirst()))
        guard let option = arguments.first else {
            self = .runServer
            return
        }
        guard arguments.count == 1 else {
            self = .invalid(arguments.joined(separator: " "))
            return
        }
        switch option {
        case "--install": self = .install
        case "--quit": self = .quit
        case "--reload": self = .reload
        case "--sync": self = .sync
        case "--self-test": self = .selfTest
        case "--help": self = .help
        default: self = .invalid(option)
        }
    }

    static let usage = """
        Usage: Scribe [option]

          --install   register Scribe's input sources with the system
                      (does not enable or select them)
          --quit      quit every running Scribe process
          --reload    make the running Scribe redeploy its configuration
          --sync      make the running Scribe sync its user data
          --self-test check that librime and its plugins load from this app
          --help      show this help

        With no option, Scribe runs as the input method server.
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
