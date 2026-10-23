/// What the process was asked to do on the command line.
///
/// As in Squirrel, an unrecognized argument is ignored and the input method
/// server starts.
enum Command: Equatable {
    case runServer
    case install
    case quit
    case help

    init(arguments: [String]) {
        switch arguments.dropFirst().first {
        case "--install": self = .install
        case "--quit": self = .quit
        case "--help": self = .help
        default: self = .runServer
        }
    }

    static let usage = """
        Usage: Scribe [option]

          --install   register Scribe's input sources with the system
                      (does not enable or select them)
          --quit      quit every running Scribe process
          --help      show this help

        With no option, Scribe runs as the input method server.
        """
}
