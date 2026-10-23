import Foundation
import os

/// Unified logging under the app's bundle ID, so Console can filter on it.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.itvx.inputmethod.Scribe"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let installer = Logger(subsystem: subsystem, category: "installer")
}
