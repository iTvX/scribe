import Foundation
import os

/// Unified logging under the app's bundle ID, so Console can filter on it.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.itvx.inputmethod.Scribe.Settings"

    static let importer = Logger(subsystem: subsystem, category: "import")
}
